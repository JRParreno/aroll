import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/theme/business_brand_theme.dart';
import 'package:aroll_mobile/domain/entities/employee_workplace_policies.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:aroll_mobile/presentation/employee/employee_workplace_policy_copy.dart';
import 'package:flutter/material.dart';

class EmployeeWorkplacePoliciesScreen extends StatefulWidget {
  const EmployeeWorkplacePoliciesScreen({super.key});

  @override
  State<EmployeeWorkplacePoliciesScreen> createState() =>
      _EmployeeWorkplacePoliciesScreenState();
}

class _EmployeeWorkplacePoliciesScreenState
    extends State<EmployeeWorkplacePoliciesScreen> {
  late Future<EmployeeWorkplacePolicies> _future;

  @override
  void initState() {
    super.initState();
    _future = sl<EmployeeRepository>().getWorkplacePolicies();
  }

  @override
  Widget build(BuildContext context) {
    final brand = BrandColors.of(context);
    return EmployeeScaffold(
      title: 'Attendance & Payroll Policies',
      selectedIndex: 4,
      child: FutureBuilder<EmployeeWorkplacePolicies>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return loadingView();
          }
          if (snapshot.hasError) {
            return errorView(
              snapshot.error,
              onRetry: () async {
                setState(() {
                  _future = sl<EmployeeRepository>().getWorkplacePolicies();
                });
              },
            );
          }
          final data = snapshot.data;
          if (data == null) {
            return errorView(
              'These policies are unavailable right now.',
              onRetry: () async {
                setState(() {
                  _future = sl<EmployeeRepository>().getWorkplacePolicies();
                });
              },
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              EmployeeCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EmployeeSectionTitle(
                      data.businessName.isEmpty
                          ? 'Your workplace'
                          : data.businessName,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'These are the attendance and payroll rules configured by your business owner. This page is view-only.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: EmployeeColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _PolicySection(
                icon: Icons.fact_check_outlined,
                title: 'Attendance Rules',
                accent: brand.primary,
                child: data.attendance == null
                    ? const _UnavailableNote(
                        'Attendance rules have not been configured yet.',
                      )
                    : _AttendanceRules(policy: data.attendance!),
              ),
              const SizedBox(height: 12),
              _PolicySection(
                icon: Icons.more_time_rounded,
                title: 'Overtime',
                accent: brand.primary,
                child: data.payroll == null
                    ? const _UnavailableNote(
                        'Overtime rules have not been configured yet.',
                      )
                    : _OvertimeRules(
                        payroll: data.payroll!,
                        attendance: data.attendance,
                      ),
              ),
              const SizedBox(height: 12),
              _PolicySection(
                icon: Icons.timer_outlined,
                title: 'Late Deductions',
                accent: brand.primary,
                child: data.payroll == null
                    ? const _UnavailableNote(
                        'Late deduction rules have not been configured yet.',
                      )
                    : _LateRules(
                        payroll: data.payroll!,
                        attendance: data.attendance,
                      ),
              ),
              const SizedBox(height: 12),
              _PolicySection(
                icon: Icons.weekend_outlined,
                title: 'Rest-Day Premium',
                accent: brand.primary,
                child: data.restDay == null
                    ? const _UnavailableNote(
                        'Rest-day premium has not been configured yet.',
                      )
                    : _RestDayRules(policy: data.restDay!),
              ),
              const SizedBox(height: 12),
              _PolicySection(
                icon: Icons.payments_outlined,
                title: 'Your Pay Rate',
                accent: brand.primary,
                child: _PayRateRules(pay: data.yourPay),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  const _PolicySection({
    required this.icon,
    required this.title,
    required this.accent,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return EmployeeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: BrandColors.of(context).iconWell,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(child: EmployeeSectionTitle(title)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _UnavailableNote extends StatelessWidget {
  const _UnavailableNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        height: 1.4,
        color: EmployeeColors.textMuted,
      ),
    );
  }
}

class _PolicyRow extends StatelessWidget {
  const _PolicyRow({
    required this.label,
    required this.value,
    this.detail,
  });

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: EmployeeColors.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: EmployeeColors.textPrimary,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(
              detail!,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: EmployeeColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AttendanceRules extends StatelessWidget {
  const _AttendanceRules({required this.policy});

  final EmployeeAttendancePolicyView policy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PolicyRow(
          label: 'Early time-in window',
          value: workplacePolicyMinutes(policy.earlyClockInMinutes),
          detail:
              'How early you may time in before your scheduled shift start.',
        ),
        _PolicyRow(
          label: 'Grace before late',
          value: workplacePolicyMinutes(policy.onTimeGraceMinutes),
          detail:
              'You are late if you time in after this grace period. Late minutes are the minutes past your scheduled start that go beyond the grace period.',
        ),
        _PolicyRow(
          label: 'Minimum worked shift',
          value: workplacePolicyPercent(policy.absentThresholdPercent),
          detail:
              'You must work at least this share of your scheduled shift to avoid being marked Absent.',
        ),
        _PolicyRow(
          label: 'Half-day cutoff',
          value: workplacePolicyPercent(policy.halfDayThresholdPercent),
          detail: 'Attendance is half-day if you work under this share of the shift.',
        ),
        _PolicyRow(
          label: 'Payroll half-day cutoff',
          value: workplacePolicyMinutes(policy.halfDayThresholdMinutes),
          detail: 'Used for payslip half-day math.',
        ),
        _PolicyRow(
          label: 'Payroll absent cutoff',
          value: workplacePolicyMinutes(policy.absentThresholdMinutes),
          detail:
              'Fallback minute cutoff when a scheduled shift length is unavailable.',
        ),
        _PolicyRow(
          label: 'Maximum overtime stay',
          value: workplacePolicyMinutes(policy.maximumOvertimeMinutes),
          detail:
              'Attendance cutoff only. After this many minutes past shift end, an open time-in can become Incomplete.',
        ),
        _PolicyRow(
          label: 'Missing time-out',
          value: missingClockOutLabel(policy.missingClockOutPolicy),
        ),
        _PolicyRow(
          label: 'Paid break time',
          value: workplacePolicyYesNo(policy.breaktimeIsPaid),
        ),
        _PolicyRow(
          label: 'Attendance affects pay',
          value: workplacePolicyYesNo(policy.attendanceBasedSalaryEnabled),
        ),
        _PolicyRow(
          label: 'Early-out deduction',
          value: policy.earlyOutDeductionEnabled
              ? workplacePolicyMoney(policy.earlyOutDeductionPerMinute)
              : 'Not enabled',
          detail: policy.earlyOutDeductionEnabled
              ? 'Deducted for each early-out minute.'
              : null,
        ),
      ],
    );
  }
}

class _OvertimeRules extends StatelessWidget {
  const _OvertimeRules({
    required this.payroll,
    required this.attendance,
  });

  final EmployeePayrollPolicyView payroll;
  final EmployeeAttendancePolicyView? attendance;

  @override
  Widget build(BuildContext context) {
    if (!payroll.overtimeEnabled) {
      return const _UnavailableNote(
        'Overtime pay is turned off for this workplace.',
      );
    }
    final method = payroll.overtimeCalculationMethod;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PolicyRow(
          label: 'Overtime pay',
          value: 'Turned on',
        ),
        _PolicyRow(
          label: 'How overtime is calculated',
          value: overtimeMethodLabel(method),
        ),
        _PolicyRow(
          label: 'Extra pay per overtime minute',
          value: method == 'flat_per_minute'
              ? workplacePolicyMoney(payroll.overtimePerMinute)
              : workplacePolicyNotApplicable,
          detail: method == 'hourly_statutory'
              ? 'This workplace uses hourly-based overtime instead of a flat peso-per-minute amount.'
              : null,
        ),
        _PolicyRow(
          label: 'Minimum overtime',
          value: workplacePolicyMinutes(attendance?.overtimeMinimumMinutes),
          detail:
              'Overtime pay starts only after this many minutes past your scheduled end.',
        ),
        _PolicyRow(
          label: 'Approval required',
          value: workplacePolicyYesNo(payroll.overtimeApprovalRequired),
          detail: payroll.overtimeApprovalRequired
              ? 'Overtime must be approved before it is included as payable additional pay.'
              : 'Qualifying overtime is included automatically when the other overtime rules are met.',
        ),
        _PolicyRow(
          label: 'Late–overtime balancing',
          value: workplacePolicyYesNo(payroll.enableLateOvertimeBalancing),
          detail: payroll.enableLateOvertimeBalancing
              ? 'If you arrive late, time after your scheduled end may first make up the late time before overtime pay starts.'
              : 'Late time and overtime are handled separately.',
        ),
      ],
    );
  }
}

class _LateRules extends StatelessWidget {
  const _LateRules({
    required this.payroll,
    required this.attendance,
  });

  final EmployeePayrollPolicyView payroll;
  final EmployeeAttendancePolicyView? attendance;

  @override
  Widget build(BuildContext context) {
    if (!payroll.lateDeductionEnabled) {
      return const _UnavailableNote(
        'Late deductions are turned off for this workplace.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PolicyRow(
          label: 'Late deduction',
          value: workplacePolicyMoney(payroll.lateDeductionPerMinute),
          detail: 'Deducted for each late minute after the grace period.',
        ),
        _PolicyRow(
          label: 'Grace before late',
          value: workplacePolicyMinutes(attendance?.onTimeGraceMinutes),
          detail: attendance == null
              ? 'The grace period comes from attendance rules, which are not configured yet.'
              : 'Late minutes are the minutes past your scheduled start that go beyond this grace period.',
        ),
      ],
    );
  }
}

class _RestDayRules extends StatelessWidget {
  const _RestDayRules({required this.policy});

  final EmployeeRestDayPolicyView policy;

  @override
  Widget build(BuildContext context) {
    return _PolicyRow(
      label: 'Extra pay on an approved rest-day shift',
      value: workplacePolicyPercent(policy.restDayPremiumPercent),
      detail:
          'This extra pay applies when you are assigned to work on an approved rest day. Rest days are set on your schedule, not as one weekday for every employee.',
    );
  }
}

class _PayRateRules extends StatelessWidget {
  const _PayRateRules({required this.pay});

  final EmployeePayPolicyView pay;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PolicyRow(
          label: 'Pay basis',
          value: pay.payBasis == null
              ? workplacePolicyUnavailable
              : titleCase(pay.payBasis!),
        ),
        _PolicyRow(
          label: 'Your rate',
          value: employeePayRateSummary(pay),
          detail:
              'This is the rate that applies to you. It is not the same as another employee’s rate.',
        ),
      ],
    );
  }
}
