// In-memory DeviceRegistry for client tests. It models the server's state
// machine (bootstrap once, approvals, single-use requests, recovery key,
// terminal states, trust epoch, identity reset) but NOT its signature
// checks: those are tested against the real server code in functions/test
// (unit + emulator). It keeps the signed evidence it receives, so lineage
// verification in client tests runs the real Rust verifier on real
// signatures.
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

  /// Account trust epoch; tests may lower it to simulate a rolled-back view.
  int trustEpoch = 0;

  /// Completed identity resets (D-082), as `accountTrust.identityEpoch`.
  int identityEpoch = 0;
  DateTime? resetEffectiveAt;
  String? firstDeviceId;

  /// Activation links and signed revocations in commit order (D-084).
  final links = <String, LineageLink>{};
  final revocations = <SignedRevocation>[];
  final _challenges = <String, ActivationChallenge>{};
  ({Uint8List registrar, Uint8List challenge, Uint8List signature})?
  _registration;

  void _maybeFail() {
    final f = failNext;
    failNext = null;
    if (f != null) throw f;
  }

  Uint8List _challenge() =>
      Uint8List.fromList(List.generate(32, (i) => (i + ++_next * 7) % 256));

  static const _expires = 1900000000;

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
        certificate: certificates[e.key],
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
    if (purpose != ChallengePurpose.activation &&
        statuses[deviceIdHex] != DeviceStatus.active) {
      throw const DeviceRegistryException(
        DeviceRegistryFailure.approverNotTrusted,
      );
    }
    final id = 'c${_next + 1}'.padRight(32, '0');
    issuedChallenges.add(id);
    return _challenges[id] = ActivationChallenge(
      challengeId: id,
      challenge: _challenge(),
      expiresAtUnix: _expires,
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
    firstDeviceId = deviceIdHex;
    trustEpoch++;
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
      expiresAtUnix: _expires,
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
            expiresAtUnix: _expires,
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
    links[r.deviceId] = ApprovalLink(
      approverCertificate: certificates[approverDeviceIdHex]!,
      newCertificate: certificates[r.deviceId]!,
      challenge: r.challenge,
      expiresAtUnix: _expires,
      signature: signature,
    );
    trustEpoch++;
  }

  @override
  Future<void> reject(AccountId account, String requestId) async {
    calls.add('reject');
    final r = requests.remove(requestId)!;
    statuses[r.deviceId] = DeviceStatus.rejected;
  }

  @override
  Future<void> revoke(
    AccountId account, {
    required String revokerDeviceIdHex,
    required String deviceIdHex,
    required RevocationReason reason,
    required String challengeId,
    required Uint8List signature,
  }) async {
    calls.add('revoke');
    _maybeFail();
    final challenge = _challenges.remove(challengeId);
    if (challenge == null) {
      throw const DeviceRegistryException(
        DeviceRegistryFailure.challengeInvalid,
      );
    }
    submitted['revoke'] = signature;
    statuses[deviceIdHex] = DeviceStatus.revoked;
    revocations.add(
      SignedRevocation(
        revokerCertificate: certificates[revokerDeviceIdHex]!,
        revokedCertificate: certificates[deviceIdHex]!,
        reason: reason.wireValue,
        challenge: challenge.challenge,
        expiresAtUnix: challenge.expiresAtUnix,
        signature: signature,
      ),
    );
    trustEpoch++;
  }

  @override
  Future<AccountTrustState> trustState(AccountId account) async {
    calls.add('trustState');
    _maybeFail();
    return AccountTrustState(
      trustEpoch: trustEpoch,
      identityEpoch: identityEpoch,
      resetEffectiveAt: resetEffectiveAt,
    );
  }

  @override
  Future<LineageRequest?> lineage(AccountId account) async {
    calls.add('lineage');
    final root = firstDeviceId;
    if (root == null) return null;
    return LineageRequest(
      accountId: account.value,
      rootCertificate: certificates[root]!,
      links: links.values.toList(),
      revocations: revocations,
    );
  }

  @override
  Future<DateTime> requestIdentityReset(AccountId account) async {
    calls.add('requestIdentityReset');
    _maybeFail();
    if (!trustInitialized) {
      throw const DeviceRegistryException(
        DeviceRegistryFailure.resetUnavailable,
      );
    }
    if (resetEffectiveAt == null) trustEpoch++;
    return resetEffectiveAt ??= DateTime.utc(2030);
  }

  @override
  Future<void> cancelIdentityReset(
    AccountId account,
    String deviceIdHex,
    String challengeId,
    Uint8List signature,
  ) async {
    calls.add('cancelIdentityReset');
    _maybeFail();
    if (resetEffectiveAt == null || _challenges.remove(challengeId) == null) {
      throw const DeviceRegistryException(
        DeviceRegistryFailure.resetUnavailable,
      );
    }
    submitted['cancelIdentityReset'] = signature;
    resetEffectiveAt = null;
    trustEpoch++;
  }

  @override
  Future<void> completeIdentityReset(AccountId account) async {
    calls.add('completeIdentityReset');
    _maybeFail();
    if (resetEffectiveAt == null) {
      throw const DeviceRegistryException(
        DeviceRegistryFailure.resetUnavailable,
      );
    }
    for (final id in statuses.keys.toList()) {
      if (!statuses[id]!.isTerminal) statuses[id] = DeviceStatus.revoked;
    }
    resetEffectiveAt = null;
    trustInitialized = false;
    firstDeviceId = null;
    links.clear();
    revocations.clear();
    recoveryPublicKey = null;
    identityEpoch++;
    trustEpoch++;
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
    _registration = (
      registrar: certificates[registrarDeviceIdHex]!,
      challenge: _challenges[challengeId]!.challenge,
      signature: signature,
    );
    trustEpoch++;
  }

  @override
  Future<void> recover(
    AccountId account,
    String requestId,
    Uint8List signature,
  ) async {
    calls.add('recover');
    final key = recoveryPublicKey;
    final registration = _registration;
    if (key == null || registration == null) {
      throw const DeviceRegistryException(
        DeviceRegistryFailure.recoveryUnavailable,
      );
    }
    final r = requests.remove(requestId)!;
    submitted['recover'] = signature;
    statuses[r.deviceId] = DeviceStatus.active;
    links[r.deviceId] = RecoveryLink(
      registrarCertificate: registration.registrar,
      recoveryPublicKey: key,
      registrationChallenge: registration.challenge,
      registrationExpiresAtUnix: _expires,
      registrationSignature: registration.signature,
      newCertificate: certificates[r.deviceId]!,
      challenge: r.challenge,
      expiresAtUnix: _expires,
      signature: signature,
    );
    recoveryPublicKey = null; // single-use
    _registration = null;
    trustEpoch++;
  }
}
