import 'package:flutter/foundation.dart';

/// Opaque ciphertext produced on-device for private relationship content.
///
/// This is the *only* shape in which private content may cross from the
/// security layer into the data layer (Firestore, Cloud Storage, FCM). The
/// data layer must never accept plaintext private content.
///
/// The envelope deliberately knows nothing about the cipher: algorithm and key
/// selection belong to the E2EE protocol, which is designed in a dedicated
/// phase (docs/security/E2EE-REQUIREMENTS.md). [protocolVersion] lets readers
/// reject envelopes they do not understand instead of guessing.
@immutable
class EncryptedEnvelope {
  EncryptedEnvelope({required this.protocolVersion, required Uint8List bytes})
    : bytes = Uint8List.fromList(bytes) {
    if (protocolVersion < 1) {
      throw ArgumentError.value(
        protocolVersion,
        'protocolVersion',
        'must be >= 1',
      );
    }
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'must not be empty');
    }
  }

  final int protocolVersion;

  /// Defensive copy: callers cannot mutate the stored ciphertext.
  final Uint8List bytes;

  @override
  bool operator ==(Object other) =>
      other is EncryptedEnvelope &&
      other.protocolVersion == protocolVersion &&
      listEquals(other.bytes, bytes);

  @override
  int get hashCode => Object.hash(protocolVersion, Object.hashAll(bytes));

  // Never print bytes: logs and crash reports are outside the trust boundary.
  @override
  String toString() =>
      'EncryptedEnvelope(v$protocolVersion, ${bytes.length} bytes)';
}
