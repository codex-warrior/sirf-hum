import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/security/couple/couple_profiles.dart';

void main() {
  group('display names are re-validated on read (rules: validDisplayName)', () {
    test('accepts ordinary names, trimmed', () {
      expect(CoupleNames.sanitize('Asha'), 'Asha');
      expect(CoupleNames.sanitize('  Ravi '), 'Ravi');
      expect(CoupleNames.sanitize('आशा'), 'आशा');
      expect(CoupleNames.sanitize('a' * 64), 'a' * 64);
    });

    test('rejects anything the rules would not allow', () {
      for (final bad in <Object?>[
        null,
        42,
        '',
        '   ',
        'a' * 65,
        'Ravi\u0000',
        'line\nbreak',
        'del\u007f',
      ]) {
        expect(CoupleNames.sanitize(bad), isNull, reason: '$bad');
      }
    });
  });

  test('names never print', () {
    const names = CoupleNames(yours: 'Asha', partner: 'Ravi');
    expect(names.toString(), isNot(contains('Asha')));
    expect(names.toString(), isNot(contains('Ravi')));
  });
}
