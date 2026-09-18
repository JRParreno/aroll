import 'package:aroll_mobile/presentation/owner/setup/holiday_ot_premium.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty OT premium is unconfigured, not zero', () {
    expect(parseHolidayOtPremium(null), isNull);
    expect(parseHolidayOtPremium(''), isNull);
    expect(parseHolidayOtPremium('   '), isNull);
    expect(holidayOtPremiumDisplay(null), '');
  });

  test('explicit 0 is configured zero percent', () {
    expect(parseHolidayOtPremium('0'), 0);
    expect(parseHolidayOtPremium('0.0'), 0);
    expect(holidayOtPremiumDisplay(0), '0');
    expect(holidayOtPremiumDisplay(0.0), '0');
  });

  test('positive OT premium is preserved', () {
    expect(parseHolidayOtPremium('30'), 30);
    expect(parseHolidayOtPremium('25.5'), 25.5);
    expect(holidayOtPremiumDisplay(30), '30');
  });

  test('negative OT premium is invalid', () {
    expect(isHolidayOtPremiumInvalid(''), isFalse);
    expect(isHolidayOtPremiumInvalid('0'), isFalse);
    expect(isHolidayOtPremiumInvalid('30'), isFalse);
    expect(isHolidayOtPremiumInvalid('-1'), isTrue);
    expect(isHolidayOtPremiumInvalid('abc'), isTrue);
  });
}
