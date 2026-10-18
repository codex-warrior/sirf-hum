import 'dart:typed_data';

import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';
// The Web implementation, tested directly on the VM: it must fail closed.
import 'package:sirf_hum_crypto/src/core_unsupported.dart' as web;
import 'package:test/test.dart';

Matcher _fails(CryptoErrorCode code) =>
    throwsA(isA<CryptoException>().having((e) => e.code, 'code', code));

void main() {
  test('error codes match the native table and unknown codes are internal', () {
    // Mirrors native/src/error.rs; a change there must be mirrored here.
    expect(CryptoErrorCode.values.map((e) => e.code), [
      for (var i = -1; i >= -17; i--) i,
    ]);
    expect(CryptoErrorCode.fromCode(-999), CryptoErrorCode.internal);
    expect(CryptoErrorCode.fromCode(0), CryptoErrorCode.internal);
    expect(
      const CryptoException(CryptoErrorCode.replay).toString(),
      'CryptoException(replay)',
    );
  });

  test('identifiers validate length and copy defensively', () {
    expect(() => DeviceId(Uint8List(15)), _fails(CryptoErrorCode.invalidInput));
    expect(
      () => PersonKey(Uint8List(31)),
      _fails(CryptoErrorCode.invalidInput),
    );
    expect(() => GroupId(Uint8List(0)), _fails(CryptoErrorCode.invalidInput));
    expect(() => AccountId(''), _fails(CryptoErrorCode.invalidInput));
    expect(() => AccountId('x' * 129), _fails(CryptoErrorCode.invalidInput));
    final source = Uint8List(16);
    final id = DeviceId(source);
    source[0] = 9;
    expect(id.bytes[0], 0);
    expect(DeviceId(Uint8List(16)), id);
    expect(DeviceId(Uint8List(16)) == PersonKey(Uint8List(32)), isFalse);
  });

  test('nothing prints identifiers or plaintext', () {
    final values = <Object>[
      AccountId('account-alice'),
      DeviceId(Uint8List(16)),
      PersonKey(Uint8List(32)),
      GroupId(Uint8List.fromList([1])),
      IncomingApplication(Uint8List.fromList([104, 105])),
      AddMemberResult(commit: Uint8List(1), welcome: Uint8List(1)),
    ];
    for (final v in values) {
      expect(v.toString(), contains('<redacted>'));
      expect(v.toString(), isNot(contains('alice')));
    }
  });

  test('the key store wire values match the native ABI', () {
    expect(KeyStoreKind.insecureTestEphemeral.wireValue, 1);
    expect(KeyStoreKind.insecureTestFile.wireValue, 2);
    expect(KeyStoreKind.platform.wireValue, 100);
  });

  test('Web implementation is unavailable and fails closed', () {
    expect(web.CryptoCore.isAvailable, isFalse);
    expect(
      () => web.CryptoCore.initialize(
        directory: '/x',
        keyStore: KeyStoreKind.insecureTestEphemeral,
      ),
      _fails(CryptoErrorCode.unsupported),
    );
  });
}
