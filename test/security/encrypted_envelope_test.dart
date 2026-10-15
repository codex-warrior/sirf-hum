import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/security/crypto/encrypted_envelope.dart';

void main() {
  test('toString never exposes ciphertext bytes', () {
    final envelope = EncryptedEnvelope(
      protocolVersion: 1,
      bytes: Uint8List.fromList([0xde, 0xad, 0xbe, 0xef]),
    );

    final text = envelope.toString();
    expect(text, 'EncryptedEnvelope(v1, 4 bytes)');
    for (final fragment in ['222', '173', 'de', 'ad', 'be', 'ef', '[']) {
      expect(text, isNot(contains(fragment)));
    }
  });

  test('stores a defensive copy of the bytes', () {
    final source = Uint8List.fromList([1, 2, 3]);
    final envelope = EncryptedEnvelope(protocolVersion: 1, bytes: source);

    source[0] = 99;
    expect(envelope.bytes, [1, 2, 3]);
  });

  test('rejects empty payloads and invalid versions', () {
    expect(
      () => EncryptedEnvelope(protocolVersion: 1, bytes: Uint8List(0)),
      throwsArgumentError,
    );
    expect(
      () => EncryptedEnvelope(protocolVersion: 0, bytes: Uint8List(1)),
      throwsArgumentError,
    );
  });

  test('value equality', () {
    EncryptedEnvelope make(int v, List<int> b) =>
        EncryptedEnvelope(protocolVersion: v, bytes: Uint8List.fromList(b));

    expect(make(1, [1, 2]), make(1, [1, 2]));
    expect(make(1, [1, 2]).hashCode, make(1, [1, 2]).hashCode);
    expect(make(1, [1, 2]), isNot(make(2, [1, 2])));
    expect(make(1, [1, 2]), isNot(make(1, [2, 1])));
  });
}
