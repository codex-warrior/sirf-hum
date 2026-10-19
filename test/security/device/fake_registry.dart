// In-memory DeviceRegistry for client tests. It models the server's state
// machine (bootstrap once, approvals, single-use requests, recovery key,
// terminal states) but NOT its signature checks: those are tested against
// the real server code in functions/test (unit + emulator).
import 'dart:typed_data';

import 'package:sirf_hum/security/device/device_registration.dart';
import 'package:sirf_hum/security/device/device_status.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

class FakeRegistry implements DeviceRegistry {
  final calls = <String>[];
  final statuses = <String, DeviceStatus>{};
  final certificates = <String, Uint8List>{};
  final approvedBy = <String, String>{};
  bool trustInitialized = false;
  Uint8List? recoveryPublicKey;
  final requests =
      <String, ({String deviceId, Uint8List challenge, bool proven})>{};
  final issuedChallenges = <String>[];
  final submitted = <String, Uint8List>{};
  DeviceRegistryException? failNext;
  int _next = 0;

  void _maybeFail() {
    final f = failNext;
    failNext = null;
    if (f != null) throw f;
  }

  Uint8List _challenge() =>
      Uint8List.fromList(List.generate(32, (i) => (i + ++_next * 7) % 256));

  @override
  Future<DeviceStatus> status(AccountId account, String deviceIdHex) async {
    calls.add('status');
    return statuses[deviceIdHex] ?? DeviceStatus.unknown;
  }

  @override
  Future<List<DeviceRecord>> listDevices(AccountId account) async => [
    for (final e in statuses.entries)
      DeviceRecord(
        deviceIdHex: e.key,
        status: e.value,
        platform: 'android',
        approvedByDeviceIdHex: approvedBy[e.key],
      ),
  ];

  @override
  Future<void> register(PendingDeviceRegistration r) async {
    calls.add('register');
    _maybeFail();
    statuses[r.deviceIdHex] = DeviceStatus.pending;
    certificates[r.deviceIdHex] = r.certificate;
  }

  @override
  Future<ActivationChallenge> requestChallenge(
    AccountId account,
    String deviceIdHex,
    ChallengePurpose purpose,
  ) async {
    calls.add('challenge:${purpose.name}');
    _maybeFail();
    if (purpose == ChallengePurpose.activation && trustInitialized) {
      throw const DeviceRegistryException(
        DeviceRegistryFailure.approvalRequired,
      );
    }
    final id = 'c${_next + 1}'.padRight(32, '0');
    issuedChallenges.add(id);
    return ActivationChallenge(
      challengeId: id,
      challenge: _challenge(),
      expiresAtUnix: 1900000000,
    );
  }

  @override
  Future<void> activate(
    AccountId account,
    String deviceIdHex,
    String challengeId,
    Uint8List proof,
  ) async {
    calls.add('activate');
    _maybeFail();
    submitted['activate'] = proof;
    statuses[deviceIdHex] = DeviceStatus.active;
    trustInitialized = true;
  }

  @override
  Future<ApprovalRequest> requestApproval(
    AccountId account,
    String deviceIdHex,
  ) async {
    calls.add('requestApproval');
    _maybeFail();
    final id = 'r${_next + 1}'.padRight(32, '0');
    final challenge = _challenge();
    requests[id] = (deviceId: deviceIdHex, challenge: challenge, proven: false);
    return ApprovalRequest(
      requestId: id,
      challenge: challenge,
      expiresAtUnix: 1900000000,
    );
  }

  @override
  Future<void> proveEnrollment(
    AccountId account,
    String requestId,
    Uint8List proof,
  ) async {
    calls.add('prove');
    _maybeFail();
    final r = requests[requestId]!;
    submitted['prove'] = proof;
    requests[requestId] = (
      deviceId: r.deviceId,
      challenge: r.challenge,
      proven: true,
    );
  }

  @override
  Future<List<PendingApproval>> pendingApprovals(AccountId account) async {
    calls.add('pendingApprovals');
    return [
      for (final e in requests.entries)
        if (e.value.proven)
          PendingApproval(
            requestId: e.key,
            challenge: e.value.challenge,
            expiresAtUnix: 1900000000,
            deviceIdHex: e.value.deviceId,
            platform: 'ios',
            certificate: certificates[e.value.deviceId]!,
          ),
    ];
  }

  @override
  Future<void> approve(
    AccountId account,
    String requestId,
    String approverDeviceIdHex,
    Uint8List signature,
  ) async {
    calls.add('approve');
    _maybeFail();
    final r = requests.remove(requestId);
    if (r == null) {
      throw const DeviceRegistryException(DeviceRegistryFailure.requestInvalid);
    }
    submitted['approve'] = signature;
    statuses[r.deviceId] = DeviceStatus.active;
    approvedBy[r.deviceId] = approverDeviceIdHex;
  }

  @override
  Future<void> reject(AccountId account, String requestId) async {
    calls.add('reject');
    final r = requests.remove(requestId)!;
    statuses[r.deviceId] = DeviceStatus.rejected;
  }

  @override
  Future<void> revoke(AccountId account, String deviceIdHex) async {
    calls.add('revoke');
    statuses[deviceIdHex] = DeviceStatus.revoked;
  }

  @override
  Future<void> registerRecoveryKey(
    AccountId account,
    String registrarDeviceIdHex,
    String challengeId,
    Uint8List recoveryPublicKey,
    Uint8List signature,
  ) async {
    calls.add('registerRecoveryKey');
    submitted['registerRecoveryKey'] = signature;
    this.recoveryPublicKey = recoveryPublicKey;
  }

  @override
  Future<void> recover(
    AccountId account,
    String requestId,
    Uint8List signature,
  ) async {
    calls.add('recover');
    if (recoveryPublicKey == null) {
      throw const DeviceRegistryException(
        DeviceRegistryFailure.recoveryUnavailable,
      );
    }
    final r = requests.remove(requestId)!;
    submitted['recover'] = signature;
    statuses[r.deviceId] = DeviceStatus.active;
    recoveryPublicKey = null; // single-use
  }
}
