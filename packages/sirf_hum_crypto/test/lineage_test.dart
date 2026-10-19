// Lineage wire format (D-084): the Dart encoder must produce exactly the blob
// the server's vector generator produces, and the native verifier must
// return the expected trusted set. Vector: functions/test/vectors.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';
import 'package:test/test.dart';

final bool _required =
    Platform.environment['SIRF_HUM_REQUIRE_NATIVE_CRYPTO'] == '1';

Map<String, Object?> _vector() =>
    jsonDecode(
          File(
            '../../functions/test/vectors/device_trust_v2.json',
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

Uint8List _hex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

LineageRequest _requestFrom(Map<String, Object?> v) {
  Uint8List h(String k) => _hex(v[k]! as String);
  final exp = int.parse(v['expiresAtUnix']! as String);
  Uint8List ch(int b) => Uint8List.fromList(List.filled(32, b));
  return LineageRequest(
    accountId: v['accountId']! as String,
    rootCertificate: h('certAHex'),
    links: [
      ApprovalLink(
        approverCertificate: h('certAHex'),
        newCertificate: h('certBHex'),
        challenge: ch(0x71),
        expiresAtUnix: exp,
        signature: h('approvalABSignatureHex'),
      ),
      RecoveryLink(
        registrarCertificate: h('certBHex'),
        recoveryPublicKey: h('recoveryPublicKeyHex'),
        registrationChallenge: ch(0x72),
        registrationExpiresAtUnix: exp,
        registrationSignature: h('registrationSignatureHex'),
        newCertificate: h('certCHex'),
        challenge: ch(0x73),
        expiresAtUnix: exp,
        signature: h('recoveryCSignatureHex'),
      ),
    ],
    revocations: [
      SignedRevocation(
        revokerCertificate: h('certAHex'),
        revokedCertificate: h('certBHex'),
        reason: RevocationReason.stolen.wireValue,
        challenge: ch(0x74),
        expiresAtUnix: exp,
        signature: h('revocationSignatureHex'),
      ),
    ],
  );
}

void main() {
  test('Dart encodes the identical lineage blob as the server vector', () {
    final v = _vector();
    expect(_requestFrom(v).encode(), _hex(v['lineageBlobHex']! as String));
  });

  test('revocation reasons match the native wire values', () {
    expect(RevocationReason.values.map((r) => r.wireValue), [1, 2, 3, 4]);
  });

  test('lineage requests print redacted', () {
    expect(_requestFrom(_vector()).toString(), 'LineageRequest(<redacted>)');
  });

  test(
    'native verifier returns the expected trusted set (A, C; B revoked)',
    () {
      final v = _vector();
      final result = _hex(v['lineageResultHex']! as String);
      final trusted = CryptoCore.verifyLineage(_requestFrom(v));
      expect(trusted.map((d) => d.bytes), [
        result.sublist(4, 20),
        result.sublist(20, 36),
      ]);
    },
    skip: CryptoCore.isAvailable || _required
        ? false
        : 'no native crypto core on this host',
  );

  test(
    'a broken chain fails closed through the binding',
    () {
      final v = _vector();
      final good = _requestFrom(v);
      final broken = LineageRequest(
        accountId: 'someoneElse',
        rootCertificate: good.rootCertificate,
        links: good.links,
      );
      expect(
        () => CryptoCore.verifyLineage(broken),
        throwsA(
          isA<CryptoException>().having(
            (e) => e.code,
            'code',
            CryptoErrorCode.trustChainInvalid,
          ),
        ),
      );
    },
    skip: CryptoCore.isAvailable || _required
        ? false
        : 'no native crypto core on this host',
  );
}
