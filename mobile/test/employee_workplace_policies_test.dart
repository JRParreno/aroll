import 'package:aroll_mobile/domain/entities/employee_workplace_policies.dart';
import 'package:aroll_mobile/presentation/employee/employee_workplace_policy_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('missing policy rows stay unconfigured instead of inventing values', () {
    final policies = EmployeeWorkplacePolicies.fromJson({
      'business_name': 'Cafe Uno',
      'attendance': null,
      'payroll': null,
      'rest_day': null,
      'your_pay': {'pay_basis': 'daily', 'daily_rate': 580},
    });

    expect(policies.businessName, 'Cafe Uno');
    expect(policies.attendance, isNull);
    expect(policies.payroll, isNull);
    expect(policies.restDay, isNull);
    expect(employeePayRateSummary(policies.yourPay), contains('580'));
  });

  test('configured overtime and late values are shown only when enabled', () {
    final payroll = EmployeePayrollPolicyView.fromJson({
      'late_deduction_enabled': true,
      'late_deduction_per_minute': 2.5,
      'overtime_enabled': false,
      'overtime_calculation_method': null,
      'overtime_per_minute': null,
      'enable_late_overtime_balancing': false,
      'overtime_approval_required': false,
    });

    expect(workplacePolicyMoney(payroll.lateDeductionPerMinute), contains('2.50'));
    expect(payroll.overtimeEnabled, isFalse);
    expect(workplacePolicyMoney(payroll.overtimePerMinute), workplacePolicyUnavailable);
    expect(overtimeMethodLabel(payroll.overtimeCalculationMethod), workplacePolicyUnavailable);
  });

  test('copy helpers stay honest for missing and inapplicable values', () {
    expect(workplacePolicyMinutes(null), workplacePolicyUnavailable);
    expect(workplacePolicyMinutes(1), '1 minute');
    expect(workplacePolicyMinutes(8), '8 minutes');
    expect(workplacePolicyPercent(null), workplacePolicyUnavailable);
    expect(workplacePolicyPercent(35), '35%');
    expect(workplacePolicyPercent(12.5), '12.5%');
    expect(workplacePolicyYesNo(true), 'Yes');
    expect(missingClockOutLabel(null), workplacePolicyUnavailable);
    expect(
      missingClockOutLabel('auto_clock_out'),
      'The system closes an open time-in at the cutoff.',
    );
    expect(
      overtimeMethodLabel('hourly_statutory'),
      contains('Hourly-based overtime'),
    );
    expect(
      employeePayRateSummary(
        const EmployeePayPolicyView(
          payBasis: 'hourly',
          dailyRate: null,
          hourlyRate: null,
          monthlySalary: null,
        ),
      ),
      workplacePolicyUnavailable,
    );
  });
}
