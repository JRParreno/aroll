/// Move the payroll report `as_of` date onto the neighboring configured period.
///
/// The API resolves the period that contains the date. The day before a
/// period starts is the previous period, and the day after it ends is the next.
DateTime previousPeriodAsOf(DateTime periodStart) {
  return DateTime(periodStart.year, periodStart.month, periodStart.day - 1);
}

DateTime nextPeriodAsOf(DateTime periodEnd) {
  return DateTime(periodEnd.year, periodEnd.month, periodEnd.day + 1);
}

DateTime? parsePayrollIsoDate(String? value) {
  if (value == null || value.length < 10) return null;
  final parts = value.substring(0, 10).split('-');
  if (parts.length != 3) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  return DateTime(year, month, day);
}

/// Next is available only for a period that has already ended.
bool canOpenNextPayPeriod(String? payrollStatus) =>
    payrollStatus == 'completed';
