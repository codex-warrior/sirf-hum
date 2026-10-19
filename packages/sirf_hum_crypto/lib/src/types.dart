import 'dart:convert';
import 'dart:typed_data';

/// Stable error categories. Codes match `native/src/error.rs` (`CoreError`)
/// and never change meaning; new categories get new codes.
enum CryptoErrorCode {
  invalidInput(-1),
  inputTooLarge(-2),
  invalidCredential(-3),
  unauthorizedDevice(-4),
  malformedMessage(-5),
  authenticationFailure(-6),
  replay(-7),
  staleEpoch(-8),
  unknownGroup(-9),
  protocolViolation(-10),
  stateCorruption(-11),
  persistenceFailure(-12),
  rollbackFailure(-13),
  unsupported(-14),
  internalCryptoFailure(-15),
  identityState(-16),
  internal(-17),
  accountMismatch(-18),
  recoveryKeyInvalid(-19),
  trustStateStale(-20),
  trustChainInvalid(-21),

  /// A staged commit awaits confirm/discard (D-087): resolve it first.
  commitPending(-22),

  /// confirm/discard named no staged commit (or another epoch).
  noStagedCommit(-23),

  /// The message is for a later epoch: apply commits, then retry (D-091).
  futureEpoch(-24),

  /// Authenticated message data does not match the envelope (D-089).
  envelopeMismatch(-25);

  const CryptoErrorCode(this.code);

  final int code;

  /// Unknown codes map to [internal]: never guess a more specific meaning.
  static CryptoErrorCode fromCode(int code) => values.firstWhere(
    (e) => e.code == code,
    orElse: () => CryptoErrorCode.internal,
  );
}

/// A crypto-core failure. Carries only the category: no message bytes, keys
/// or native strings, so it is safe to log and to report.
class CryptoException implements Exception {
  const CryptoException(this.code);

  final CryptoErrorCode code;

  @override
  String toString() => 'CryptoException(${code.name})';
}

/// Where the core's key-encryption key comes from.
///
/// The test adapters are **insecure** and refused in release builds; never
/// use them for real users. [platform] is the Android Keystore / iOS Keychain
/// adapter (D-066), whose key the app passes in.
enum KeyStoreKind {
  /// KEK lives in memory only; state is unreadable after restart.
  insecureTestEphemeral(1),

  /// KEK is a plaintext file next to the state. Restart-capable tests only.
  insecureTestFile(2),

  /// The platform key store (Android Keystore / iOS Keychain, D-066). Opened
  /// through `CryptoCore.initializeWithPlatformKey`, never `initialize`.
  platform(100);

  const KeyStoreKind(this.wireValue);

  final int wireValue;
}

/// What a device proof of possession is for (D-070). Each purpose is a
/// separate signed domain; values match the native ABI.
enum DeviceProofPurpose {
  activation(1),

  /// A new device proving possession while it awaits approval (Prompt 08).
  enrollment(2),

  /// An active device registering or clearing its own push token (Prompt 11,
  /// D-098). The server binds the challenge to the token's hash.
  pushToken(3);

  const DeviceProofPurpose(this.wireValue);

  final int wireValue;
}

/// Zeroes [bytes] in place. Never throws: an unmodifiable view (e.g. one
/// decoded by a platform channel) is left as is, because a wipe must never
/// mask the real outcome of the operation it follows.
void wipeBytes(Uint8List bytes) {
  try {
    bytes.fillRange(0, bytes.length, 0);
  } on UnsupportedError {
    // Not ours to wipe; the owner of the underlying buffer must do it.
  }
}

/// The account a device belongs to (validated: 1–128 UTF-8 bytes).
class AccountId {
  AccountId(this.value) {
    final length = utf8.encode(value).length;
    if (length == 0 || length > 128) {
      throw const CryptoException(CryptoErrorCode.invalidInput);
    }
  }

  final String value;

  @override
  bool operator ==(Object other) => other is AccountId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'AccountId(<redacted>)';
}

/// Fixed-length public identifier wrapper with defensive copies and
/// redacted printing.
abstract class ByteIdentifier {
  ByteIdentifier(Uint8List bytes, int length)
    : bytes = Uint8List.fromList(bytes) {
    if (length >= 0 && bytes.length != length) {
      throw const CryptoException(CryptoErrorCode.invalidInput);
    }
  }

  final Uint8List bytes;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is ByteIdentifier &&
      _equal(other.bytes, bytes);

  @override
  int get hashCode => Object.hashAll(bytes);
}

bool _equal(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// One device's identifier (16 bytes, derived from its MLS signature key).
class DeviceId extends ByteIdentifier {
  DeviceId(Uint8List bytes) : super(bytes, 16);

  @override
  String toString() => 'DeviceId(<redacted>)';
}

/// A person's public identity key (Ed25519, 32 bytes). Public, but still an
/// identifier: not printed.
class PersonKey extends ByteIdentifier {
  PersonKey(Uint8List bytes) : super(bytes, 32);

  @override
  String toString() => 'PersonKey(<redacted>)';
}

/// An MLS group identifier (opaque).
class GroupId extends ByteIdentifier {
  GroupId(Uint8List bytes) : super(bytes, -1) {
    if (bytes.isEmpty) {
      throw const CryptoException(CryptoErrorCode.invalidInput);
    }
  }

  @override
  String toString() => 'GroupId(<redacted>)';
}

/// Public identity material of this device. Contains no private key.
class PublicIdentity {
  PublicIdentity({
    required this.deviceId,
    required this.personKey,
    required Uint8List certificate,
  }) : certificate = Uint8List.fromList(certificate);

  final DeviceId deviceId;
  final PersonKey personKey;

  /// Device certificate signed by the person key (public).
  final Uint8List certificate;

  @override
  String toString() => 'PublicIdentity(<redacted>)';
}

/// One group member.
class RosterEntry {
  const RosterEntry({required this.deviceId, required this.personKey});

  final DeviceId deviceId;
  final PersonKey personKey;

  @override
  String toString() => 'RosterEntry(<redacted>)';
}

/// Outputs of adding a member: the commit for existing members and the
/// Welcome for the new device. Both are MLS wire messages (not secrets).
class AddMemberResult {
  AddMemberResult({required Uint8List commit, required Uint8List welcome})
    : commit = Uint8List.fromList(commit),
      welcome = Uint8List.fromList(welcome);

  final Uint8List commit;
  final Uint8List welcome;

  @override
  String toString() => 'AddMemberResult(<redacted>)';
}

/// Why a device was revoked (wire values match the native ABI, D-081).
enum RevocationReason {
  removed(1),
  lost(2),
  stolen(3),
  compromised(4);

  const RevocationReason(this.wireValue);

  final int wireValue;
}

/// A newly created recovery key (D-076). [secret] is shown to the user once:
/// never store, send or log it.
class RecoveryKeyBundle {
  RecoveryKeyBundle({
    required this.secret,
    required Uint8List publicKey,
    required Uint8List registrationSignature,
  }) : publicKey = Uint8List.fromList(publicKey),
       registrationSignature = Uint8List.fromList(registrationSignature);

  final String secret;

  /// Public half, registered with the server.
  final Uint8List publicKey;

  /// This device's PIK signature registering [publicKey].
  final Uint8List registrationSignature;

  @override
  String toString() => 'RecoveryKeyBundle(<redacted>)';
}

/// A recovery approval for this device, signed with the recovery key.
class RecoveryApprovalResult {
  RecoveryApprovalResult({
    required Uint8List signature,
    required Uint8List recoveryPublicKey,
  }) : signature = Uint8List.fromList(signature),
       recoveryPublicKey = Uint8List.fromList(recoveryPublicKey);

  final Uint8List signature;
  final Uint8List recoveryPublicKey;

  @override
  String toString() => 'RecoveryApprovalResult(<redacted>)';
}

/// The result of processing one incoming MLS message.
sealed class IncomingResult {
  const IncomingResult();
}

/// A decrypted application message. [plaintext] is private content: never
/// log, persist unencrypted, or send it anywhere.
final class IncomingApplication extends IncomingResult {
  IncomingApplication(this.plaintext);

  final Uint8List plaintext;

  @override
  String toString() => 'IncomingApplication(<redacted>)';
}

/// A commit was validated and applied; the group is now at [epoch].
final class IncomingCommit extends IncomingResult {
  const IncomingCommit(this.epoch);

  final int epoch;

  @override
  String toString() => 'IncomingCommit(epoch: $epoch)';
}

/// This device was removed; its local group state has been deleted.
final class IncomingRemoved extends IncomingResult {
  const IncomingRemoved();

  @override
  String toString() => 'IncomingRemoved()';
}

// ------------------------------------------------------------------ ABI v5
// Messaging core (Prompt 10, docs/security/E2EE-MESSAGING-DESIGN.md).

/// A conversation ID (16 bytes, server-generated). It is also the MLS group
/// ID of the conversation (D-086).
class ConversationId extends ByteIdentifier {
  ConversationId(Uint8List bytes) : super(bytes, 16);

  @override
  String toString() => 'ConversationId(<redacted>)';
}

/// A message ID (16 random bytes generated by the core, D-089). Not secret,
/// never derived from content.
class MessageId extends ByteIdentifier {
  MessageId(Uint8List bytes) : super(bytes, 16);

  @override
  String toString() => 'MessageId(<redacted>)';
}

/// Versions bound into every message's authenticated data (D-089).
abstract final class MessageVersions {
  static const int schema = 1;
  static const int protocol = 1;
}

/// A commit generated but not applied (D-087). Upload it (and [welcome],
/// for adds) for [fromEpoch]; then confirm or discard.
class StagedCommit {
  StagedCommit({
    required this.fromEpoch,
    required Uint8List commit,
    Uint8List? welcome,
  }) : commit = Uint8List.fromList(commit),
       welcome = welcome == null || welcome.isEmpty
           ? null
           : Uint8List.fromList(welcome);

  final int fromEpoch;
  final Uint8List commit;
  final Uint8List? welcome;

  @override
  String toString() => 'StagedCommit(fromEpoch: $fromEpoch, <redacted>)';
}

/// An encrypted outgoing message, ready for its envelope.
class SentMessage {
  SentMessage({
    required this.messageId,
    required this.epoch,
    required Uint8List ciphertext,
  }) : ciphertext = Uint8List.fromList(ciphertext);

  final MessageId messageId;
  final int epoch;
  final Uint8List ciphertext;

  @override
  String toString() => 'SentMessage(epoch: $epoch, <redacted>)';
}

/// The outcome of receiving one message. [payload] is private content.
class ReceivedMessage {
  ReceivedMessage({required this.payload, required this.duplicate});

  final Uint8List payload;

  /// Already in local history: nothing was processed, [payload] is empty.
  final bool duplicate;

  @override
  String toString() => 'ReceivedMessage(duplicate: $duplicate, <redacted>)';
}

enum MessageDirection {
  outgoing(1),
  incoming(2);

  const MessageDirection(this.wireValue);
  final int wireValue;
}

enum MessageState {
  /// Encrypted locally, not accepted by the server yet (the outbox).
  queued(1),

  /// Accepted by the server.
  sent(2),

  /// Received and decrypted.
  received(3);

  const MessageState(this.wireValue);
  final int wireValue;
}

/// One message of local history. [payload] is private content: display
/// only, never log or persist elsewhere.
class LocalMessage {
  LocalMessage({
    required this.messageId,
    required this.senderDeviceId,
    required this.direction,
    required this.state,
    required this.epoch,
    required this.createdAtMs,
    required this.serverTimeMs,
    required this.payload,
    this.ciphertext,
  });

  final MessageId messageId;
  final DeviceId senderDeviceId;
  final MessageDirection direction;
  final MessageState state;
  final int epoch;
  final int createdAtMs;

  /// 0 until the server time is known.
  final int serverTimeMs;
  final Uint8List payload;

  /// Only while [MessageState.queued].
  final Uint8List? ciphertext;

  @override
  String toString() =>
      'LocalMessage(${direction.name}, ${state.name}, <redacted>)';
}

/// Strictly decodes `sh_crypto_history` output (native
/// `LocalMessage::encode`). Any defect is [CryptoErrorCode.internal]:
/// never a partial history.
List<LocalMessage> decodeHistory(Uint8List bytes, ConversationId conversation) {
  const bad = CryptoException(CryptoErrorCode.internal);
  final view = ByteData.sublistView(bytes);
  var at = 0;
  int u8() {
    if (at + 1 > bytes.length) throw bad;
    return bytes[at++];
  }

  int u32() {
    if (at + 4 > bytes.length) throw bad;
    final v = view.getUint32(at, Endian.big);
    at += 4;
    return v;
  }

  int u64() {
    if (at + 8 > bytes.length) throw bad;
    final v = view.getUint64(at, Endian.big);
    at += 8;
    return v;
  }

  Uint8List take(int n) {
    if (at + n > bytes.length) throw bad;
    final v = Uint8List.fromList(bytes.sublist(at, at + n));
    at += n;
    return v;
  }

  T pick<T extends Enum>(List<T> values, int wire, int Function(T) of) =>
      values.firstWhere((v) => of(v) == wire, orElse: () => throw bad);

  final count = u32();
  final out = <LocalMessage>[];
  for (var i = 0; i < count; i++) {
    final end = u32() + at;
    if (u8() != 1 || !_sameBytes(take(16), conversation.bytes)) throw bad;
    final messageId = MessageId(take(16));
    final sender = DeviceId(take(16));
    final direction = pick(MessageDirection.values, u8(), (d) => d.wireValue);
    final state = pick(MessageState.values, u8(), (s) => s.wireValue);
    final epoch = u64();
    final created = u64();
    final server = u64();
    final payload = take(u32());
    final hasCiphertext = u8();
    final ciphertext = switch (hasCiphertext) {
      0 => null,
      1 => take(u32()),
      _ => throw bad,
    };
    if (at != end || (state == MessageState.queued) != (ciphertext != null)) {
      throw bad;
    }
    out.add(
      LocalMessage(
        messageId: messageId,
        senderDeviceId: sender,
        direction: direction,
        state: state,
        epoch: epoch,
        createdAtMs: created,
        serverTimeMs: server,
        payload: payload,
        ciphertext: ciphertext,
      ),
    );
  }
  if (at != bytes.length) throw bad;
  return out;
}

bool _sameBytes(Uint8List a, Uint8List b) => _equal(a, b);

/// `u32 count | count × (u32 len | bytes)`: the native list encoding.
Uint8List encodeByteList(List<Uint8List> items) {
  final builder = BytesBuilder(copy: false);
  final header = ByteData(4)..setUint32(0, items.length, Endian.big);
  builder.add(header.buffer.asUint8List());
  for (final item in items) {
    final len = ByteData(4)..setUint32(0, item.length, Endian.big);
    builder
      ..add(len.buffer.asUint8List())
      ..add(item);
  }
  return builder.toBytes();
}

// Encrypted media (Prompt 11, docs/security/E2EE-MEDIA-AND-NOTIFICATIONS.md).

/// What a media object is. It exists only inside the encrypted payload and
/// the media AAD; the server never learns it.
enum MediaClass {
  image(1),
  video(2),
  audio(3),
  file(4);

  const MediaClass(this.wireValue);
  final int wireValue;
}

/// A media object ID (16 random bytes generated by the core). Not secret;
/// it names the Storage object.
class MediaId extends ByteIdentifier {
  MediaId(Uint8List bytes) : super(bytes, 16);

  @override
  String toString() => 'MediaId(<redacted>)';
}

/// Media object format v1 (D-093): `header 25 B | chunks of 64 KiB + tag`.
abstract final class MediaLimits {
  /// Largest media plaintext (`MAX_MEDIA_PLAINTEXT_BYTES`).
  static const int maxPlaintextBytes = 64 * 1024 * 1024;
  static const int chunkBytes = 64 * 1024;
  static const int headerBytes = 25;
  static const int tagBytes = 16;

  /// Largest ciphertext object; matches the Storage rule.
  static const int maxObjectBytes = headerBytes + maxPlaintextBytes + 16 * 1024;

  /// The exact object size for a plaintext length.
  static int objectLength(int plaintextLength) =>
      headerBytes +
      plaintextLength +
      tagBytes * ((plaintextLength + chunkBytes - 1) ~/ chunkBytes);
}

/// The file name the core gives a media object in a media directory:
/// `<conversation hex>_<media hex>.shm` (native `media_object_file_name`).
String mediaObjectFileName(ConversationId conversation, MediaId media) =>
    '${_hexOf(conversation.bytes)}_${_hexOf(media.bytes)}.shm';

String _hexOf(Uint8List bytes) =>
    [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

/// What `sendMedia` produced: the queued message that delivers the key
/// (upload it after the object) and the ciphertext object's identity.
class SentMedia {
  SentMedia({
    required this.message,
    required this.mediaId,
    required this.objectLength,
  });

  final SentMessage message;
  final MediaId mediaId;

  /// Exact size of the ciphertext object ([mediaObjectFileName] in the
  /// media directory).
  final int objectLength;

  @override
  String toString() => 'SentMedia(epoch: ${message.epoch}, <redacted>)';
}

/// The key-free view of a media message (D-094): what `receiveMessage`
/// and `history` return for a media payload. The media key and the object
/// hash never leave the core.
///
/// ```text
/// version u8 = 1 | kind u8 = 2 | client time ms u64 | media id[16]
/// | class u8 | plaintext length u64 | object length u64     (43 bytes)
/// ```
class MediaRefView {
  MediaRefView._({
    required this.clientTimeMs,
    required this.mediaId,
    required this.mediaClass,
    required this.plaintextLength,
    required this.objectLength,
  });

  static const int length = 43;
  static const int version = 1;
  static const int kind = 2;

  final int clientTimeMs;
  final MediaId mediaId;
  final MediaClass mediaClass;
  final int plaintextLength;
  final int objectLength;

  /// True when [payload] claims to be a media message (version 1, kind 2).
  static bool isMedia(Uint8List payload) =>
      payload.length >= 2 && payload[0] == version && payload[1] == kind;

  /// Strict decode; any defect is [CryptoErrorCode.internal] (the core
  /// produced it, so a mismatch is a bug, never content to guess at).
  static MediaRefView decode(Uint8List payload) {
    const bad = CryptoException(CryptoErrorCode.internal);
    if (payload.length != length || !isMedia(payload)) throw bad;
    final view = ByteData.sublistView(payload);
    final classWire = payload[26];
    final mediaClass = MediaClass.values.firstWhere(
      (c) => c.wireValue == classWire,
      orElse: () => throw bad,
    );
    final plaintextLength = view.getUint64(27, Endian.big);
    final objectLength = view.getUint64(35, Endian.big);
    if (plaintextLength <= 0 ||
        plaintextLength > MediaLimits.maxPlaintextBytes ||
        objectLength != MediaLimits.objectLength(plaintextLength)) {
      throw bad;
    }
    return MediaRefView._(
      clientTimeMs: view.getUint64(2, Endian.big),
      mediaId: MediaId(Uint8List.fromList(payload.sublist(10, 26))),
      mediaClass: mediaClass,
      plaintextLength: plaintextLength,
      objectLength: objectLength,
    );
  }

  @override
  String toString() => 'MediaRefView(${mediaClass.name}, <redacted>)';
}
