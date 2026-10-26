import 'package:aroll_mobile/presentation/owner/payroll/pay_period_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('previous and next dates sit on the period boundary', () {
    expect(
      previousPeriodAsOf(DateTime(2026, 7, 16)),
      DateTime(2026, 7, 15),
    );
    expect(
      nextPeriodAsOf(DateTime(2026, 7, 15)),
      DateTime(2026, 7, 16),
    );
  });

  test('navigation crosses month and year boundaries', () {
    expect(
      previousPeriodAsOf(DateTime(2026, 1, 1)),
      DateTime(2025, 12, 31),
    );
    expect(
      nextPeriodAsOf(DateTime(2026, 12, 31)),
      DateTime(2027, 1, 1),
    );
    expect(
      nextPeriodAsOf(DateTime(2024, 2, 28)),
      DateTime(2024, 2, 29),
    );
  });

  test('parses an API period date and ignores a missing value', () {
    expect(parsePayrollIsoDate('2026-07-16'), DateTime(2026, 7, 16));
    expect(parsePayrollIsoDate('2026-07-16T00:00:00'), DateTime(2026, 7, 16));
    expect(parsePayrollIsoDate(null), isNull);
    expect(parsePayrollIsoDate(''), isNull);
  });

  test('Next stays closed for the current and upcoming periods', () {
    expect(canOpenNextPayPeriod('completed'), isTrue);
    expect(canOpenNextPayPeriod('current'), isFalse);
    expect(canOpenNextPayPeriod('upcoming'), isFalse);
    expect(canOpenNextPayPeriod(null), isFalse);
  });
}
