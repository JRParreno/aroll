import 'package:aroll_mobile/core/utils/format.dart';
import 'package:intl/intl.dart';

/// Formats [value] as Philippine pesos. Delegates to [formatPeso].
String ownerPayrollMoney(num value) => formatPeso(value);

/// Salary rate from pay_basis (+ rates). Delegates to [formatSalaryRate].
String ownerSalaryRate(Map<String, dynamic>? payload) {
  if (payload == null) return 'Not set';
  return formatSalaryRate(
    payBasis: '${payload['pay_basis'] ?? 'daily'}',
    dailyRate: _optionalRate(payload['daily_rate']),
    hourlyRate: _optionalRate(
      payload['hourly_rate'] ?? payload['hourly_rate_configured'],
    ),
    monthlySalary: _optionalRate(
      payload['monthly_salary'] ?? payload['monthly_salary_configured'],
    ),
  );
}

num? _optionalRate(Object? value) {
  if (value == null) return null;
  final amount = parsePayrollAmount(value);
  return amount > 0 ? amount : null;
}

String ownerSalaryRateLabel() => salaryRateLabel();

String ownerPayrollShortDate(String? isoDate) {
  if (isoDate == null || isoDate.isEmpty) return '--';
  final parsed = DateTime.tryParse(isoDate);
  if (parsed == null) return isoDate;
  return DateFormat('MMMM d').format(parsed);
}

String ownerPayrollYear(String? isoDate) {
  if (isoDate == null || isoDate.isEmpty) return '--';
  final parsed = DateTime.tryParse(isoDate);
  if (parsed == null) return isoDate;
  return DateFormat('yyyy').format(parsed);
}

String ownerPayrollDisplayDate(String? isoDate) {
  if (isoDate == null || isoDate.isEmpty) return '--';
  final parsed = DateTime.tryParse(isoDate);
  if (parsed == null) return isoDate;
  return DateFormat('MMM d, yyyy').format(parsed);
}

String ownerEmploymentLabel(String? value) {
  if (value == null || value.isEmpty) return 'Employee';
  return ownerStatusLabel(value);
}

String ownerStatusLabel(String? value) {
  if (value == null || value.isEmpty) return '--';
  return value
      .replaceAll('_', ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

double parsePayrollAmount(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) {
    final cleaned = value.replaceAll(RegExp(r'[^0-9.\-]'), '');
    return double.tryParse(cleaned) ?? 0;
  }
  return double.tryParse('$value') ?? 0;
}
