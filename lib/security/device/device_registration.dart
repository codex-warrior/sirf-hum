import 'dart:typed_data';

import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/core/logging/log_value.dart';
import 'package:sirf_hum/security/device/device_status.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// Platforms that can hold a device identity (Web cannot, D-046).
enum DevicePlatform { android, ios }

/// What a client sends to `registerDevice` (D-069). The server verifies the
/// certificate and writes the `pending` record itself; every server-visible
/// field is justified in DEVICE-IDENTITY.md §4.
class PendingDeviceRegistration {
  PendingDeviceRegistration({
    required this.accountId,
    required DeviceId deviceId,
    required this.platform,
    required Uint8List certificate,
  }) : deviceIdHex = hexOf(deviceId),
       certificate = Uint8List.fromList(certificate) {
    if (certificate.isEmpty || certificate.length > maxCertificateBytes) {
      throw const DeviceRegistryException(DeviceRegistryFailure.invalidRecord);
    }
  }

  static const int schemaVersion = 1;
  static const int maxCertificateBytes = 512;

  /// MLS ciphersuite 0x0001 and implementation (D-061 capabilities).
  static const int ciphersuite = 1;
  static const String implementation = 'openmls/0.9.1';

  final AccountId accountId;

  /// Lower-case hex of the 16-byte device ID; the record's document ID.
  final String deviceIdHex;
  final DevicePlatform platform;

  /// The PIK-signed device certificate (D-064). Public material.
  final Uint8List certificate;

  static String hexOf(DeviceId id) =>
      id.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  @override
  String toString() => 'PendingDeviceRegistration(<redacted>)';
}

Uint8List _challengeBytes(Uint8List challenge) {
  if (challenge.length != 32) {
    throw const DeviceRegistryException(DeviceRegistryFailure.invalidRecord);
  }
  return Uint8List.fromList(challenge);
}

/// A server-issued, single-use challenge (5-minute lifetime).
class ActivationChallenge {
  ActivationChallenge({
    required this.challengeId,
    required Uint8List challenge,
    this.expiresAtUnix = 0,
  }) : challenge = _challengeBytes(challenge);

  final String challengeId;
  final Uint8List challenge;

  /// Signed into recovery-key registrations (whole seconds).
  final int expiresAtUnix;

  @override
  String toString() => 'ActivationChallenge(<redacted>)';
}

/// An approval request opened by a new device (D-075; 10-minute lifetime).
class ApprovalRequest {
  ApprovalRequest({
    required this.requestId,
    required Uint8List challenge,
    required this.expiresAtUnix,
  }) : challenge = _challengeBytes(challenge);

  final String requestId;
  final Uint8List challenge;
  final int expiresAtUnix;

  @override
  String toString() => 'ApprovalRequest(<redacted>)';
}

/// A proven request shown to a trusted device for approval.
class PendingApproval extends ApprovalRequest {
  PendingApproval({
    required super.requestId,
    required super.challenge,
    required super.expiresAtUnix,
    required this.deviceIdHex,
    required this.platform,
    required Uint8List certificate,
  }) : certificate = Uint8List.fromList(certificate);

  final String deviceIdHex;
  final String platform;
  final Uint8List certificate;

  @override
  String toString() => 'PendingApproval(<redacted>)';
}

/// A device record as its owner can read it (public metadata).
class DeviceRecord {
  const DeviceRecord({
    required this.deviceIdHex,
    required this.status,
    required this.platform,
    this.activationMethod,
    this.approvedByDeviceIdHex,
    this.certificate,
    this.activatedEpoch,
  });

  final String deviceIdHex;
  final DeviceStatus status;
  final String platform;

  /// `first_device`, `approval` or `recovery` once active.
  final String? activationMethod;

  /// The approving device, for `approval` (D-075 lineage).
  final String? approvedByDeviceIdHex;

  /// The device certificate (public); needed to sign its revocation.
  final Uint8List? certificate;

  /// The account trust epoch at which it became active (D-083 ordering).
  final int? activatedEpoch;

  @override
  String toString() => 'DeviceRecord(${status.name}, <redacted>)';
}

/// Stable failure categories, matching functions/src/device/common.ts.
enum DeviceRegistryFailure {
  invalidRecord,
  unauthenticated,
  deviceNotFound,
  deviceNotPending,
  deviceExpired,
  challengeInvalid,
  challengeExpired,
  proofInvalid,
  certificateInvalid,
  duplicateDevice,
  tooManyPending,

  /// The account already has a trusted device: use the approval flow.
  approvalRequired,
  requestInvalid,
  requestExpired,

  /// The approving device is not (or no longer) trusted.
  approverNotTrusted,
  approvalInvalid,

  /// No recovery key is registered for this account.
  recoveryUnavailable,
  recoveryInvalid,

  /// The revocation statement did not verify (D-081).
  revocationInvalid,

  /// There is no identity reset to request, cancel or complete (D-082).
  resetUnavailable,

  /// The reset's public delay has not passed yet.
  resetNotReady,
  rateLimited,

  /// The server returned a status this client does not understand.
  unexpectedState,

  /// This device is not trusted, so it may not perform the operation.
  deviceNotTrusted,

  /// Network, App Check or backend unavailable; safe to retry later.
  unavailable;

  /// Maps the server's category string; anything unknown is [unavailable]
  /// (retryable), never success.
  static DeviceRegistryFailure fromServer(String? category) =>
      switch (category) {
        'invalid_argument' => invalidRecord,
        'unauthenticated' => unauthenticated,
        'device_not_found' => deviceNotFound,
        'device_not_pending' => deviceNotPending,
        'device_expired' => deviceExpired,
        'challenge_invalid' => challengeInvalid,
        'challenge_expired' => challengeExpired,
        'proof_invalid' => proofInvalid,
        'certificate_invalid' => certificateInvalid,
        'duplicate_device' => duplicateDevice,
        'too_many_pending' => tooManyPending,
        'approval_required' => approvalRequired,
        'request_invalid' => requestInvalid,
        'request_expired' => requestExpired,
        'approver_not_trusted' => approverNotTrusted,
        'approval_invalid' => approvalInvalid,
        'recovery_unavailable' => recoveryUnavailable,
        'recovery_invalid' => recoveryInvalid,
        'revocation_invalid' => revocationInvalid,
        'reset_unavailable' => resetUnavailable,
        'reset_not_ready' => resetNotReady,
        'rate_limited' => rateLimited,
        // Prompt 11 (push tokens): the device is not active on the server.
        'device_not_active' => deviceNotTrusted,
        _ => unavailable,
      };
}

class DeviceRegistryException implements Exception {
  const DeviceRegistryException(this.failure);

  final DeviceRegistryFailure failure;

  @override
  String toString() => 'DeviceRegistryException(${failure.name})';
}

/// Purposes of server challenges (functions/src/device/registration.ts).
enum ChallengePurpose {
  activation,
  recoveryRegistration,
  revocation,
  resetCancel,
}

/// The account's server-side trust state (D-082, D-083), owner-readable.
class AccountTrustState {
  const AccountTrustState({
    required this.trustEpoch,
    this.identityEpoch = 0,
    this.bootstrapOpen = false,
    this.resetEffectiveAt,
  });

  /// No trusted device ever: nothing to protect yet.
  static const none = AccountTrustState(trustEpoch: 0);

  /// Monotonic; bumped by every trust change. Devices refuse older views.
  final int trustEpoch;

  /// How many identity resets completed.
  final int identityEpoch;

  /// After a completed reset: the next device bootstraps a NEW identity.
  final bool bootstrapOpen;

  /// When a pending identity reset may complete; null when none is pending.
  final DateTime? resetEffectiveAt;

  bool get resetPending => resetEffectiveAt != null;

  @override
  String toString() =>
      'AccountTrustState(epoch $trustEpoch, reset ${resetPending ? 'pending' : 'none'})';
}

/// Port for the server-side device registry, implemented by
/// `lib/infrastructure/firebase/firestore_device_registry.dart`. Every
/// trust-changing call is a server-side Function; the server never receives
/// private keys and cannot sign approvals.
abstract interface class DeviceRegistry {
  /// The record's status, [DeviceStatus.unknown] when there is none.
  Future<DeviceStatus> status(AccountId account, String deviceIdHex);

  /// All of the account's device records (owner read via the rules).
  Future<List<DeviceRecord>> listDevices(AccountId account);

  /// Registers this device as `pending` (`registerDevice`).
  Future<void> register(PendingDeviceRegistration registration);

  Future<ActivationChallenge> requestChallenge(
    AccountId account,
    String deviceIdHex,
    ChallengePurpose purpose,
  );

  /// First device only: proof of possession activates it (`activateDevice`).
  Future<void> activate(
    AccountId account,
    String deviceIdHex,
    String challengeId,
    Uint8List proof,
  );

  /// Opens an approval request for this pending device.
  Future<ApprovalRequest> requestApproval(
    AccountId account,
    String deviceIdHex,
  );

  /// Proves possession for an open request (purpose `enrollment`).
  Future<void> proveEnrollment(
    AccountId account,
    String requestId,
    Uint8List proof,
  );

  /// Proven requests awaiting approval by a trusted device.
  Future<List<PendingApproval>> pendingApprovals(AccountId account);

  Future<void> approve(
    AccountId account,
    String requestId,
    String approverDeviceIdHex,
    Uint8List signature,
  );

  Future<void> reject(AccountId account, String requestId);

  /// Signed revocation by a trusted device of the account, possibly of
  /// itself (`revokeDevice`, D-081). One way.
  Future<void> revoke(
    AccountId account, {
    required String revokerDeviceIdHex,
    required String deviceIdHex,
    required RevocationReason reason,
    required String challengeId,
    required Uint8List signature,
  });

  /// The account's trust epoch and identity-reset state.
  Future<AccountTrustState> trustState(AccountId account);

  /// Public evidence for on-device lineage verification (D-084), or null
  /// while the account has no current first device.
  Future<LineageRequest?> lineage(AccountId account);

  /// Starts (or returns the pending) identity reset; when it may complete.
  Future<DateTime> requestIdentityReset(AccountId account);

  /// A trusted device's signed cancellation of a pending reset.
  Future<void> cancelIdentityReset(
    AccountId account,
    String deviceIdHex,
    String challengeId,
    Uint8List signature,
  );

  /// Completes a reset whose delay has passed: every device is revoked and
  /// the account accepts one NEW first device.
  Future<void> completeIdentityReset(AccountId account);

  Future<void> registerRecoveryKey(
    AccountId account,
    String registrarDeviceIdHex,
    String challengeId,
    Uint8List recoveryPublicKey,
    Uint8List signature,
  );

  Future<void> recover(
    AccountId account,
    String requestId,
    Uint8List signature,
  );
}

/// Where a device stands after [DeviceRegistrationFlow.enroll].
sealed class EnrollmentState {
  const EnrollmentState();
}

/// Trusted. Nothing more to do.
final class EnrollmentActive extends EnrollmentState {
  const EnrollmentActive();
}

/// Waiting for a trusted device (or the recovery key). Show [code] on this
/// device; the user approves the request showing the same code elsewhere.
final class EnrollmentAwaitingApproval extends EnrollmentState {
  const EnrollmentAwaitingApproval({required this.request, required this.code});

  final ApprovalRequest request;

  /// Six-digit comparison code (not a secret).
  final int code;

  @override
  String toString() => 'EnrollmentAwaitingApproval(<redacted>)';
}

/// Terminal on the server (revoked, rejected, expired): this identity will
/// never be trusted again. The app needs a NEW identity (remove the account
/// from this device, then enroll again).
final class EnrollmentTerminal extends EnrollmentState {
  const EnrollmentTerminal(this.status);

  final DeviceStatus status;
}

/// Drives one device into trust (DEVICE-IDENTITY.md §3, §16).
///
/// Idempotent: safe to rerun after any failure. It never reuses a challenge
/// or request (each attempt asks for a new one) and never tries to revive a
/// terminal device.
class DeviceRegistrationFlow {
  const DeviceRegistrationFlow(this._registry);

  final DeviceRegistry _registry;

  /// Registers this device and either activates it (first device of the
  /// account) or opens a proven approval request.
  Future<EnrollmentState> enroll({
    required CryptoCore core,
    required AccountId account,
    required DevicePlatform platform,
  }) async {
    // The core must hold this account's identity before anything is sent.
    core.checkAccount(account);
    final identity = core.publicIdentity();
    final deviceIdHex = PendingDeviceRegistration.hexOf(identity.deviceId);

    var status = await _registry.status(account, deviceIdHex);
    if (status == DeviceStatus.unknown) {
      await _registry.register(
        PendingDeviceRegistration(
          accountId: account,
          deviceId: identity.deviceId,
          platform: platform,
          certificate: identity.certificate,
        ),
      );
      status = DeviceStatus.pending;
    }
    final EnrollmentState state;
    if (status == DeviceStatus.active) {
      state = const EnrollmentActive();
    } else if (status.isTerminal) {
      state = EnrollmentTerminal(status);
    } else {
      state = await _bootstrapOrRequest(core, account, deviceIdHex, identity);
    }
    _log(state);
    return state;
  }

  Future<EnrollmentState> _bootstrapOrRequest(
    CryptoCore core,
    AccountId account,
    String deviceIdHex,
    PublicIdentity identity,
  ) async {
    try {
      final challenge = await _registry.requestChallenge(
        account,
        deviceIdHex,
        ChallengePurpose.activation,
      );
      await _registry.activate(
        account,
        deviceIdHex,
        challenge.challengeId,
        core.deviceProof(DeviceProofPurpose.activation, challenge.challenge),
      );
      return const EnrollmentActive();
    } on DeviceRegistryException catch (e) {
      if (e.failure != DeviceRegistryFailure.approvalRequired) rethrow;
    }
    // Not the first device: trust must come from a trusted device or the
    // recovery key. Prove possession now so approvers only see proven
    // requests.
    final request = await _registry.requestApproval(account, deviceIdHex);
    await _registry.proveEnrollment(
      account,
      request.requestId,
      core.deviceProof(DeviceProofPurpose.enrollment, request.challenge),
    );
    return EnrollmentAwaitingApproval(
      request: request,
      code: CryptoCore.approvalCode(
        newCertificate: identity.certificate,
        challenge: request.challenge,
      ),
    );
  }

  void _log(EnrollmentState state) => AppLogger.info(
    'device_enrollment_state',
    fields: {
      'state': SafeLogString(switch (state) {
        EnrollmentActive() => 'active',
        EnrollmentAwaitingApproval() => 'awaiting_approval',
        EnrollmentTerminal(:final status) => status.name,
      }),
    },
  );
}
