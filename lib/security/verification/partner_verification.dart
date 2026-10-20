import 'package:flutter/foundation.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/core/logging/log_value.dart';
import 'package:sirf_hum/security/device/device_registration.dart';
import 'package:sirf_hum/security/device/device_status.dart';
import 'package:sirf_hum/security/messaging/message_envelope.dart';
import 'package:sirf_hum/security/verification/safety_number.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// Whether this phone has verified the partner's identity (D-128).
enum VerificationStatus {
  /// The partner's current root key is the one this phone verified: their
  /// devices are trusted through their signed lineage.
  verified,

  /// Never verified on this phone, or the partner now has a different root
  /// key (for example after an identity reset): compare again.
  notVerified,

  /// The server's view of the partner contradicts what this phone verified
  /// (a pinned key on another device, a relabelled device). Fails closed.
  changed,
}

/// Why verification could not proceed. Categories only.
enum VerificationFailure {
  /// This device is not active, or its own lineage does not prove it.
  ownIdentityUnproven,

  /// The partner has no verifiable identity yet (no trusted device, a reset
  /// in progress, or evidence that does not verify).
  partnerUnavailable,

  /// The server answered with an older trust view than one already seen.
  staleServerView,

  /// The scanned code is not this safety number. Nothing was trusted.
  mismatch,

  /// The partner's identity changed between showing and confirming the
  /// number. Nothing was trusted; show the new number.
  changedWhileShown,

  /// The partner's root key was revoked: it can never be verified again.
  revoked,
}

class VerificationException implements Exception {
  const VerificationException(this.failure);

  final VerificationFailure failure;

  @override
  String toString() => 'VerificationException(${failure.name})';
}

/// What the verification screen shows. Holds no IDs; the safety number is
/// shown on screen and never logged.
class PartnerVerification {
  PartnerVerification._({
    required this.status,
    required this.number,
    required this.partnerResetCount,
    required this.partnerDeviceCount,
    required PersonKey partnerRoot,
  }) : _partnerRoot = partnerRoot;

  /// For controller and screen tests with a fake backend only.
  @visibleForTesting
  factory PartnerVerification.forTesting({
    required VerificationStatus status,
    required SafetyNumber number,
    int partnerResetCount = 0,
    int partnerDeviceCount = 0,
  }) => PartnerVerification._(
    status: status,
    number: number,
    partnerResetCount: partnerResetCount,
    partnerDeviceCount: partnerDeviceCount,
    partnerRoot: PersonKey(Uint8List(32)),
  );

  final VerificationStatus status;
  final SafetyNumber number;

  /// Completed identity resets the server reports for the partner (a hint
  /// for the copy only: it can make this phone say "not verified", never
  /// "verified").
  final int partnerResetCount;

  /// Devices the partner's verified lineage proves (0 unless verified).
  final int partnerDeviceCount;

  final PersonKey _partnerRoot;

  @override
  String toString() => 'PartnerVerification(${status.name}, <redacted>)';
}

/// What the verification screen needs (D-128): implemented by
/// [PartnerVerificationService]. `null` in production until a messaging
/// backend is wired (D-116, D-121).
abstract interface class PartnerVerificationBackend {
  Future<PartnerVerification> load();

  Future<PartnerVerification> confirmCompared(PartnerVerification shown);

  Future<PartnerVerification> confirmScanned(
    PartnerVerification shown,
    Uint8List scanned,
  );
}

/// Partner identity verification for one account on one phone (Prompt 17B,
/// D-128). No server answer can make the partner *verified*: only
/// [confirmCompared] or a matching [confirmScanned], after the person
/// compared the number, anchors the partner's root key in the Rust core
/// (sealed, survives restarts). From then on the core accepts the partner's
/// devices only through their signed lineage from that root.
///
/// - Never trust on first contact: an authenticated, paired account and a
///   server that says "trusted" change nothing here.
/// - A different root (reset, substitution) is not anchored, so the status
///   falls back to [VerificationStatus.notVerified] and messaging to the
///   partner fails closed until the person compares again.
/// - Revoked root keys are refused by the core forever.
/// - When the partner's lineage cannot be applied, the devices the server
///   reports revoked are still revoked locally (revocation only removes
///   trust), so an identity reset's revocations reach this phone even
///   before the new identity is verified.
class PartnerVerificationService implements PartnerVerificationBackend {
  PartnerVerificationService({
    required this.core,
    required this.account,
    required this.partner,
    required DeviceRegistry registry,
  }) : _registry = registry;

  final CryptoCore core;
  final AccountId account;
  final AccountId partner;
  final DeviceRegistry _registry;

  @override
  Future<PartnerVerification> load() async {
    core.checkAccount(account);
    final own = core.publicIdentity();
    final ownHex = PendingDeviceRegistration.hexOf(own.deviceId);
    if (await _registry.status(account, ownHex) != DeviceStatus.active) {
      throw const VerificationException(
        VerificationFailure.ownIdentityUnproven,
      );
    }
    final ownRoot = await _ownRoot(own);
    final (request, partnerRoot) = await _partnerLineage();
    final trust = await _registry.trustState(partner);
    final status = await _apply(request, trust.trustEpoch);
    final proven = status == VerificationStatus.verified
        ? CryptoCore.verifyLineage(request).length
        : 0;
    final result = PartnerVerification._(
      status: status,
      number: SafetyNumber.of(
        ownAccount: account.value,
        ownRoot: ownRoot,
        partnerAccount: partner.value,
        partnerRoot: partnerRoot,
      ),
      partnerResetCount: trust.identityEpoch,
      partnerDeviceCount: proven,
      partnerRoot: partnerRoot,
    );
    _log('partner_verification_loaded', status.name);
    return result;
  }

  /// The person compared [shown] with their partner's screen and says it
  /// matches. Anchors the partner root behind [shown] only if the server
  /// still presents that same root.
  @override
  Future<PartnerVerification> confirmCompared(PartnerVerification shown) async {
    final current = await load();
    if (current.number != shown.number) {
      _log('partner_verification_confirmed', 'changed_while_shown');
      throw const VerificationException(VerificationFailure.changedWhileShown);
    }
    if (current.status == VerificationStatus.verified) return current;
    try {
      core.trustVerifiedPersonKey(current._partnerRoot);
    } on CryptoException catch (e) {
      if (e.code == CryptoErrorCode.unauthorizedDevice) {
        _log('partner_verification_confirmed', 'revoked');
        throw const VerificationException(VerificationFailure.revoked);
      }
      rethrow;
    }
    final after = await load();
    _log('partner_verification_confirmed', after.status.name);
    return after;
  }

  /// The person scanned the partner's QR code. Trusts nothing unless the
  /// payload is exactly [shown]'s safety number.
  @override
  Future<PartnerVerification> confirmScanned(
    PartnerVerification shown,
    Uint8List scanned,
  ) async {
    if (!shown.number.matchesScanned(scanned)) {
      _log('partner_verification_scanned', 'mismatch');
      throw const VerificationException(VerificationFailure.mismatch);
    }
    return confirmCompared(shown);
  }

  /// This account's root key, from a lineage that proves THIS device. A
  /// chain containing this device can only descend from this person's real
  /// root (every link is a signature the server cannot make), so the root
  /// is anchored without asking the person to verify themselves.
  Future<PersonKey> _ownRoot(PublicIdentity own) async {
    final request = await _registry.lineage(account);
    if (request == null) {
      throw const VerificationException(
        VerificationFailure.ownIdentityUnproven,
      );
    }
    final List<DeviceId> proven;
    try {
      proven = CryptoCore.verifyLineage(request);
    } on CryptoException catch (e) {
      if (e.code != CryptoErrorCode.trustChainInvalid) rethrow;
      throw const VerificationException(
        VerificationFailure.ownIdentityUnproven,
      );
    }
    if (!proven.contains(own.deviceId)) {
      throw const VerificationException(
        VerificationFailure.ownIdentityUnproven,
      );
    }
    final root = personKeyOfCertificate(request.rootCertificate);
    core.trustVerifiedPersonKey(root);
    return root;
  }

  Future<(LineageRequest, PersonKey)> _partnerLineage() async {
    final request = await _registry.lineage(partner);
    if (request == null) {
      await _applyServerRevocations();
      throw const VerificationException(VerificationFailure.partnerUnavailable);
    }
    try {
      CryptoCore.verifyLineage(request);
    } on CryptoException catch (e) {
      if (e.code != CryptoErrorCode.trustChainInvalid) rethrow;
      throw const VerificationException(VerificationFailure.partnerUnavailable);
    }
    return (request, personKeyOfCertificate(request.rootCertificate));
  }

  Future<VerificationStatus> _apply(LineageRequest request, int epoch) async {
    try {
      core.trustLineage(request, epoch);
      // An anchored but revoked root (e.g. an old identity re-presented
      // after a reset) applies without trusting anything: not verified.
      final root = deviceIdOfCertificate(request.rootCertificate);
      if (core.deviceAccount(root) != partner.value) {
        await _applyServerRevocations();
        return VerificationStatus.notVerified;
      }
      return VerificationStatus.verified;
    } on CryptoException catch (e) {
      switch (e.code) {
        case CryptoErrorCode.unauthorizedDevice:
          await _applyServerRevocations();
          return VerificationStatus.notVerified;
        case CryptoErrorCode.trustChainInvalid:
          await _applyServerRevocations();
          return VerificationStatus.changed;
        case CryptoErrorCode.trustStateStale:
          throw const VerificationException(
            VerificationFailure.staleServerView,
          );
        default:
          rethrow;
      }
    }
  }

  /// Revokes, on this phone, every partner device the server reports
  /// revoked. Server-asserted revocations only ever remove trust (D-084).
  Future<void> _applyServerRevocations() async {
    for (final d in await _registry.listDevices(partner)) {
      if (d.status == DeviceStatus.revoked) {
        core.revokeDevice(
          DeviceId(EncryptedMessageEnvelope.bytesOfHex(d.deviceIdHex)),
        );
      }
    }
  }

  static void _log(String event, String outcome) =>
      AppLogger.info(event, fields: {'outcome': SafeLogString(outcome)});
}
