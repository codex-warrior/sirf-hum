// In-memory server for messaging tests. It enforces what firebase/
// firestore.rules enforce (membership, active sender device, one commit per
// epoch with the epoch move, messages only at the current epoch,
// create-only documents) so the client's arbitration logic meets the same
// answers. The rules themselves are tested in firebase/tests/messaging.test.js.
import 'package:sirf_hum/security/device/device_status.dart';
import 'package:sirf_hum/security/messaging/conversation_transport.dart';
import 'package:sirf_hum/security/messaging/message_envelope.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

class FakeTransport implements ConversationTransport {
  FakeTransport({required this.members, required this.statusOf});

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
  Future<WriteResult> submitCommit(
    ConversationId id,
    CommitRecord commit,
    List<WelcomeRecord> welcomes,
  ) async {
    if (offline) return const WriteResult(WriteOutcome.unavailable);
    if (commits.containsKey(commit.epoch) ||
        commit.epoch != epoch ||
        !_activeMember(commit.senderAccountId, commit.senderDeviceIdHex)) {
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
