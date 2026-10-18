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
/// (Prompt 08, DEVICE-IDENTITY.md §15–§19). The UI never handles
/// cryptography: it shows codes and states and calls these methods.
///
/// The server is authoritative for every device's status. Before acting as
/// an approver, this device re-reads its own status, so a device revoked
/// while offline cannot create trust after reconnecting (the server would
/// refuse anyway).
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

  /// Rejects a request: the device becomes `rejected` (terminal).
  Future<void> reject({
    required AccountId account,
    required ApprovalCandidate candidate,
  }) async {
    await _registry.reject(account, candidate.request.requestId);
    _log('device_rejected', 'rejected');
  }

  /// Revokes one of the account's devices: lost, stolen, compromised or
  /// unwanted. One way. Revoking this device's own record is allowed (e.g.
  /// before handing the phone on).
  Future<void> revoke({
    required AccountId account,
    required String deviceIdHex,
  }) async {
    await _registry.revoke(account, deviceIdHex);
    _log('device_revoked', 'revoked');
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
