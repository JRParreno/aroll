import 'package:aroll_mobile/presentation/owner/setup/holiday_management_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('holiday pay rate labels', () {
    test('1.0 displays as Regular Pay — 100%', () {
      expect(holidayPayRateLabel(1.0), 'Regular Pay — 100%');
    });

    test('1.3 displays as 130% Pay', () {
      expect(holidayPayRateLabel(1.3), '130% Pay');
    });

    test('1.5 displays as 150% Pay', () {
      expect(holidayPayRateLabel(1.5), '150% Pay');
    });

    test('2.0 displays as Double Pay — 200%', () {
      expect(holidayPayRateLabel(2.0), 'Double Pay — 200%');
    });

    test('2.5 displays as 250% Pay', () {
      expect(holidayPayRateLabel(2.5), '250% Pay');
    });

    test('3.0 displays as Triple Pay — 300%', () {
      expect(holidayPayRateLabel(3.0), 'Triple Pay — 300%');
    });

    test('custom multiplier keeps display without rewriting storage value', () {
      expect(holidayPayRateLabel(1.75), '175% Pay');
      expect(percentToPayMultiplier(175), 1.75);
    });
  });

  group('custom percent maps to pay_multiplier', () {
    test('200% maps back to 2.0', () {
      expect(percentToPayMultiplier(200), 2.0);
    });

    test('130% maps back to 1.3', () {
      expect(percentToPayMultiplier(130), 1.3);
    });

    test('150% maps back to 1.5', () {
      expect(percentToPayMultiplier(150), 1.5);
    });

    test('existing custom multiplier round-trips for display input', () {
      const stored = 1.75;
      final pct = double.parse(multiplierToPercentInput(stored));
      expect(percentToPayMultiplier(pct), stored);
    });
  });

  group('OT premium presentation', () {
    test('null OT premium displays as 0% without inventing a new value', () {
      expect(
        holidayOtPremiumOwnerLabel(null),
        'No additional holiday OT premium — 0%',
      );
      expect(
        otPremiumWarning(''),
        'Extra pay for approved overtime worked this holiday.',
      );
    });

    test('30% OT premium label', () {
      expect(holidayOtPremiumOwnerLabel(30), '30% additional — 30%');
    });
  });

  test('unworked rule is locked for PH regular and special', () {
    final regular = unworkedRulePresentation(
      mode: 'philippine_labor',
      holidayType: 'regular',
      isPaid: false,
    );
    expect(regular.editable, isFalse);
    expect(regular.effectivePaysUnworked, isTrue);

    final special = unworkedRulePresentation(
      mode: 'philippine_labor',
      holidayType: 'special_non_working',
      isPaid: true,
    );
    expect(special.editable, isFalse);
    expect(special.effectivePaysUnworked, isFalse);
  });

  test('company and custom mode allow pay-when-not-working toggle', () {
    final company = unworkedRulePresentation(
      mode: 'philippine_labor',
      holidayType: 'company',
      isPaid: true,
    );
    expect(company.editable, isTrue);
    expect(company.effectivePaysUnworked, isTrue);

    final custom = unworkedRulePresentation(
      mode: 'custom_company',
      holidayType: 'regular',
      isPaid: false,
    );
    expect(custom.editable, isTrue);
    expect(custom.effectivePaysUnworked, isFalse);
  });

  test('short pay copy and edit action label', () {
    expect(HolidayTerms.editHolidayPay, 'Edit holiday pay');
    expect(workedRateNote(1.0, custom: false), 'Regular pay. No extra holiday pay.');
    expect(
      workedRateNote(2.0, custom: false),
      'Double pay for eligible holiday work.',
    );
    expect(workedRateNote(1.75, custom: true), contains('200% is double pay'));
    expect(
      unworkedRulePresentation(
        mode: 'philippine_labor',
        holidayType: 'company',
        isPaid: true,
      ).explanation,
      'Pay their scheduled day if they do not work.',
    );
    expect(
      otPremiumWarning(''),
      'Extra pay for approved overtime worked this holiday.',
    );
    expect(
      otPremiumWarning('30'),
      'Extra pay for approved overtime worked this holiday.',
    );
    expect(holidayPayRateParts(2.0).title, 'Double Pay');
    expect(holidayPayRateParts(2.0).detail, '200%');
    expect(holidayPayRateCardLine(2.0), 'Double Pay · 200%');
    expect(holidayOtCardLine(null), 'No Extra OT');
    expect(holidayOtCardLine(30), '30%');
    expect(multiplierWarning(1.0), isNull);
  });

  test('duplicate active holiday detection', () {
    final holidays = [
      {
        'id': 'a',
        'name': 'Existing',
        'holiday_date': '2026-09-23',
        'holiday_type': 'company',
        'is_active': true,
      },
    ];
    final hit = findDuplicateActiveHoliday(
      holidays: holidays,
      holidayDate: '2026-09-23',
    );
    expect(hit?.name, 'Existing');
    expect(
      findDuplicateActiveHoliday(
        holidays: holidays,
        holidayDate: '2026-09-23',
        excludeId: 'a',
      ),
      isNull,
    );
  });

  test('rule summary uses total pay-rate wording', () {
    final summary = buildRuleSummary(
      name: 'Birthday ni Sid',
      holidayType: 'company',
      mode: 'philippine_labor',
      isPaid: true,
      payMultiplier: 2.0,
      otPremiumRaw: '',
    );
    expect(summary.holiday, 'Birthday ni Sid');
    expect(summary.type, 'Company Holiday');
    expect(summary.worked.first, contains('Double Pay — 200%'));
    expect(summary.worked.first, contains('total pay rate'));
    expect(summary.overtime.any((l) => l.contains('0%')), isTrue);
  });

  test('compact rule line uses human-readable rate', () {
    expect(
      compactRuleLine(
        mode: 'philippine_labor',
        holidayType: 'company',
        isPaid: true,
        payMultiplier: 2.0,
      ),
      'Double Pay — 200% · Pay Scheduled Day',
    );
    expect(
      compactRuleLine(
        mode: 'philippine_labor',
        holidayType: 'company',
        isPaid: true,
        payMultiplier: 1.0,
      ),
      'Regular Pay — 100% · Pay Scheduled Day',
    );
  });

  test('terminology uses Holiday Pay Rate not Pay Multiplier', () {
    expect(HolidayTerms.workedPremium, 'Holiday Pay Rate');
    expect(HolidayTerms.payWhenNotWorking, 'Pay Scheduled Day When Not Working');
    expect(HolidayTerms.holidayOtPremium, 'Holiday OT Premium');
  });
}
