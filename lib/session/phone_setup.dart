import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/core/logging/log_value.dart';
import 'package:sirf_hum/security/device/device_registration.dart';
import 'package:sirf_hum/security/device/device_trust_service.dart';
import 'package:sirf_hum/security/device/local_device_identity.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// Where setting this phone up again stands (D-159). ID-free and
/// content-free: safe to render.
sealed class PhoneSetupStep {
  const PhoneSetupStep();
}

/// This phone is a trusted device of the account: private services can
/// open.
final class PhoneSetupDone extends PhoneSetupStep {
  const PhoneSetupDone({required this.newIdentity});

  /// The phone now has a NEW identity (after a reset): the partner must
  /// compare safety numbers again (D-082, D-128).
  final bool newIdentity;
}

/// The account has a trusted identity this phone does not hold (e.g. the
/// app was reinstalled). It can be approved by the recovery key, or the
/// account can be reset.
final class PhoneSetupNeedsApproval extends PhoneSetupStep {
  const PhoneSetupNeedsApproval({required this.code});

  /// The comparison code a trusted phone would show (D-075).
  final int code;
}

/// A reset was requested; it can finish at [effectiveAt].
final class PhoneSetupResetPending extends PhoneSetupStep {
  const PhoneSetupResetPending(this.effectiveAt);

  final DateTime effectiveAt;
}

/// The reset's wait has passed: [PhoneSetup.finishReset] completes it.
final class PhoneSetupResetReady extends PhoneSetupStep {
  const PhoneSetupResetReady();
}

enum PhoneSetupFailure {
  /// Network or server unavailable; retry.
  unavailable,

  /// The recovery key did not match (or was used already).
  wrongKey,

  /// This account never saved a recovery key.
  noBackupKey,

  /// Too many resets recently (the server's limit).
  tooManyResets,

  /// This platform cannot hold keys (web).
  needsPhone,

  /// The server answered something unexpected.
  unexpected,
}

class PhoneSetupException implements Exception {
  const PhoneSetupException(this.failure);

  final PhoneSetupFailure failure;

  @override
  String toString() => 'PhoneSetupException(${failure.name})';
}

/// Sets this phone up again for an account whose trusted identity it does
/// not hold (D-159). One instance per signed-in account; it holds the core
/// open between steps, so [close] it before private services open the same
/// identity.
abstract interface class PhoneSetup {
  /// Where things stand now, registering this phone if needed.
  Future<PhoneSetupStep> check();

  /// Approves this phone with the account's recovery key (D-076).
  Future<PhoneSetupStep> useRecoveryKey(String key);

  /// Starts the delayed, cancellable reset to a new identity (D-082).
  Future<PhoneSetupStep> requestReset();

  /// Completes a reset whose wait has passed, then makes this phone the
  /// account's new first device.
  Future<PhoneSetupStep> finishReset();

  void close();
}

/// The production [PhoneSetup]: the platform key store, the server's device
/// registry and the existing enrollment, recovery and reset flows. Nothing
/// here can make a phone trusted by itself: the server decides each step.
class LocalPhoneSetup implements PhoneSetup {
  LocalPhoneSetup({
    required this.account,
    required LocalDeviceIdentityService identities,
    required DeviceRegistry registry,
    required DevicePlatform platform,
    DateTime Function()? now,
  }) : _identities = identities,
       _registry = registry,
       _platform = platform,
       _now = now ?? DateTime.now;

  final AccountId account;
  final LocalDeviceIdentityService _identities;
  final DeviceRegistry _registry;
  final DevicePlatform _platform;
  final DateTime Function() _now;

  CryptoCore? _core;
  EnrollmentAwaitingApproval? _awaiting;
  bool _newIdentity = false;

  @override
  Future<PhoneSetupStep> check() => _guard(() async {
    final trust = await _registry.trustState(account);
    final effectiveAt = trust.resetEffectiveAt;
    if (effectiveAt != null) {
      return _now().isBefore(effectiveAt)
          ? PhoneSetupResetPending(effectiveAt)
          : const PhoneSetupResetReady();
    }
    return _enroll();
  });

  @override
  Future<PhoneSetupStep> useRecoveryKey(String key) => _guard(() async {
    final awaiting = _awaiting;
    if (awaiting == null) return check();
    try {
      await DeviceTrustService(_registry).recover(
        core: await _open(),
        account: account,
        enrollment: awaiting,
        recoveryKey: key.trim(),
      );
    } on CryptoException {
      throw const PhoneSetupException(PhoneSetupFailure.wrongKey);
    } on DeviceRegistryException catch (e) {
      throw PhoneSetupException(switch (e.failure) {
        DeviceRegistryFailure.unavailable => PhoneSetupFailure.unavailable,
        DeviceRegistryFailure.recoveryUnavailable =>
          PhoneSetupFailure.noBackupKey,
        _ => PhoneSetupFailure.wrongKey,
      });
    }
    _awaiting = null;
    return _enroll();
  });

  @override
  Future<PhoneSetupStep> requestReset() => _guard(() async {
    final DateTime effectiveAt;
    try {
      effectiveAt = await DeviceTrustService(
        _registry,
      ).requestIdentityReset(account);
    } on DeviceRegistryException catch (e) {
      if (e.failure == DeviceRegistryFailure.rateLimited) {
        throw const PhoneSetupException(PhoneSetupFailure.tooManyResets);
      }
      rethrow;
    }
    _log('requested');
    return _now().isBefore(effectiveAt)
        ? PhoneSetupResetPending(effectiveAt)
        : const PhoneSetupResetReady();
  });

  @override
  Future<PhoneSetupStep> finishReset() => _guard(() async {
    await DeviceTrustService(_registry).completeIdentityReset(account);
    _log('completed');
    // Completion revoked every device of the account, this phone's current
    // identity included: the next enrollment makes a new one.
    return _enroll();
  });

  @override
  void close() {
    _core?.close();
    _core = null;
  }

  /// Registers this phone (if new) and activates or opens an approval
  /// request. An identity the server has retired is replaced by a NEW one
  /// (its slot erased first: crypto-erasure), once.
  Future<PhoneSetupStep> _enroll({bool replaced = false}) async {
    final state = await DeviceRegistrationFlow(
      _registry,
    ).enroll(core: await _open(), account: account, platform: _platform);
    switch (state) {
      case EnrollmentActive():
        _awaiting = null;
        return PhoneSetupDone(newIdentity: _newIdentity);
      case EnrollmentAwaitingApproval(:final code):
        _awaiting = state;
        return PhoneSetupNeedsApproval(code: code);
      case EnrollmentTerminal():
        if (replaced) {
          throw const PhoneSetupException(PhoneSetupFailure.unexpected);
        }
        close();
        await _identities.removeAccount(account);
        _newIdentity = true;
        _log('identity_replaced');
        return _enroll(replaced: true);
    }
  }

  Future<CryptoCore> _open() async {
    final open = _core;
    if (open != null) return open;
    switch (await _identities.open(account)) {
      case LocalIdentityReady(:final core, :final created):
        if (created) _newIdentity = true;
        return _core = core;
      case LocalIdentityUnavailable():
        throw const PhoneSetupException(PhoneSetupFailure.needsPhone);
      case LocalIdentityCorrupted():
        // An unreadable slot cannot hold trust anyway: start a new identity.
        await _identities.removeAccount(account);
        _newIdentity = true;
        return _open();
    }
  }

  Future<PhoneSetupStep> _guard(Future<PhoneSetupStep> Function() run) async {
    try {
      return await run();
    } on PhoneSetupException {
      rethrow;
    } on DeviceRegistryException catch (e) {
      throw PhoneSetupException(
        e.failure == DeviceRegistryFailure.unavailable
            ? PhoneSetupFailure.unavailable
            : PhoneSetupFailure.unexpected,
      );
    }
  }

  static void _log(String outcome) => AppLogger.info(
    'phone_setup_reset',
    fields: {'outcome': SafeLogString(outcome)},
  );
}
