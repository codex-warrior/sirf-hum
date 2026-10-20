// In-memory server for messaging tests. It enforces what firebase/
// firestore.rules and the commit Function enforce (membership, active
// sender device, one commit per epoch with the epoch move, single-use
// device-bound commit authorization (D-127), messages only at the current
// epoch, create-only documents) so the client's arbitration logic meets the
// same answers. The rules are tested in firebase/tests/messaging.test.js,
// the Function in functions/test/emulator/commit.test.mjs.
import 'dart:math';
import 'dart:typed_data';

import 'package:sirf_hum/security/device/device_status.dart';
import 'package:sirf_hum/security/messaging/commit_authorization.dart';
import 'package:sirf_hum/security/messaging/conversation_transport.dart';
import 'package:sirf_hum/security/messaging/message_envelope.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

class FakeTransport implements ConversationTransport {
  FakeTransport({
    required this.members,
    required this.statusOf,
    this.verifyCommitProof,
  });

  /// Verifies a device proof (purpose `commit`) over [signed] for
  /// [deviceHex]. Tests that model the real check pass one (Ed25519 is
  /// deterministic, so the device's own core can recompute it); when null,
  /// the challenge, device and epoch bindings are still enforced.
  bool Function(String deviceHex, Uint8List signed, Uint8List proof)?
  verifyCommitProof;

  final _challenges =
      <
        String,
        ({String account, String device, int fromEpoch, Uint8List nonce})
      >{};
  final _random = Random.secure();

  /// Commit submissions the server refused (any reason).
  int refusedCommits = 0;

  final List<String> members;

  /// The server's device status (from the account's registry).
  final DeviceStatus Function(String account, String deviceHex) statusOf;

  int epoch = 0;
  bool active = true;

  /// Every call fails as if the network were down.
  bool offline = false;

  /// The next write lands but its acknowledgement is lost.
  bool loseNextAck = false;

  final keyPackageDocs = <String, PublishedKeyPackage>{};
  final commits = <int, CommitRecord>{};
  final welcomeDocs = <String, WelcomeRecord>{};
  final messageDocs = <String, EncryptedMessageEnvelope>{};

  /// Documents that fail to parse, per epoch (a malicious or buggy writer).
  final malformed = <int, int>{};
  int _time = 1000;
  int writes = 0;

  void _online() {
    if (offline) throw const TransportException(TransportFailure.unavailable);
  }

  bool _activeMember(String account, String deviceHex) =>
      active &&
      members.contains(account) &&
      statusOf(account, deviceHex) == DeviceStatus.active;

  @override
  Future<ConversationRecord> conversation(ConversationId id) async {
    _online();
    return ConversationRecord(members: members, epoch: epoch, active: active);
  }

  @override
  Future<void> publishKeyPackage(
    ConversationId id,
    PublishedKeyPackage kp,
  ) async {
    _online();
    if (!_activeMember(kp.accountId, kp.deviceIdHex)) {
      throw const TransportException(TransportFailure.denied);
    }
    keyPackageDocs[kp.deviceIdHex] = kp;
  }

  @override
  Future<List<PublishedKeyPackage>> keyPackages(ConversationId id) async {
    _online();
    return keyPackageDocs.values.toList();
  }

  @override
  Future<CommitChallenge> requestCommitChallenge(
    ConversationId id, {
    required String deviceIdHex,
    required int fromEpoch,
  }) async {
    _online();
    final account = _accountOf(deviceIdHex);
    if (account == null || fromEpoch != epoch) {
      throw const TransportException(TransportFailure.denied);
    }
    final challengeId = [
      for (var i = 0; i < 16; i++) _random.nextInt(256),
    ].map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final nonce = Uint8List.fromList([
      for (var i = 0; i < 32; i++) _random.nextInt(256),
    ]);
    _challenges[challengeId] = (
      account: account,
      device: deviceIdHex,
      fromEpoch: fromEpoch,
      nonce: nonce,
    );
    return CommitChallenge(challengeId: challengeId, nonce: nonce);
  }

  /// The member account whose ACTIVE device this is (the caller's own
  /// account on the real server), or null.
  String? _accountOf(String deviceHex) {
    for (final a in members) {
      if (_activeMember(a, deviceHex)) return a;
    }
    return null;
  }

  @override
  Future<WriteResult> submitCommit(
    ConversationId id,
    CommitRecord commit,
    List<WelcomeRecord> welcomes,
    CommitAuthorization authorization,
  ) async {
    if (offline) return const WriteResult(WriteOutcome.unavailable);
    // Single use whatever the outcome, as on the server.
    final c = _challenges.remove(authorization.challengeId);
    final verify = verifyCommitProof;
    final authorized =
        c != null &&
        c.device == commit.senderDeviceIdHex &&
        c.account == commit.senderAccountId &&
        c.fromEpoch == commit.epoch &&
        _activeMember(commit.senderAccountId, commit.senderDeviceIdHex) &&
        (verify == null ||
            verify(
              commit.senderDeviceIdHex,
              commitAuthorizationChallenge(
                nonce: c.nonce,
                accountId: c.account,
                deviceId: EncryptedMessageEnvelope.bytesOfHex(c.device),
                conversationId: id.bytes,
                fromEpoch: c.fromEpoch,
                protocolVersion: MessageVersions.protocol,
                commit: commit.commit,
                welcomes: [
                  for (final w in welcomes)
                    AuthorizedWelcome(
                      targetDeviceId: EncryptedMessageEnvelope.bytesOfHex(
                        w.targetDeviceIdHex,
                      ),
                      welcome: w.welcome,
                    ),
                ],
              ),
              authorization.proof,
            ));
    if (!authorized ||
        commits.containsKey(commit.epoch) ||
        commit.epoch != epoch) {
      refusedCommits++;
      return const WriteResult(WriteOutcome.refused);
    }
    writes++;
    commits[commit.epoch] = commit;
    epoch++;
    for (final w in welcomes) {
      welcomeDocs['${w.targetDeviceIdHex}_${w.epoch}'] = w;
    }
    return _ack(const WriteResult(WriteOutcome.accepted));
  }

  @override
  Future<CommitRecord?> commit(ConversationId id, int epoch) async {
    _online();
    return commits[epoch];
  }

  @override
  Future<List<WelcomeRecord>> welcomesFor(
    ConversationId id,
    String deviceHex,
  ) async {
    _online();
    return [
      for (final w in welcomeDocs.values)
        if (w.targetDeviceIdHex == deviceHex) w,
    ];
  }

  @override
  Future<WriteResult> submitMessage(
    ConversationId id,
    EncryptedMessageEnvelope e,
  ) async {
    if (offline) return const WriteResult(WriteOutcome.unavailable);
    if (messageDocs.containsKey(e.messageIdHex) ||
        e.epoch != epoch ||
        !_activeMember(e.senderAccountId, e.senderDeviceIdHex)) {
      return const WriteResult(WriteOutcome.refused);
    }
    writes++;
    final stored = stamp(e, ++_time);
    messageDocs[e.messageIdHex] = stored;
    return _ack(WriteResult(WriteOutcome.accepted, serverTimeMs: _time));
  }

  WriteResult _ack(WriteResult result) {
    if (!loseNextAck) return result;
    loseNextAck = false;
    return const WriteResult(WriteOutcome.unavailable);
  }

  /// A copy with the server time set (what the server stores).
  static EncryptedMessageEnvelope stamp(EncryptedMessageEnvelope e, int t) =>
      EncryptedMessageEnvelope(
        messageId: e.messageId,
        schemaVersion: e.schemaVersion,
        protocolVersion: e.protocolVersion,
        senderAccountId: e.senderAccountId,
        senderDeviceId: e.senderDeviceId,
        epoch: e.epoch,
        ciphertext: e.ciphertext,
        serverTimeMs: t,
      );

  @override
  Future<EncryptedMessageEnvelope?> message(
    ConversationId id,
    String hexId,
  ) async {
    _online();
    return messageDocs[hexId];
  }

  @override
  Future<({List<EncryptedMessageEnvelope> messages, int malformedCount})>
  messagesAtEpoch(ConversationId id, int epoch) async {
    _online();
    final list = messageDocs.values.where((m) => m.epoch == epoch).toList()
      ..sort((a, b) => a.serverTimeMs!.compareTo(b.serverTimeMs!));
    return (messages: list, malformedCount: malformed[epoch] ?? 0);
  }
}
