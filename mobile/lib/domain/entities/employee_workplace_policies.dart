import 'package:equatable/equatable.dart';

class EmployeeWorkplacePolicies extends Equatable {
  const EmployeeWorkplacePolicies({
    required this.businessName,
    required this.attendance,
    required this.payroll,
    required this.restDay,
    required this.yourPay,
  });

  final String businessName;
  final EmployeeAttendancePolicyView? attendance;
  final EmployeePayrollPolicyView? payroll;
  final EmployeeRestDayPolicyView? restDay;
  final EmployeePayPolicyView yourPay;

  factory EmployeeWorkplacePolicies.fromJson(Map<String, dynamic> json) {
    return EmployeeWorkplacePolicies(
      businessName: '${json['business_name'] ?? ''}',
      attendance: json['attendance'] is Map
          ? EmployeeAttendancePolicyView.fromJson(
              Map<String, dynamic>.from(json['attendance'] as Map),
            )
          : null,
      payroll: json['payroll'] is Map
          ? EmployeePayrollPolicyView.fromJson(
              Map<String, dynamic>.from(json['payroll'] as Map),
            )
          : null,
      restDay: json['rest_day'] is Map
          ? EmployeeRestDayPolicyView.fromJson(
              Map<String, dynamic>.from(json['rest_day'] as Map),
            )
          : null,
      yourPay: EmployeePayPolicyView.fromJson(
        json['your_pay'] is Map
            ? Map<String, dynamic>.from(json['your_pay'] as Map)
            : const {},
      ),
    );
  }

  @override
  List<Object?> get props => [businessName, attendance, payroll, restDay, yourPay];
}

class EmployeeAttendancePolicyView extends Equatable {
  const EmployeeAttendancePolicyView({
    required this.earlyClockInMinutes,
    required this.onTimeGraceMinutes,
    required this.halfDayThresholdMinutes,
    required this.absentThresholdMinutes,
    required this.absentThresholdPercent,
    required this.halfDayThresholdPercent,
    required this.earlyOutDeductionEnabled,
    required this.earlyOutDeductionPerMinute,
    required this.overtimeMinimumMinutes,
    required this.maximumOvertimeMinutes,
    required this.missingClockOutPolicy,
    required this.attendanceBasedSalaryEnabled,
    required this.breaktimeIsPaid,
  });

  final int? earlyClockInMinutes;
  final int? onTimeGraceMinutes;
  final int? halfDayThresholdMinutes;
  final int? absentThresholdMinutes;
  final int? absentThresholdPercent;
  final int? halfDayThresholdPercent;
  final bool earlyOutDeductionEnabled;
  final double? earlyOutDeductionPerMinute;
  final int? overtimeMinimumMinutes;
  final int? maximumOvertimeMinutes;
  final String? missingClockOutPolicy;
  final bool attendanceBasedSalaryEnabled;
  final bool breaktimeIsPaid;

  factory EmployeeAttendancePolicyView.fromJson(Map<String, dynamic> json) {
    return EmployeeAttendancePolicyView(
      earlyClockInMinutes: _int(json['early_clock_in_minutes']),
      onTimeGraceMinutes: _int(json['on_time_grace_minutes']),
      halfDayThresholdMinutes: _int(json['half_day_threshold_minutes']),
      absentThresholdMinutes: _int(json['absent_threshold_minutes']),
      absentThresholdPercent: _int(json['absent_threshold_percent']),
      halfDayThresholdPercent: _int(json['half_day_threshold_percent']),
      earlyOutDeductionEnabled: json['early_out_deduction_enabled'] == true,
      earlyOutDeductionPerMinute: _double(json['early_out_deduction_per_minute']),
      overtimeMinimumMinutes: _int(json['overtime_minimum_minutes']),
      maximumOvertimeMinutes: _int(json['maximum_overtime_minutes']),
      missingClockOutPolicy: json['missing_clock_out_policy'] as String?,
      attendanceBasedSalaryEnabled: json['attendance_based_salary_enabled'] == true,
      breaktimeIsPaid: json['breaktime_is_paid'] == true,
    );
  }

  @override
  List<Object?> get props => [
        earlyClockInMinutes,
        onTimeGraceMinutes,
        halfDayThresholdMinutes,
        absentThresholdMinutes,
        absentThresholdPercent,
        halfDayThresholdPercent,
        earlyOutDeductionEnabled,
        earlyOutDeductionPerMinute,
        overtimeMinimumMinutes,
        maximumOvertimeMinutes,
        missingClockOutPolicy,
        attendanceBasedSalaryEnabled,
        breaktimeIsPaid,
      ];
}

class EmployeePayrollPolicyView extends Equatable {
  const EmployeePayrollPolicyView({
    required this.lateDeductionEnabled,
    required this.lateDeductionPerMinute,
    required this.overtimeEnabled,
    required this.overtimeCalculationMethod,
    required this.overtimePerMinute,
    required this.enableLateOvertimeBalancing,
    required this.overtimeApprovalRequired,
  });

  final bool lateDeductionEnabled;
  final double? lateDeductionPerMinute;
  final bool overtimeEnabled;
  final String? overtimeCalculationMethod;
  final double? overtimePerMinute;
  final bool enableLateOvertimeBalancing;
  final bool overtimeApprovalRequired;

  factory EmployeePayrollPolicyView.fromJson(Map<String, dynamic> json) {
    return EmployeePayrollPolicyView(
      lateDeductionEnabled: json['late_deduction_enabled'] == true,
      lateDeductionPerMinute: _double(json['late_deduction_per_minute']),
      overtimeEnabled: json['overtime_enabled'] == true,
      overtimeCalculationMethod: json['overtime_calculation_method'] as String?,
      overtimePerMinute: _double(json['overtime_per_minute']),
      enableLateOvertimeBalancing: json['enable_late_overtime_balancing'] == true,
      overtimeApprovalRequired: json['overtime_approval_required'] == true,
    );
  }

  @override
  List<Object?> get props => [
        lateDeductionEnabled,
        lateDeductionPerMinute,
        overtimeEnabled,
        overtimeCalculationMethod,
        overtimePerMinute,
        enableLateOvertimeBalancing,
        overtimeApprovalRequired,
      ];
}

class EmployeeRestDayPolicyView extends Equatable {
  const EmployeeRestDayPolicyView({required this.restDayPremiumPercent});

  final double? restDayPremiumPercent;

  factory EmployeeRestDayPolicyView.fromJson(Map<String, dynamic> json) {
    return EmployeeRestDayPolicyView(
      restDayPremiumPercent: _double(json['rest_day_premium_percent']),
    );
  }

  @override
  List<Object?> get props => [restDayPremiumPercent];
}

class EmployeePayPolicyView extends Equatable {
  const EmployeePayPolicyView({
    required this.payBasis,
    required this.dailyRate,
    required this.hourlyRate,
    required this.monthlySalary,
  });

  final String? payBasis;
  final double? dailyRate;
  final double? hourlyRate;
  final double? monthlySalary;

  factory EmployeePayPolicyView.fromJson(Map<String, dynamic> json) {
    return EmployeePayPolicyView(
      payBasis: json['pay_basis'] as String?,
      dailyRate: _double(json['daily_rate']),
      hourlyRate: _double(json['hourly_rate']),
      monthlySalary: _double(json['monthly_salary']),
    );
  }

  @override
  List<Object?> get props => [payBasis, dailyRate, hourlyRate, monthlySalary];
}

int? _int(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse('$value');
}

double? _double(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}
