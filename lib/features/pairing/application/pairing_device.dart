import 'package:flutter/foundation.dart';
import 'package:sirf_hum/security/couple/pairing.dart';
import 'package:sirf_hum/security/device/device_key_store.dart';
import 'package:sirf_hum/security/device/device_registration.dart';
import 'package:sirf_hum/security/device/local_device_identity.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// The pairing steps of one trusted phone, signed by its device key
/// ([PairingService]). The owner calls [close] to release the keys.
abstract interface class PairingSession {
  Future<PairingInvitation> createInvitation();
  Future<PairingAcceptance> acceptInvitation(String token);
  Future<CoupleMembership> confirm(String pairingId, String code);
  Future<void> reject(String pairingId);
  Future<void> cancel(String pairingId);
  Future<PairingState> state();
  void close();
}

sealed class DeviceSetupResult {
  const DeviceSetupResult();
}

final class DeviceSetupReady extends DeviceSetupResult {
  const DeviceSetupReady(this.session);

  final PairingSession session;
}

/// Not the account's first phone: a trusted phone must approve it.
final class DeviceSetupAwaitingApproval extends DeviceSetupResult {
  const DeviceSetupAwaitingApproval(this.code);

  final int code;
}

enum DeviceSetupProblem { needsPhone, removed, unreadable }

final class DeviceSetupUnavailable extends DeviceSetupResult {
  const DeviceSetupUnavailable(this.problem);

  final DeviceSetupProblem problem;
}

/// Makes this phone ready to pair for an account. Port, so the screens are
/// tested without native crypto.
abstract interface class PairingDeviceSetup {
  /// Throws (retryably) on network or server failures.
  Future<DeviceSetupResult> setUp(AccountId account);
}

/// Opens the account's device identity from the platform key store
/// (`LocalDeviceIdentityService`, D-066), enrolls it with the server
/// (`DeviceRegistrationFlow`: first phone activates, later phones ask for
/// approval) and signs pairing steps with it. Trust is decided by the
/// server; nothing here can make a phone trusted or a couple paired.
class LocalPairingDeviceSetup implements PairingDeviceSetup {
  LocalPairingDeviceSetup({
    required LocalDeviceIdentityService identities,
    required DeviceRegistry registry,
    required PairingBackend backend,
  }) : _identities = identities,
       _registry = registry,
       _backend = backend;

  LocalPairingDeviceSetup.withKeyStore({
    required DeviceKeyStore keyStore,
    required DeviceRegistry registry,
    required PairingBackend backend,
  }) : this(
         identities: LocalDeviceIdentityService(keyStore: keyStore),
         registry: registry,
         backend: backend,
       );

  final LocalDeviceIdentityService _identities;
  final DeviceRegistry _registry;
  final PairingBackend _backend;

  @override
  Future<DeviceSetupResult> setUp(AccountId account) async {
    final opened = await _identities.open(account);
    final CryptoCore core;
    switch (opened) {
      case LocalIdentityUnavailable():
        return const DeviceSetupUnavailable(DeviceSetupProblem.needsPhone);
      case LocalIdentityCorrupted():
        return const DeviceSetupUnavailable(DeviceSetupProblem.unreadable);
      case LocalIdentityReady(core: final ready):
        core = ready;
    }
    try {
      final enrollment = await DeviceRegistrationFlow(_registry).enroll(
        core: core,
        account: account,
        platform: defaultTargetPlatform == TargetPlatform.iOS
            ? DevicePlatform.ios
            : DevicePlatform.android,
      );
      switch (enrollment) {
        case EnrollmentActive():
          return DeviceSetupReady(
            _ServicePairingSession(
              core,
              PairingService(core: core, backend: _backend),
            ),
          );
        case EnrollmentAwaitingApproval(:final code):
          core.close();
          return DeviceSetupAwaitingApproval(code);
        case EnrollmentTerminal():
          core.close();
          return const DeviceSetupUnavailable(DeviceSetupProblem.removed);
      }
    } on Object {
      core.close();
      rethrow;
    }
  }
}

class _ServicePairingSession implements PairingSession {
  _ServicePairingSession(this._core, this._service);

  final CryptoCore _core;
  final PairingService _service;

  @override
  Future<PairingInvitation> createInvitation() => _service.createInvitation();

  @override
  Future<PairingAcceptance> acceptInvitation(String token) =>
      _service.acceptInvitation(token);

  @override
  Future<CoupleMembership> confirm(String pairingId, String code) =>
      _service.confirm(pairingId, code);

  @override
  Future<void> reject(String pairingId) => _service.reject(pairingId);

  @override
  Future<void> cancel(String pairingId) => _service.cancel(pairingId);

  @override
  Future<PairingState> state() => _service.state();

  @override
  void close() => _core.close();
}
