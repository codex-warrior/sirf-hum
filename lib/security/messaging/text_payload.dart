import 'dart:convert';
import 'dart:typed_data';

/// Why a text cannot be sent. Categories only; never the text.
enum TextPayloadFailure { empty, tooLong, malformed, unsupported }

class TextPayloadException implements Exception {
  const TextPayloadException(this.failure);

  final TextPayloadFailure failure;

  @override
  String toString() => 'TextPayloadException(${failure.name})';
}

/// The encrypted application payload of a text message (D-089):
///
/// ```text
/// version u8 = 1 | kind u8 (1 = text) | client time ms u64 BE | u32 len | UTF-8
/// ```
///
/// It exists only inside MLS ciphertext and the sealed local history. The
/// client time is the sender's clock, for display only; ordering uses the
/// server time (D-091). Media kinds come later with their own payloads
/// (Prompt 11); unknown versions or kinds fail closed.
class TextPayload {
  TextPayload({required this.text, required this.clientTimeMs}) {
    if (text.trim().isEmpty) {
      throw const TextPayloadException(TextPayloadFailure.empty);
    }
    if (utf8.encode(text).length > maxTextBytes) {
      throw const TextPayloadException(TextPayloadFailure.tooLong);
    }
  }

  static const int version = 1;
  static const int kindText = 1;

  /// Text limit (E2EE-MESSAGING-DESIGN §11); the payload stays under the
  /// core's 16 KiB message limit.
  static const int maxTextBytes = 16000;

  /// Private content: never log it.
  final String text;
  final int clientTimeMs;

  Uint8List encode() {
    final body = utf8.encode(text);
    final out = ByteData(14 + body.length)
      ..setUint8(0, version)
      ..setUint8(1, kindText)
      ..setUint64(2, clientTimeMs, Endian.big)
      ..setUint32(10, body.length, Endian.big);
    final bytes = out.buffer.asUint8List()
      ..setRange(14, 14 + body.length, body);
    return bytes;
  }

  /// Strict decode: exact length, valid UTF-8, known version and kind.
  static TextPayload decode(Uint8List bytes) {
    if (bytes.length < 14) {
      throw const TextPayloadException(TextPayloadFailure.malformed);
    }
    final view = ByteData.sublistView(bytes);
    if (view.getUint8(0) != version || view.getUint8(1) != kindText) {
      throw const TextPayloadException(TextPayloadFailure.unsupported);
    }
    final length = view.getUint32(10, Endian.big);
    if (bytes.length != 14 + length) {
      throw const TextPayloadException(TextPayloadFailure.malformed);
    }
    final String text;
    try {
      text = utf8.decode(bytes.sublist(14), allowMalformed: false);
    } on FormatException {
      throw const TextPayloadException(TextPayloadFailure.malformed);
    }
    return TextPayload(text: text, clientTimeMs: view.getUint64(2, Endian.big));
  }

  @override
  String toString() => 'TextPayload(<redacted>)';
}
