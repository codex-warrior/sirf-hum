import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/core/logging/log_value.dart';
import 'package:sirf_hum/security/device/device_registration.dart';
import 'package:sirf_hum/security/device/device_status.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// A pending device as an approver sees it, with the comparison code the
/// user must match against the code shown on the new device.
class ApprovalCandidate {
  const ApprovalCandidate({required this.request, required this.code});

  final PendingApproval request;
  final int code;

  @override
  String toString() => 'ApprovalCandidate(<redacted>)';
}

/// Multi-device trust operations for a future device-management UI
/// (Prompts 08–09, DEVICE-IDENTITY.md §15–§19, MULTI-DEVICE-TRUST.md). The UI never handles
/// cryptography: it shows codes and states and calls these methods.
///
/// The server is authoritative for every device's status. Before acting as
/// an approver, this device re-reads its own status, so a device revoked
/// while offline cannot create trust after reconnecting (the server would
/// refuse anyway). It also records the account's trust epoch in the core, so
/// a stale or rolled-back server view is refused (D-083).
class DeviceTrustService {
  const DeviceTrustService(this._registry);

  final DeviceRegistry _registry;

  /// This device's current server status. A terminal status means the local
  /// identity must stop presenting itself as trusted (§17); the caller then
  /// offers "remove this account from this device".
  Future<DeviceStatus> refreshStatus({
    required CryptoCore core,
    required AccountId account,
  }) async {
    core.checkAccount(account);
    final status = await _registry.status(account, _ownId(core));
    _log('device_status_refreshed', status.name);
    return status;
  }

  Future<List<DeviceRecord>> devices(AccountId account) =>
      _registry.listDevices(account);

  /// Reads the account's trust state and records its epoch in the core.
  /// Throws [CryptoException] with [CryptoErrorCode.trustStateStale] when
  /// the server shows an epoch older than one this device already saw: the
  /// caller must not act on that view (D-083).
  Future<AccountTrustState> refreshTrustState({
    required CryptoCore core,
    required AccountId account,
  }) async {
    core.checkAccount(account);
    final state = await _registry.trustState(account);
    try {
      core.observeTrustEpoch(state.trustEpoch);
    } on CryptoException catch (e) {
      if (e.code == CryptoErrorCode.trustStateStale) {
        _log('trust_state_refreshed', 'stale');
      }
      rethrow;
    }
    return state;
  }

  /// Verifies the account's device lineage on this device (D-084) and
  /// returns the device IDs it proves trusted. Fails closed with
  /// [CryptoErrorCode.trustChainInvalid] if the server lists an active
  /// device the signed chain does not prove. The root's person key still
  /// needs the partner's out-of-band verification (D-064): this proves the
  /// chain from the root, not who the root is.
  Future<Set<String>> verifyLineage(AccountId account) async {
    final request = await _registry.lineage(account);
    if (request == null) return const {};
    final proven = {
      for (final id in CryptoCore.verifyLineage(request))
        PendingDeviceRegistration.hexOf(id),
    };
    final active = {
      for (final r in await _registry.listDevices(account))
        if (r.status == DeviceStatus.active) r.deviceIdHex,
    };
    if (!proven.containsAll(active)) {
      _log('device_lineage_verified', 'mismatch');
      throw const CryptoException(CryptoErrorCode.trustChainInvalid);
    }
    _log('device_lineage_verified', 'verified');
    return proven.intersection(active);
  }

  /// Proven requests from other devices, each with its comparison code.
  Future<List<ApprovalCandidate>> pendingApprovals({
    required CryptoCore core,
    required AccountId account,
  }) async {
    await _requireTrusted(core, account);
    final own = _ownId(core);
    final requests = await _registry.pendingApprovals(account);
    return [
      for (final r in requests)
        if (r.deviceIdHex != own)
          ApprovalCandidate(
            request: r,
            code: CryptoCore.approvalCode(
              newCertificate: r.certificate,
              challenge: r.challenge,
            ),
          ),
    ];
  }

  /// Approves [candidate] after the user confirmed its code matches the new
  /// device's screen.
  Future<void> approve({
    required CryptoCore core,
    required AccountId account,
    required ApprovalCandidate candidate,
  }) async {
    await _requireTrusted(core, account);
    final r = candidate.request;
    final signature = core.approveDevice(
      newCertificate: r.certificate,
      challenge: r.challenge,
      expiresAtUnix: r.expiresAtUnix,
    );
    await _registry.approve(account, r.requestId, _ownId(core), signature);
    _log('device_approved', 'approved');
  }

  /// Rejects a request: the device becomes `rejected` (terminal). Signed by
  /// this active device's key over a challenge bound to the request (D-129):
  /// a password alone can no longer block the owner's new devices.
  Future<void> reject({
    required CryptoCore core,
    required AccountId account,
    required ApprovalCandidate candidate,
  }) async {
    await _requireTrusted(core, account);
    final own = _ownId(core);
    final requestId = candidate.request.requestId;
    final c = await _registry.requestChallenge(
      account,
      own,
      ChallengePurpose.approvalRejection,
      requestId: requestId,
    );
    await _registry.reject(
      account,
      requestId,
      rejecterDeviceIdHex: own,
      challengeId: c.challengeId,
      proof: core.deviceProof(
        DeviceProofPurpose.approvalRejection,
        c.challenge,
      ),
    );
    _log('device_rejected', 'rejected');
  }

  /// Revokes one of the account's devices: lost, stolen, compromised or
  /// unwanted. One way. This device signs the revocation with its person
  /// key (D-081); revoking its own record is allowed (e.g. before handing
  /// the phone on).
  Future<void> revoke({
    required CryptoCore core,
    required AccountId account,
    required String deviceIdHex,
    required RevocationReason reason,
  }) async {
    await _requireTrusted(core, account);
    final own = _ownId(core);
    final certificate = (await _registry.listDevices(
      account,
    )).where((r) => r.deviceIdHex == deviceIdHex).firstOrNull?.certificate;
    if (certificate == null) {
      throw const DeviceRegistryException(DeviceRegistryFailure.deviceNotFound);
    }
    final challenge = await _registry.requestChallenge(
      account,
      own,
      ChallengePurpose.revocation,
    );
    final signature = core.signRevocation(
      revokedCertificate: certificate,
      reason: reason,
      challenge: challenge.challenge,
      expiresAtUnix: challenge.expiresAtUnix,
    );
    await _registry.revoke(
      account,
      revokerDeviceIdHex: own,
      deviceIdHex: deviceIdHex,
      reason: reason,
      challengeId: challenge.challengeId,
      signature: signature,
    );
    _log('device_revoked', 'revoked');
  }

  /// Starts an identity reset for an account whose devices are ALL lost and
  /// that has no recovery key (D-082). It completes only after a public
  /// delay, and any trusted device can cancel it. It never restores the old
  /// identity: the next device creates a NEW person key that partners must
  /// verify again. Returns when the reset may complete.
  Future<DateTime> requestIdentityReset(AccountId account) async {
    final effectiveAt = await _registry.requestIdentityReset(account);
    _log('identity_reset_requested', 'pending');
    return effectiveAt;
  }

  /// Cancels a pending reset this device's user did not ask for.
  Future<void> cancelIdentityReset({
    required CryptoCore core,
    required AccountId account,
  }) async {
    await _requireTrusted(core, account);
    final own = _ownId(core);
    final challenge = await _registry.requestChallenge(
      account,
      own,
      ChallengePurpose.resetCancel,
    );
    final signature = core.signResetCancellation(
      challenge: challenge.challenge,
      expiresAtUnix: challenge.expiresAtUnix,
    );
    await _registry.cancelIdentityReset(
      account,
      own,
      challenge.challengeId,
      signature,
    );
    _log('identity_reset_cancelled', 'cancelled');
  }

  /// Completes a reset whose delay has passed. Afterwards the user creates a
  /// new identity and enrolls it as the account's first device.
  Future<void> completeIdentityReset(AccountId account) async {
    await _registry.completeIdentityReset(account);
    _log('identity_reset_completed', 'completed');
  }

  /// Creates and registers a recovery key, replacing any previous one. The
  /// returned text must be shown to the user ONCE and never stored, sent or
  /// logged (D-076).
  Future<String> createRecoveryKey({
    required CryptoCore core,
    required AccountId account,
  }) async {
    await _requireTrusted(core, account);
    final own = _ownId(core);
    final challenge = await _registry.requestChallenge(
      account,
      own,
      ChallengePurpose.recoveryRegistration,
    );
    final bundle = core.createRecoveryKey(
      challenge: challenge.challenge,
      expiresAtUnix: challenge.expiresAtUnix,
    );
    await _registry.registerRecoveryKey(
      account,
      own,
      challenge.challengeId,
      bundle.publicKey,
      bundle.registrationSignature,
    );
    _log('recovery_key_created', 'registered');
    return bundle.secret;
  }

  /// Uses the user-typed recovery key to approve THIS device's proven
  /// request (from [DeviceRegistrationFlow.enroll]). The key is single-use:
  /// create a new one afterwards.
  Future<void> recover({
    required CryptoCore core,
    required AccountId account,
    required EnrollmentAwaitingApproval enrollment,
    required String recoveryKey,
  }) async {
    core.checkAccount(account);
    final r = enrollment.request;
    final approval = core.recoveryApproval(
      recoveryKey: recoveryKey,
      challenge: r.challenge,
      expiresAtUnix: r.expiresAtUnix,
    );
    await _registry.recover(account, r.requestId, approval.signature);
    _log('device_recovered', 'recovered');
  }

  Future<void> _requireTrusted(CryptoCore core, AccountId account) async {
    await refreshTrustState(core: core, account: account);
    if (await refreshStatus(core: core, account: account) !=
        DeviceStatus.active) {
      throw const DeviceRegistryException(
        DeviceRegistryFailure.deviceNotTrusted,
      );
    }
  }

  static String _ownId(CryptoCore core) =>
      PendingDeviceRegistration.hexOf(core.publicIdentity().deviceId);

  static void _log(String event, String outcome) =>
      AppLogger.info(event, fields: {'outcome': SafeLogString(outcome)});
}
