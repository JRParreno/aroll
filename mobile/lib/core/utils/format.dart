import 'package:intl/intl.dart';

/// Canonical PHP peso formatter shared by all screens.
///
/// Uses locale `en_PH` with the `₱` symbol and 2 decimal places so the output
/// is consistent whether shown on employee or owner screens, or embedded in a
/// generated PDF.
String formatPeso(num value) {
  return NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  ).format(value);
}

/// Canonical salary-rate label from employee [payBasis].
///
/// Hourly/monthly ignore [dailyRate] even when present as a legacy fallback.
String formatSalaryRate({
  String? payBasis,
  num? dailyRate,
  num? hourlyRate,
  num? monthlySalary,
}) {
  final basis = (payBasis ?? 'daily').toLowerCase();
  num? amount;
  String unit;
  if (basis == 'hourly') {
    amount = _positiveRate(hourlyRate);
    unit = '/hour';
  } else if (basis == 'monthly') {
    amount = _positiveRate(monthlySalary);
    unit = '/month';
  } else {
    amount = _positiveRate(dailyRate);
    unit = '/day';
  }
  if (amount == null) return 'Not set';
  return '${formatPeso(amount)}$unit';
}

String salaryRateLabel() => 'Salary Rate';

num? _positiveRate(num? value) {
  if (value == null) return null;
  if (value <= 0) return null;
  return value;
}
