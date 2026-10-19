import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/features/home/domain/greeting.dart';
import 'package:sirf_hum/security/couple/couple_profiles.dart';

void main() {
  test('greeting follows the local time of day', () {
    expect(greetingFor(DateTime(2026, 1, 1, 5)), 'Good morning');
    expect(greetingFor(DateTime(2026, 1, 1, 11, 59)), 'Good morning');
    expect(greetingFor(DateTime(2026, 1, 1, 12)), 'Good afternoon');
    expect(greetingFor(DateTime(2026, 1, 1, 17)), 'Good evening');
    expect(greetingFor(DateTime(2026, 1, 1, 22)), 'Hello, you two');
    expect(greetingFor(DateTime(2026, 1, 1, 3)), 'Hello, you two');
  });

  test('the couple title reads naturally for every profile combination', () {
    expect(
      coupleTitle(const CoupleNames(yours: 'Asha', partner: 'Ravi')),
      'Asha & Ravi',
    );
    expect(coupleTitle(const CoupleNames(partner: 'Ravi')), 'You & Ravi');
    expect(coupleTitle(const CoupleNames(yours: 'Asha')), 'Asha & your person');
    expect(coupleTitle(CoupleNames.unknown), 'Just the two of you');
  });
}
