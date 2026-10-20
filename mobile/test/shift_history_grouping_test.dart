import 'package:aroll_mobile/presentation/shared/shift_history_grouping.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shift history same-day grouping', () {
    test('single shift per date stays single', () {
      final entries = buildEmployeeShiftHistoryEntries(
        items: [
          _Item(DateTime(2026, 9, 23), 'Morning', '08:00', 100),
          _Item(DateTime(2026, 9, 24), 'Morning', '08:00', 100),
        ],
        dateOf: (e) => e.date,
        shiftName: (e) => e.name,
        scheduledStart: (e) => e.start,
      );
      expect(entries.length, 2);
      expect(entries[0], isA<_Item>());
      expect(entries[1], isA<_Item>());
    });

    test('two same-day shifts group together', () {
      final entries = buildEmployeeShiftHistoryEntries(
        items: [
          _Item(DateTime(2026, 9, 23), 'Morning', '08:00', 250),
          _Item(DateTime(2026, 9, 23), 'Afternoon', '13:00', 180),
        ],
        dateOf: (e) => e.date,
        shiftName: (e) => e.name,
        scheduledStart: (e) => e.start,
      );
      expect(entries.length, 1);
      expect(entries.first, isA<List<_Item>>());
      final multi = entries.first as List<_Item>;
      expect(multi.length, 2);
      expect(multi.first.name, 'Morning');
      expect(multi.last.name, 'Afternoon');
    });

    test('different work dates are not combined', () {
      final entries = buildEmployeeShiftHistoryEntries(
        items: [
          _Item(DateTime(2026, 9, 23), 'Morning', '08:00', 100),
          _Item(DateTime(2026, 9, 24), 'Morning', '08:00', 200),
        ],
        dateOf: (e) => e.date,
        shiftName: (e) => e.name,
        scheduledStart: (e) => e.start,
      );
      expect(entries.length, 2);
      expect(entries.every((e) => e is _Item), isTrue);
    });

    test('owner day blocks group by employee_id', () {
      final blocks = buildOwnerDayBlocks(
        rows: [
          {
            'employee_id': 'a',
            'employee_name': 'Ada',
            'shift_name': 'Morning',
            'scheduled_start': '08:00',
            'shift_net': 100,
          },
          {
            'employee_id': 'a',
            'employee_name': 'Ada',
            'shift_name': 'Afternoon',
            'scheduled_start': '13:00',
            'shift_net': 200,
          },
          {
            'employee_id': 'b',
            'employee_name': 'Bea',
            'shift_name': 'Morning',
            'scheduled_start': '08:00',
            'shift_net': 50,
          },
        ],
      );
      expect(blocks.length, 2);
      expect(blocks.first, isA<List<Map<String, dynamic>>>());
      expect(blocks.last, isA<Map<String, dynamic>>());
      expect(shiftIndexLabel(0, 'Morning'), 'Shift 1 — Morning');
    });
  });

  group('FINAL SHIFT NET from shift_net', () {
    test('Drew pattern: OT on second shift uses shift_net not earned', () {
      final sum = sumAuthoritativeShiftNet([
        (shiftNet: 659.23, historicalRateRequired: false),
        (shiftNet: 240.67, historicalRateRequired: false),
      ]);
      expect(sum.unresolved, isFalse);
      expect(sum.total, closeTo(899.90, 0.001));
      expect(sum.parts, [659.23, 240.67]);
      // Must not equal sum of earned (659.23 + 233.33).
      expect(sum.total, isNot(closeTo(892.56, 0.001)));
    });

    test('two shifts no overtime sums shift_net', () {
      final sum = sumAuthoritativeShiftNet([
        (shiftNet: 400.0, historicalRateRequired: false),
        (shiftNet: 250.0, historicalRateRequired: false),
      ]);
      expect(sum.total, 650.0);
      expect(sum.parts, [400.0, 250.0]);
    });

    test('OT on first shift included via shift_net', () {
      final sum = sumAuthoritativeShiftNet([
        (shiftNet: 240.67, historicalRateRequired: false),
        (shiftNet: 659.23, historicalRateRequired: false),
      ]);
      expect(sum.total, closeTo(899.90, 0.001));
    });

    test('missing shift_net makes FINAL unavailable not zero or earned', () {
      final sum = sumAuthoritativeShiftNet([
        (shiftNet: 659.23, historicalRateRequired: false),
        (shiftNet: null, historicalRateRequired: false),
      ]);
      expect(sum.unresolved, isFalse);
      expect(sum.total, isNull);
      expect(sum.parts, isEmpty);
      expect(sum.total, isNot(0));
    });

    test('non-numeric shift_net from maps is unavailable', () {
      final sum = sumAuthoritativeShiftNetFromMaps([
        {'shift_net': 100.0},
        {'shift_net': 'not-a-number'},
      ]);
      expect(sum.total, isNull);
      expect(sum.parts, isEmpty);
      expect(asFiniteShiftNet('12.5'), isNull);
      expect(asFiniteShiftNet(double.nan), isNull);
      expect(asFiniteShiftNet(double.infinity), isNull);
    });

    test('Daily-style shift_net totals still sum authoritatively', () {
      // Daily entitlement path may differ from earned; FINAL uses shift_net.
      final sum = sumAuthoritativeShiftNet([
        (shiftNet: 307.73, historicalRateRequired: false),
        (shiftNet: 100.0, historicalRateRequired: false),
      ]);
      expect(sum.total, closeTo(407.73, 0.001));
    });

    test('historical rate required stays unresolved', () {
      final sum = sumAuthoritativeShiftNet([
        (shiftNet: 250.0, historicalRateRequired: false),
        (shiftNet: null, historicalRateRequired: true),
      ]);
      expect(sum.unresolved, isTrue);
      expect(sum.total, isNull);
    });
  });

  group('pay component lines from authoritative fields', () {
    test('no additional pay / no deductions when zeros or null', () {
      expect(
        buildAdditionalPayLines(overtimePay: 0, restDayPremiumPay: null),
        isEmpty,
      );
      expect(
        buildDeductionLines(lateDeduction: 0, undertimeDeduction: null),
        isEmpty,
      );
    });

    test('overtime pay visible', () {
      final lines = buildAdditionalPayLines(
        overtimePay: 75,
        overtimeMinutes: 30,
      );
      expect(lines.length, 1);
      expect(lines.first.key, 'overtime');
      expect(lines.first.label, contains('30'));
      expect(lines.first.amount, 75);
    });

    test('rest-day premium visible', () {
      final lines = buildAdditionalPayLines(restDayPremiumPay: 120);
      expect(lines.single.key, 'rest_day');
      expect(lines.single.amount, 120);
    });

    test('holiday pay not invented without amount field', () {
      expect(buildAdditionalPayLines(), isEmpty);
    });

    test('late and undertime deductions visible', () {
      final lines = buildDeductionLines(
        lateDeduction: 20,
        lateMinutes: 5,
        undertimeDeduction: 50,
        undertimeMinutes: 10,
      );
      expect(lines.map((l) => l.key).toList(), ['late', 'undertime']);
      expect(lines[0].amount, 20);
      expect(lines[1].amount, 50);
    });

    test('multiple positive components', () {
      final lines = buildAdditionalPayLines(
        overtimePay: 75,
        overtimeMinutes: 20,
        restDayPremiumPay: 100,
      );
      expect(lines.length, 2);
      expect(lines.map((l) => l.key).toList(), ['overtime', 'rest_day']);
    });

    test('null components omitted', () {
      expect(buildAdditionalPayLines(overtimePay: null), isEmpty);
      expect(buildDeductionLines(lateDeduction: null), isEmpty);
    });

    test('does not emit aggregate shift_deductions double-count line', () {
      final lines = buildDeductionLines(
        lateDeduction: 10,
        undertimeDeduction: 5,
      );
      expect(lines.every((l) => l.key != 'shift_deductions'), isTrue);
      expect(lines.length, 2);
    });
  });

  group('employee-facing shift pay', () {
    String money(double value) => value.toStringAsFixed(2);

    test('Kane mixed daily and hourly', () {
      final daily = {
        'pay_basis_used': 'daily',
        'status': 'present',
        'expected_salary_pay': 350.0,
        'earned': 200.0,
        'holiday_pay': 0.0,
        'day_holiday_pay': 350.0,
        'shift_net': 350.0,
        'reconciled_shift_total': 350.0,
        'holiday_included_in_shift_net': false,
        'reconciled_day_total': 1000.0,
      };
      final hourly = {
        'pay_basis_used': 'hourly',
        'status': 'present',
        'expected_salary_pay': 150.0,
        'earned': 150.0,
        'holiday_pay': 150.0,
        'day_holiday_pay': 350.0,
        'shift_net': 150.0,
        'reconciled_shift_total': 300.0,
        'holiday_included_in_shift_net': false,
        'reconciled_day_total': 1000.0,
      };
      final siblings = [daily, hourly];
      final dailyFace = presentShiftPayFromMap(daily, siblings);
      final hourlyFace = presentShiftPayFromMap(hourly, siblings);
      expect(dailyFace.earned, 350);
      expect(dailyFace.holidayPay, 350);
      expect(dailyFace.shiftTotal, 700);
      expect(hourlyFace.earned, 150);
      expect(hourlyFace.holidayPay, 150);
      expect(hourlyFace.shiftTotal, 300);
      expect(
        historyDayEquationFromMaps(siblings, 1000, money),
        '700.00 + 300.00 = 1000.00',
      );
      final day = historyDayTotalFromMaps(siblings);
      expect(day.total, 1000);
    });

    test('Kim hourly holiday stays on each shift', () {
      final first = {
        'pay_basis_used': 'hourly',
        'status': 'present',
        'earned': 200.0,
        'holiday_pay': 200.0,
        'day_holiday_pay': 0.0,
        'shift_net': 200.0,
        'reconciled_shift_total': 400.0,
        'holiday_included_in_shift_net': false,
        'reconciled_day_total': 700.0,
      };
      final second = {
        'pay_basis_used': 'hourly',
        'status': 'present',
        'earned': 150.0,
        'holiday_pay': 150.0,
        'day_holiday_pay': 0.0,
        'shift_net': 150.0,
        'reconciled_shift_total': 300.0,
        'holiday_included_in_shift_net': false,
        'reconciled_day_total': 700.0,
      };
      final siblings = [first, second];
      expect(presentShiftPayFromMap(first, siblings).shiftTotal, 400);
      expect(presentShiftPayFromMap(second, siblings).shiftTotal, 300);
      expect(historyDayTotalFromMaps(siblings).total, 700);
      expect(
        historyDayEquationFromMaps(siblings, 700, money),
        '400.00 + 300.00 = 700.00',
      );
    });

    test('Ali two daily stamps do not duplicate the entitlement', () {
      final row = {
        'pay_basis_used': 'daily',
        'status': 'present',
        'expected_salary_pay': 350.0,
        'earned': 200.0,
        'holiday_pay': 0.0,
        'day_holiday_pay': 350.0,
        'day_entitlement': 350.0,
        'shift_net': 350.0,
        'reconciled_shift_total': 350.0,
        'holiday_included_in_shift_net': false,
        'late_deduction': 0.0,
        'reconciled_day_total': 700.0,
      };
      final siblings = [row, Map<String, dynamic>.from(row)];
      final face = presentShiftPayFromMap(siblings.first, siblings);
      expect(face.showEarned, isFalse);
      expect(face.holidayPay, isNull);
      expect(face.hideShiftTotal, isTrue);
      expect(face.shiftTotal, isNull);
      expect(historyDayTotalFromMaps(siblings).total, 700);
      expect(historyDayEquationFromMaps(siblings, 700, money), isNull);
      final added = dateLevelAdditionalPayFromMaps(siblings);
      expect(added.map((line) => line.key).toList(), ['holiday']);
      expect(added.single.amount, 350);
    });

    test('Bianca unworked holiday is not doubled', () {
      final first = {
        'pay_basis_used': 'hourly',
        'status': 'absent',
        'earned': 150.0,
        'holiday_pay': 150.0,
        'day_holiday_pay': 0.0,
        'shift_net': 150.0,
        'reconciled_shift_total': 150.0,
        'holiday_included_in_shift_net': true,
        'reconciled_day_total': 262.50,
      };
      final second = {
        'pay_basis_used': 'hourly',
        'status': 'absent',
        'earned': 112.50,
        'holiday_pay': 112.50,
        'day_holiday_pay': 0.0,
        'shift_net': 112.50,
        'reconciled_shift_total': 112.50,
        'holiday_included_in_shift_net': true,
        'reconciled_day_total': 262.50,
      };
      final siblings = [first, second];
      final firstFace = presentShiftPayFromMap(first, siblings);
      final secondFace = presentShiftPayFromMap(second, siblings);
      expect(firstFace.earned, isNull);
      expect(firstFace.showEarned, isFalse);
      expect(firstFace.holidayPay, 150);
      expect(firstFace.shiftTotal, 150);
      expect(secondFace.earned, isNull);
      expect(secondFace.holidayPay, 112.50);
      expect(secondFace.shiftTotal, 112.50);
      expect(historyDayTotalFromMaps(siblings).total, 262.50);
      expect(
        historyDayEquationFromMaps(siblings, 262.50, money),
        '150.00 + 112.50 = 262.50',
      );
    });

    test('Aina paid leave does not gain holiday pay', () {
      final row = {
        'pay_basis_used': 'hourly',
        'status': 'on_leave',
        'earned': 200.0,
        'holiday_pay': 0.0,
        'day_holiday_pay': 200.0,
        'shift_net': 200.0,
        'reconciled_shift_total': 200.0,
        'holiday_included_in_shift_net': false,
      };
      final face = presentShiftPayFromMap(row, [row]);
      expect(face.earned, 200);
      expect(face.holidayPay, isNull);
      expect(face.shiftTotal, 200);
    });

    test('Drew unpaid leave stays zero', () {
      final row = {
        'pay_basis_used': 'hourly',
        'status': 'on_leave',
        'earned': 0.0,
        'holiday_pay': 0.0,
        'day_holiday_pay': 0.0,
        'shift_net': 0.0,
        'reconciled_shift_total': 0.0,
        'holiday_included_in_shift_net': false,
      };
      final face = presentShiftPayFromMap(row, [row]);
      expect(face.earned, 0);
      expect(face.holidayPay, isNull);
      expect(face.shiftTotal, 0);
    });

    test('overtime and rest premium stay inside the existing shift total', () {
      final overtime = {
        'pay_basis_used': 'hourly',
        'status': 'present',
        'earned': 200.0,
        'overtime_pay': 50.0,
        'holiday_pay': 0.0,
        'shift_net': 250.0,
        'reconciled_shift_total': 250.0,
        'holiday_included_in_shift_net': false,
      };
      final rest = {
        'pay_basis_used': 'hourly',
        'status': 'present',
        'earned': 200.0,
        'rest_day_premium_pay': 120.0,
        'holiday_pay': 0.0,
        'shift_net': 320.0,
        'reconciled_shift_total': 320.0,
        'holiday_included_in_shift_net': false,
      };
      expect(presentShiftPayFromMap(overtime, [overtime]).shiftTotal, 250);
      expect(presentShiftPayFromMap(rest, [rest]).shiftTotal, 320);
    });

    test('old snapshot without stamp fields keeps earned and shift net', () {
      final row = {
        'earned': 200.0,
        'shift_net': 200.0,
      };
      final face = presentShiftPayFromMap(row, [row]);
      expect(face.earned, 200);
      expect(face.holidayPay, isNull);
      expect(face.shiftTotal, 200);
      expect(face.hideShiftTotal, isFalse);
    });

    test('unworked holiday status and rate stay on the frozen row', () {
      final bianca = {
        'status': 'holiday_paid',
        'pay_basis_used': 'hourly',
        'rate_used': 75.0,
        'earned': 150.0,
        'holiday_pay': 150.0,
        'shift_net': 150.0,
        'holiday_included_in_shift_net': true,
        'reconciled_shift_total': 150.0,
      };
      expect(
        shiftHistoryStatusLabelFromMap(bianca),
        'Paid Holiday — Not Worked',
      );
      final face = presentShiftPayFromMap(bianca, [bianca]);
      expect(face.showEarned, isFalse);
      expect(face.holidayPay, 150);
      expect(face.shiftTotal, 150);
      expect(face.shiftTotal, isNot(300));

      final daily = {
        'status': 'holiday_paid',
        'pay_basis_used': 'daily',
        'rate_used': 350.0,
        'earned': 350.0,
        'holiday_pay': 350.0,
        'shift_net': 350.0,
        'holiday_included_in_shift_net': true,
        'reconciled_shift_total': 350.0,
      };
      final dailyFace = presentShiftPayFromMap(daily, [daily]);
      expect(dailyFace.holidayPay, 350);
      expect(dailyFace.shiftTotal, 350);
      expect(dailyFace.showEarned, isFalse);

      final worked = {
        'status': 'complete',
        'pay_basis_used': 'hourly',
        'rate_used': 100.0,
        'earned': 150.0,
        'holiday_pay': 150.0,
        'shift_net': 150.0,
        'reconciled_shift_total': 300.0,
        'holiday_included_in_shift_net': false,
      };
      final workedFace = presentShiftPayFromMap(worked, [worked]);
      expect(workedFace.earned, 150);
      expect(workedFace.holidayPay, 150);
      expect(workedFace.shiftTotal, 300);
      expect(shiftHistoryStatusLabelFromMap(worked), 'Present');

      expect(
        shiftHistoryStatusLabelFromMap({
          'status': 'on_leave',
          'earned': 200.0,
          'shift_net': 200.0,
          'holiday_pay': 0.0,
        }),
        'Paid Leave',
      );
      expect(
        shiftHistoryStatusLabelFromMap({
          'status': 'on_leave',
          'earned': 0.0,
          'shift_net': 0.0,
          'holiday_pay': 0.0,
        }),
        'Unpaid Leave',
      );

      final frozen = {
        'status': 'holiday_paid',
        'pay_basis_used': 'hourly',
        'rate_used': 75.0,
        'shift_net': 150.0,
        'holiday_included_in_shift_net': true,
      };
      expect(frozen['rate_used'], 75);
      expect(frozen['pay_basis_used'], 'hourly');
      final missing = {'status': 'holiday_paid', 'shift_net': 150.0};
      expect(missing['rate_used'], isNull);
      expect(missing['pay_basis_used'], isNull);
    });
  });

  group('two daily shifts date-level additional pay', () {
    Map<String, dynamic> daily({
      double dayRest = 0,
      double dayHoliday = 0,
      double late = 0,
      double undertime = 0,
      double overtime = 0,
    }) {
      return {
        'pay_basis_used': 'daily',
        'status': 'present',
        'expected_salary_pay': 350.0,
        'earned': 218.75,
        'rest_day_premium_pay': null,
        'holiday_pay': 0.0,
        'day_rest_day_pay': dayRest,
        'day_holiday_pay': dayHoliday,
        'late_deduction': late,
        'undertime_deduction': undertime,
        'overtime_pay': overtime,
        'shift_net': 350.0,
        'reconciled_shift_total': 350.0,
        'holiday_included_in_shift_net': false,
        'reconciled_day_total': 455.0,
      };
    }

    test('A normal day has no additional pay lines', () {
      final siblings = [daily(), daily()];
      expect(dateLevelAdditionalPayFromMaps(siblings), isEmpty);
      expect(presentShiftPayFromMap(siblings[0], siblings).showEarned, isFalse);
      expect(presentShiftPayFromMap(siblings[1], siblings).showEarned, isFalse);
      expect(historyDayTotalFromMaps(siblings).total, 455);
    });

    test('B rest premium appears once and day total stays canonical', () {
      final siblings = [
        daily(dayRest: 105)..['reconciled_day_total'] = 455.0,
        daily(dayRest: 105)..['reconciled_day_total'] = 455.0,
      ];
      final lines = dateLevelAdditionalPayFromMaps(siblings);
      expect(lines.length, 1);
      expect(lines.single.label, 'Rest-Day Premium');
      expect(lines.single.amount, 105);
      expect(presentShiftPayFromMap(siblings[0], siblings).restPay, isNull);
      expect(presentShiftPayFromMap(siblings[1], siblings).restPay, isNull);
      expect(historyDayTotalFromMaps(siblings).total, 455);
      expect(historyDayEquationFromMaps(siblings, 455, (v) => '$v'), isNull);
    });

    test('C holiday premium appears once and not on both shifts', () {
      final siblings = [
        daily(dayHoliday: 350)..['reconciled_day_total'] = 700.0,
        daily(dayHoliday: 350)..['reconciled_day_total'] = 700.0,
      ];
      final lines = dateLevelAdditionalPayFromMaps(siblings);
      expect(lines.map((line) => line.key).toList(), ['holiday']);
      expect(lines.single.amount, 350);
      expect(presentShiftPayFromMap(siblings[0], siblings).holidayPay, isNull);
      expect(presentShiftPayFromMap(siblings[1], siblings).holidayPay, isNull);
      expect(historyDayTotalFromMaps(siblings).total, 700);
    });

    test('D rest and holiday each appear once', () {
      final siblings = [
        daily(dayRest: 105, dayHoliday: 350)..['reconciled_day_total'] = 805.0,
        daily(dayRest: 105, dayHoliday: 350)..['reconciled_day_total'] = 805.0,
      ];
      final lines = dateLevelAdditionalPayFromMaps(siblings);
      expect(lines.map((line) => line.label).toList(), [
        'Rest-Day Premium',
        'Holiday Premium',
      ]);
      expect(lines.map((line) => line.amount).toList(), [105, 350]);
      expect(historyDayTotalFromMaps(siblings).total, 805);
      expect(
        historyDayTotalFromMaps(siblings).total,
        isNot(805 + 105 + 350),
      );
    });

    test('E deductions stay on the shift and additional pay stays on the date', () {
      final first = daily(dayRest: 105, late: 20)..['reconciled_day_total'] = 435.0;
      final second = daily(dayRest: 105, undertime: 30)
        ..['reconciled_day_total'] = 435.0;
      final siblings = [first, second];
      final lines = dateLevelAdditionalPayFromMaps(siblings);
      expect(lines.single.key, 'rest_day');
      expect(lines.single.amount, 105);
      final firstDeductions = buildDeductionLines(lateDeduction: first['late_deduction']);
      final secondDeductions = buildDeductionLines(
        undertimeDeduction: second['undertime_deduction'],
      );
      expect(firstDeductions.single.key, 'late');
      expect(secondDeductions.single.key, 'undertime');
      expect(presentShiftPayFromMap(first, siblings).restPay, isNull);
      expect(historyDayTotalFromMaps(siblings).total, 435);
    });

    test('F mixed hourly and daily keeps row premiums and no date section', () {
      final hourly = {
        'pay_basis_used': 'hourly',
        'status': 'present',
        'expected_salary_pay': 250.0,
        'earned': 250.0,
        'rest_day_premium_pay': 75.0,
        'holiday_pay': 0.0,
        'day_rest_day_pay': 105.0,
        'shift_net': 325.0,
        'reconciled_shift_total': 325.0,
        'reconciled_day_total': 780.0,
      };
      final dailyShift = {
        'pay_basis_used': 'daily',
        'status': 'present',
        'expected_salary_pay': 350.0,
        'earned': 131.25,
        'rest_day_premium_pay': null,
        'day_rest_day_pay': 105.0,
        'day_holiday_pay': 0.0,
        'shift_net': 350.0,
        'reconciled_shift_total': 350.0,
        'reconciled_day_total': 780.0,
      };
      final siblings = [hourly, dailyShift];
      expect(dateLevelAdditionalPayFromMaps(siblings), isEmpty);
      expect(presentShiftPayFromMap(hourly, siblings).restPay, 75);
      expect(presentShiftPayFromMap(dailyShift, siblings).restPay, 105);
      expect(presentShiftPayFromMap(dailyShift, siblings).shiftTotal, 455);
      expect(historyDayTotalFromMaps(siblings).total, 780);
    });

    test('G single daily keeps the premium on the shift', () {
      final row = daily(dayRest: 105)..['reconciled_day_total'] = 455.0;
      expect(dateLevelAdditionalPayFromMaps([row]), isEmpty);
      final face = presentShiftPayFromMap(row, [row]);
      expect(face.restPay, 105);
      expect(face.baseLabel, 'Daily Entitlement');
      expect(face.earned, 350);
      expect(historyDayTotalFromMaps([row]).total, 455);
    });

    test('H hourly plus hourly keeps each row premium', () {
      final first = {
        'pay_basis_used': 'hourly',
        'status': 'present',
        'expected_salary_pay': 250.0,
        'earned': 250.0,
        'rest_day_premium_pay': 75.0,
        'day_rest_day_pay': 0.0,
        'shift_net': 325.0,
        'reconciled_shift_total': 325.0,
        'reconciled_day_total': 520.0,
      };
      final second = {
        'pay_basis_used': 'hourly',
        'status': 'present',
        'expected_salary_pay': 150.0,
        'earned': 150.0,
        'rest_day_premium_pay': 45.0,
        'day_rest_day_pay': 0.0,
        'shift_net': 195.0,
        'reconciled_shift_total': 195.0,
        'reconciled_day_total': 520.0,
      };
      final siblings = [first, second];
      expect(dateLevelAdditionalPayFromMaps(siblings), isEmpty);
      expect(presentShiftPayFromMap(first, siblings).restPay, 75);
      expect(presentShiftPayFromMap(second, siblings).restPay, 45);
      expect(historyDayTotalFromMaps(siblings).total, 520);
    });
  });

  group('late overtime and rest-day summary lines', () {
    Map<String, dynamic> daily({
      double late = 0,
      double lateMinutes = 0,
      double overtime = 0,
      double overtimeMinutes = 0,
      double dayRest = 0,
      double shiftNet = 350,
    }) {
      return {
        'pay_basis_used': 'daily',
        'status': late > 0 ? 'late' : 'complete',
        'expected_salary_pay': 350.0,
        'earned': 315.99,
        'rest_day_premium_pay': null,
        'holiday_pay': 0.0,
        'day_rest_day_pay': dayRest,
        'late_deduction': late,
        'late_minutes': lateMinutes,
        'overtime_pay': overtime,
        'overtime_minutes': overtimeMinutes,
        'shift_net': shiftNet,
        'reconciled_shift_total': shiftNet,
      };
    }

    test('late only', () {
      final row = daily(late: 20, lateMinutes: 20, shiftNet: 330);
      expect(buildDeductionLines(lateDeduction: row['late_deduction'], lateMinutes: row['late_minutes']).single.key, 'late');
      expect(buildAdditionalPayLines(overtimePay: row['overtime_pay']), isEmpty);
    });

    test('overtime only', () {
      final row = daily(overtime: 60, overtimeMinutes: 60, shiftNet: 410);
      expect(buildAdditionalPayLines(overtimePay: row['overtime_pay'], overtimeMinutes: row['overtime_minutes']).single.key, 'overtime');
      expect(buildDeductionLines(lateDeduction: row['late_deduction']), isEmpty);
    });

    test('late and overtime together', () {
      final row = daily(late: 20, lateMinutes: 20, overtime: 60, overtimeMinutes: 60, shiftNet: 390);
      expect(buildAdditionalPayLines(overtimePay: row['overtime_pay']).single.key, 'overtime');
      expect(buildDeductionLines(lateDeduction: row['late_deduction']).single.key, 'late');
    });

    test('rest-day premium only', () {
      final row = daily(dayRest: 35);
      final face = presentShiftPayFromMap(row, [row]);
      expect(face.restPay, 35);
      expect(face.shiftTotal, 385);
      expect(buildAdditionalPayLines(restDayPremiumPay: face.restPay).single.key, 'rest_day');
    });

    test('late overtime and rest-day coexist without duplicating rest', () {
      final row = daily(
        late: 20,
        lateMinutes: 20,
        overtime: 60,
        overtimeMinutes: 60,
        dayRest: 35,
        shiftNet: 390,
      );
      final face = presentShiftPayFromMap(row, [row]);
      final additional = buildAdditionalPayLines(
        overtimePay: row['overtime_pay'],
        restDayPremiumPay: face.restPay,
      );
      expect(additional.map((l) => l.key).toList(), ['overtime', 'rest_day']);
      expect(additional.where((l) => l.key == 'rest_day').length, 1);
      expect(buildDeductionLines(lateDeduction: row['late_deduction']).single.amount, 20);
      expect(face.restPay, 35);
      expect(face.shiftTotal, 425);
    });

    test('grace period omits late line', () {
      expect(
        buildDeductionLines(lateDeduction: 0, lateMinutes: 0),
        isEmpty,
      );
    });

    test('ineligible overtime omits overtime line', () {
      expect(buildAdditionalPayLines(overtimePay: 0, overtimeMinutes: 0), isEmpty);
    });

    test('rest-day premium amount is unchanged when late and overtime exist', () {
      final restOnly = presentShiftPayFromMap(daily(dayRest: 35), [daily(dayRest: 35)]);
      final mixed = presentShiftPayFromMap(
        daily(late: 20, overtime: 60, dayRest: 35, shiftNet: 390),
        [daily(late: 20, overtime: 60, dayRest: 35, shiftNet: 390)],
      );
      expect(restOnly.restPay, 35);
      expect(mixed.restPay, 35);
    });

    test('shift total matches entitlement plus extras minus deductions', () {
      final row = daily(
        late: 20,
        overtime: 60,
        dayRest: 35,
        shiftNet: 390,
      );
      final face = presentShiftPayFromMap(row, [row]);
      expect(face.shiftTotal, 350 + 60 + 35 - 20);
    });
  });
}

class _Item {
  _Item(this.date, this.name, this.start, this.earned);
  final DateTime date;
  final String name;
  final String start;
  final double earned;
}
