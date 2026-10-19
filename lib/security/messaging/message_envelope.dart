import 'dart:typed_data';

import 'package:sirf_hum/security/crypto/encrypted_envelope.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// The server-visible record of one encrypted message (D-089,
/// E2EE-MESSAGING-DESIGN §6): `conversations/{c}/messages/{messageId}`.
///
/// Every routing field here is also bound into the MLS authenticated data
/// by the Rust core, except [senderAccountId] (checked against the verified
/// lineage) and [serverTimeMs] (transport ordering only). It never holds
/// plaintext, previews or the payload kind.
class EncryptedMessageEnvelope {
  EncryptedMessageEnvelope({
    required this.messageId,
    required this.schemaVersion,
    required this.protocolVersion,
    required this.senderAccountId,
    required this.senderDeviceId,
    required this.epoch,
    required Uint8List ciphertext,
    this.serverTimeMs,
  }) : ciphertext = Uint8List.fromList(ciphertext) {
    if (ciphertext.isEmpty || ciphertext.length > maxCiphertextBytes) {
      throw const EnvelopeFormatException();
    }
    if (epoch < 1 || schemaVersion < 1 || protocolVersion < 1) {
      throw const EnvelopeFormatException();
    }
  }

  /// Matches the core limit and the Firestore rule.
  static const int maxCiphertextBytes = 32 * 1024;

  static final RegExp _hexId = RegExp(r'^[0-9a-f]{32}$');
  static final RegExp _account = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  final MessageId messageId;
  final int schemaVersion;
  final int protocolVersion;
  final String senderAccountId;
  final DeviceId senderDeviceId;
  final int epoch;
  final Uint8List ciphertext;

  /// Set by the server (`request.time`); null on outgoing envelopes.
  final int? serverTimeMs;

  String get messageIdHex => hexOf(messageId.bytes);
  String get senderDeviceIdHex => hexOf(senderDeviceId.bytes);

  /// The crossing into infrastructure as opaque ciphertext (security README).
  EncryptedEnvelope get opaque =>
      EncryptedEnvelope(protocolVersion: protocolVersion, bytes: ciphertext);

  /// Firestore fields, minus `serverTime` (the transport adds the server
  /// timestamp). Exactly the fields the rules allow.
  Map<String, Object> toFields() => {
    'schemaVersion': schemaVersion,
    'protocolVersion': protocolVersion,
    'senderAccountId': senderAccountId,
    'senderDeviceId': senderDeviceIdHex,
    'epoch': epoch,
    'ciphertext': ciphertext,
  };

  /// Strictly parses a stored document. Unknown or missing fields, wrong
  /// types, malformed IDs or oversized ciphertext throw
  /// [EnvelopeFormatException]: a malformed remote message never crashes
  /// the app and is never guessed at. Versions are passed through: the core
  /// rejects them cryptographically (forged) or as unsupported (genuine).
  static EncryptedMessageEnvelope fromFields(
    String messageIdHex,
    Map<String, Object?> data, {
    required Uint8List Function(Object?) bytesOf,
    required int? Function(Object?) timeOf,
  }) {
    const allowed = {
      'schemaVersion',
      'protocolVersion',
      'senderAccountId',
      'senderDeviceId',
      'epoch',
      'ciphertext',
      'serverTime',
    };
    if (!allowed.containsAll(data.keys)) throw const EnvelopeFormatException();
    final account = data['senderAccountId'];
    final device = data['senderDeviceId'];
    final schema = data['schemaVersion'];
    final protocol = data['protocolVersion'];
    final epoch = data['epoch'];
    if (!_hexId.hasMatch(messageIdHex) ||
        account is! String ||
        !_account.hasMatch(account) ||
        device is! String ||
        !_hexId.hasMatch(device) ||
        schema is! int ||
        protocol is! int ||
        epoch is! int ||
        schema > 0xffff ||
        protocol > 0xffff) {
      throw const EnvelopeFormatException();
    }
    final Uint8List ciphertext;
    try {
      ciphertext = bytesOf(data['ciphertext']);
    } on Object {
      throw const EnvelopeFormatException();
    }
    return EncryptedMessageEnvelope(
      messageId: MessageId(bytesOfHex(messageIdHex)),
      schemaVersion: schema,
      protocolVersion: protocol,
      senderAccountId: account,
      senderDeviceId: DeviceId(bytesOfHex(device)),
      epoch: epoch,
      ciphertext: ciphertext,
      serverTimeMs: timeOf(data['serverTime']),
    );
  }

  static String hexOf(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List bytesOfHex(String hex) => Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);

  // Never prints IDs or ciphertext: logs are outside the trust boundary.
  @override
  String toString() =>
      'EncryptedMessageEnvelope(epoch: $epoch, ${ciphertext.length} bytes)';
}

class EnvelopeFormatException implements Exception {
  const EnvelopeFormatException();

  @override
  String toString() => 'EnvelopeFormatException()';
}
