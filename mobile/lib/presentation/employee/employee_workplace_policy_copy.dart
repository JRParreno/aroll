import 'package:aroll_mobile/core/utils/format.dart';
import 'package:aroll_mobile/domain/entities/employee_workplace_policies.dart';

const workplacePolicyUnavailable = 'Not configured';
const workplacePolicyNotApplicable = 'Not applicable';

String workplacePolicyMinutes(int? value) {
  if (value == null) return workplacePolicyUnavailable;
  return value == 1 ? '1 minute' : '$value minutes';
}

String workplacePolicyPercent(num? value) {
  if (value == null) return workplacePolicyUnavailable;
  final shown = value.truncateToDouble() == value.toDouble()
      ? '${value.toInt()}'
      : value.toString()
          .replaceFirst(RegExp(r'\.?0+$'), '');
  return '$shown%';
}

String workplacePolicyMoney(num? value) {
  if (value == null) return workplacePolicyUnavailable;
  return formatPeso(value);
}

String workplacePolicyYesNo(bool value) => value ? 'Yes' : 'No';

String missingClockOutLabel(String? policy) {
  return switch (policy) {
    'auto_clock_out' => 'The system closes an open time-in at the cutoff.',
    'require_manager_approval' =>
      'A manager must review a missing time-out before it is completed.',
    null => workplacePolicyUnavailable,
    _ => workplacePolicyUnavailable,
  };
}

String overtimeMethodLabel(String? method) {
  return switch (method) {
    'flat_per_minute' => 'A saved peso amount for each qualifying overtime minute',
    'hourly_statutory' =>
      'Hourly-based overtime using your hourly rate, or your daily rate divided by that shift’s scheduled hours',
    null => workplacePolicyUnavailable,
    _ => workplacePolicyUnavailable,
  };
}

String employeePayRateSummary(EmployeePayPolicyView pay) {
  final basis = pay.payBasis;
  if (basis == 'hourly') {
    return pay.hourlyRate == null
        ? workplacePolicyUnavailable
        : '${workplacePolicyMoney(pay.hourlyRate)} per hour';
  }
  if (basis == 'monthly') {
    return pay.monthlySalary == null
        ? workplacePolicyUnavailable
        : '${workplacePolicyMoney(pay.monthlySalary)} per month';
  }
  if (basis == 'daily') {
    return pay.dailyRate == null
        ? workplacePolicyUnavailable
        : '${workplacePolicyMoney(pay.dailyRate)} per day';
  }
  if (pay.dailyRate != null) {
    return '${workplacePolicyMoney(pay.dailyRate)} per day';
  }
  if (pay.hourlyRate != null) {
    return '${workplacePolicyMoney(pay.hourlyRate)} per hour';
  }
  if (pay.monthlySalary != null) {
    return '${workplacePolicyMoney(pay.monthlySalary)} per month';
  }
  return workplacePolicyUnavailable;
}
