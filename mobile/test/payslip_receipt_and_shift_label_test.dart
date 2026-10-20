import 'dart:io';

import 'package:aroll_mobile/core/utils/format.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/presentation/shared/standard_payslip_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

EmployeePayslip _employeeSlip({
  String payBasis = 'daily',
  double dailyRate = 350,
  double? hourlyRate,
  double restDayPay = 35,
}) {
  return EmployeePayslip(
    businessName: 'Cafe',
    employeeId: 'e1',
    employeeName: 'Sample Emp',
    positionTitle: 'Cashier',
    employmentType: 'full_time',
    periodStart: DateTime(2026, 8, 1),
    periodEnd: DateTime(2026, 8, 15),
    dailyRate: dailyRate,
    payBasis: payBasis,
    hourlyRate: hourlyRate,
    workedDays: 2,
    overtimeHours: 0,
    overtimePay: 0,
    holidayPay: 0,
    restDayPay: restDayPay,
    restDayDays: 1,
    restDayPremiumPercent: 10,
    restDayName: 'sunday',
    restDayRecords: [
      EmployeeRestDayRecord(
        date: DateTime(2026, 8, 2),
        weekday: 'sunday',
        status: 'complete',
        timeIn: DateTime(2026, 8, 2, 18, 0),
        timeOut: DateTime(2026, 8, 2, 22, 0),
        shiftName: 'Evening',
        premiumPercent: 10,
        premiumPay: restDayPay,
      ),
    ],
    deductions: 0,
    absentDays: 0,
    grossPay: 735,
    netPay: 735,
    hoursWorked: 8,
    lateDeductions: 0,
    undertimeDeductions: 0,
    regularPay: 700,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('employee PDF data keeps rest-day pay and drops attendance rows', () {
    final data = StandardPayslipPdfData.fromEmployee(_employeeSlip());
    expect(data.restDayPay.contains('35'), isTrue);
    expect(data.restDayPremiumLabel.contains('Rest Day Premium'), isTrue);
    expect(data.grossPay.contains('735'), isTrue);
  });

  test('owner PDF data also omits rest-day attendance rows', () {
    final data = StandardPayslipPdfData.fromOwnerMap(
      {
        'employee_name': 'Sample Emp',
        'pay_basis': 'daily',
        'daily_rate': 350,
        'hourly_rate': 80,
        'regular_pay': 700,
        'rest_day_pay': 35,
        'rest_day_premium_percent': 10,
        'rest_day_records': [
          {
            'date': '2026-08-02',
            'weekday': 'sunday',
            'time_in': '2026-08-02T10:00:00Z',
            'time_out': '2026-08-02T18:00:00Z',
            'shift_name': 'Evening',
            'premium_pay': 35,
          },
        ],
        'gross_pay': 735,
        'net_pay': 735,
        'period_start': '2026-08-01',
        'period_end': '2026-08-15',
      },
      businessName: 'Cafe',
    );
    expect(data.restDayPay.contains('35'), isTrue);
    expect(data.hourlyRateValue, isEmpty);
    expect(data.dailyRateValue.contains('350'), isTrue);
  });

  test('daily basis fills Daily Rate and leaves Hourly Rate blank', () {
    final rates = payslipRateFieldValues(
      payBasis: 'daily',
      dailyRate: 350,
      hourlyRate: 80,
    );
    expect(rates.daily.contains('350'), isTrue);
    expect(rates.hourly, isEmpty);
    expect(rates.hourly.contains('0.00'), isFalse);
  });

  test('hourly basis fills Hourly Rate and leaves Daily Rate blank', () {
    final rates = payslipRateFieldValues(
      payBasis: 'hourly',
      dailyRate: 650,
      hourlyRate: 100,
    );
    expect(rates.hourly.contains('100'), isTrue);
    expect(rates.daily, isEmpty);
    expect(rates.daily.contains('650'), isFalse);
  });

  test('both stored rates show when basis is not exclusive', () {
    final rates = payslipRateFieldValues(
      payBasis: '',
      dailyRate: 350,
      hourlyRate: 100,
    );
    expect(rates.daily.contains('350'), isTrue);
    expect(rates.hourly.contains('100'), isTrue);
  });

  test('missing rates stay blank', () {
    final rates = payslipRateFieldValues(
      payBasis: 'daily',
      dailyRate: null,
      hourlyRate: null,
    );
    expect(rates.daily, isEmpty);
    expect(rates.hourly, isEmpty);
  });

  test('receipt page is narrower than letter/A4', () {
    expect(payslipReceiptWidthPt, lessThan(400));
    expect(payslipReceiptWidthPt, greaterThan(200));
  });

  test('generated PDF omits rest-day attendance and keeps rest-day pay', () async {
    final data = StandardPayslipPdfData.fromEmployee(_employeeSlip());
    expect(data.restDayPay.contains('35'), isTrue);
    expect(data.dailyRateValue.contains('350'), isTrue);
    expect(data.hourlyRateValue, isEmpty);

    final bytes = await buildStandardPayslipPdfBytes(data);
    expect(bytes.length, greaterThan(200));
    expect(String.fromCharCodes(bytes.take(8)), contains('%PDF'));
    final latin1 = String.fromCharCodes(bytes);
    expect(latin1.contains('Rest Day Work'), isFalse);
    expect(latin1.contains('2026-08-02'), isFalse);
    expect(
      RegExp(r'/MediaBox\s*\[\s*0\s+0\s+612\s+792\s*\]').hasMatch(latin1),
      isFalse,
    );
    final media = RegExp(
      r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]',
    ).firstMatch(latin1);
    expect(media, isNotNull, reason: 'generated PDF must declare a MediaBox');
    final width = double.parse(media!.group(1)!);
    final height = double.parse(media.group(2)!);
    expect(width, closeTo(payslipReceiptWidthPt, 0.5));
    expect(height, greaterThan(300));
    expect(height.isFinite, isTrue);
  });

  test('employee shift history schedule line has no A prefix', () {
    final source = File(
      'lib/presentation/employee/shift_history_screen.dart',
    ).readAsStringSync();
    expect(source.contains('Â·'), isFalse);
    expect(source.contains('Â'), isFalse);
    expect(source.contains(r"${item.shiftName} · $_shiftRange"), isTrue);

    const shiftName = 'Evening';
    const range = '6:30 PM – 10:00 PM';
    final label = '$shiftName · $range';
    expect(label.startsWith('A'), isFalse);
    expect(label.contains('Â'), isFalse);
    expect(label, 'Evening · 6:30 PM – 10:00 PM');
  });
}
