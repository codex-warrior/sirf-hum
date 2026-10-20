// Safety number format (Prompt 17B, D-128): symmetric, bound to both roots
// and both accounts, and strict about certificates.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/security/verification/safety_number.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

PersonKey _key(int fill) =>
    PersonKey(Uint8List.fromList(List.filled(32, fill)));

SafetyNumber _n(String a, int ka, String b, int kb) => SafetyNumber.of(
  ownAccount: a,
  ownRoot: _key(ka),
  partnerAccount: b,
  partnerRoot: _key(kb),
);

void main() {
  test('both phones compute the same 60 digits and 69-byte QR payload', () {
    final mine = _n('accountA', 1, 'accountB', 2);
    final theirs = _n('accountB', 2, 'accountA', 1);
    expect(mine, theirs);
    expect(mine.groups, theirs.groups);
    expect(mine.groups, hasLength(12));
    for (final g in mine.groups) {
      expect(g, matches(RegExp(r'^\d{5}$')));
    }
    expect(mine.qrPayload, hasLength(SafetyNumber.payloadLength));
    expect(mine.matchesScanned(theirs.qrPayload), isTrue);
  });

  test('a different root on either side changes the number', () {
    final base = _n('accountA', 1, 'accountB', 2);
    expect(_n('accountA', 1, 'accountB', 3), isNot(base));
    expect(_n('accountA', 4, 'accountB', 2), isNot(base));
    expect(
      _n('accountA', 1, 'accountB', 3).groups.sublist(0, 6),
      base.groups.sublist(0, 6),
      reason: 'each half belongs to one person',
    );
  });

  test('roots are bound to their accounts (swapping them changes it)', () {
    expect(
      _n('accountA', 2, 'accountB', 1),
      isNot(_n('accountA', 1, 'accountB', 2)),
    );
    expect(
      _n('accountA', 1, 'accountC', 2),
      isNot(_n('accountA', 1, 'accountB', 2)),
    );
  });

  test('scanned payloads must match exactly', () {
    final n = _n('accountA', 1, 'accountB', 2);
    expect(n.matchesScanned(Uint8List(0)), isFalse);
    expect(n.matchesScanned(Uint8List(69)), isFalse);
    final flipped = n.qrPayload..[68] ^= 1;
    expect(n.matchesScanned(flipped), isFalse);
    expect(n.matchesScanned(Uint8List.fromList([...n.qrPayload, 0])), isFalse);
  });

  test('never prints the number', () {
    expect('${_n('accountA', 1, 'accountB', 2)}', 'SafetyNumber(<redacted>)');
  });

  test('one account cannot be both people', () {
    expect(() => _n('accountA', 1, 'accountA', 2), throwsArgumentError);
  });

  test('certificate fields are read strictly', () {
    final cert = Uint8List(165);
    final d = ByteData.sublistView(cert)
      ..setUint8(0, 1)
      ..setUint32(1, 32)
      ..setUint32(53, 32)
      ..setUint32(97, 64);
    cert.setRange(5, 37, List.filled(32, 7));
    cert.setRange(37, 53, List.filled(16, 9));
    expect(personKeyOfCertificate(cert), _key(7));
    expect(deviceIdOfCertificate(cert).bytes, List.filled(16, 9));
    for (final bad in [
      Uint8List(164),
      Uint8List.fromList([...cert, 0]),
      Uint8List.fromList(cert)..[0] = 2,
      Uint8List.fromList(cert)..[4] = 31,
    ]) {
      expect(
        () => personKeyOfCertificate(bad),
        throwsA(isA<CryptoException>()),
      );
    }
    d.setUint32(97, 63);
    expect(() => personKeyOfCertificate(cert), throwsA(isA<CryptoException>()));
  });
}
