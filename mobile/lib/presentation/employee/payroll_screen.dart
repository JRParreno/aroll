import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class EmployeePayrollScreen extends StatefulWidget {
  const EmployeePayrollScreen({super.key});

  @override
  State<EmployeePayrollScreen> createState() => _EmployeePayrollScreenState();
}

class _EmployeePayrollScreenState extends State<EmployeePayrollScreen> {
  late Future<_PayrollData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_PayrollData> _load() async {
    final repo = sl<EmployeeRepository>();
    final results = await Future.wait([
      repo.getProfile(),
      repo.getPayroll(),
    ]);
    return _PayrollData(
      profile: results[0] as EmployeeProfile,
      payroll: results[1] as EmployeePayroll,
    );
  }

  @override
  Widget build(BuildContext context) {
    return EmployeeScaffold(
      title: 'Payroll',
      selectedIndex: 3,
      showBack: true,
      child: FutureBuilder<_PayrollData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return loadingView();
          }
          if (snapshot.hasError) return errorView(snapshot.error);
          final data = snapshot.data!;
          final payroll = data.payroll;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              _PayrollHeader(profile: data.profile),
              const SizedBox(height: 16),
              _CurrentSalaryCard(payroll: payroll),
              const SizedBox(height: 14),
              _DailyWageCard(payroll: payroll),
              const SizedBox(height: 16),
              EmployeePrimaryButton(
                label: 'View Payslip',
                onPressed: () => context.go('/payslip'),
                icon: Icons.receipt_long_rounded,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PayrollData {
  const _PayrollData({required this.profile, required this.payroll});

  final EmployeeProfile profile;
  final EmployeePayroll payroll;
}

class _PayrollHeader extends StatelessWidget {
  const _PayrollHeader({required this.profile});

  final EmployeeProfile profile;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        EmployeeAvatar(
          imageUrl: profile.profileImageUrl,
          name: profile.fullName,
          size: 78,
        ),
        const SizedBox(height: 6),
        Text(
          'Welcome back!',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: const Color(0xFF6B7280),
              ),
        ),
        Text(
          profile.fullName,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _CurrentSalaryCard extends StatelessWidget {
  const _CurrentSalaryCard({required this.payroll});

  final EmployeePayroll payroll;

  @override
  Widget build(BuildContext context) {
    final summary = payroll.summary;
    return EmployeeCard(
      child: Column(
        children: [
          _SummaryLine(
            'Current Salary:',
            money(summary.netPay),
            strong: true,
            valueColor: const Color(0xFF15803D),
          ),
          _SummaryLine('Salary Rate:', '${money(summary.dailyRate)} (daily)'),
          _SummaryLine('Employment Type:', titleCase(summary.employmentType)),
          _SummaryLine('Job Position:', summary.positionTitle ?? 'Employee'),
        ],
      ),
    );
  }
}

class _DailyWageCard extends StatelessWidget {
  const _DailyWageCard({required this.payroll});

  final EmployeePayroll payroll;

  @override
  Widget build(BuildContext context) {
    return EmployeeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Basic Daily Wage',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              _PeriodChip(monthName(payroll.summary.periodEnd).substring(0, 3)),
              const SizedBox(width: 6),
              _PeriodChip('${payroll.summary.periodEnd.year}'),
            ],
          ),
          const Divider(height: 20),
          const Row(
            children: [
              Expanded(flex: 2, child: Text('Date', style: _TableHeaderStyle())),
              Expanded(child: Text('Remarks', style: _TableHeaderStyle())),
              Expanded(child: Text('Basic Salary', style: _TableHeaderStyle())),
              Expanded(child: Text('Earned', textAlign: TextAlign.right, style: _TableHeaderStyle())),
            ],
          ),
          const SizedBox(height: 8),
          if (payroll.rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: EmployeeEmptyState(
                title: 'No payroll records yet',
                description:
                    'Daily wage entries will appear here for the current pay period.',
                icon: Icons.payments_outlined,
              ),
            )
          else
            ...payroll.rows.map((row) => _PayrollRow(row: row)),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine(
    this.label,
    this.value, {
    this.strong = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool strong;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: EmployeeColors.chipFill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _PayrollRow extends StatelessWidget {
  const _PayrollRow({required this.row});

  final EmployeePayrollRow row;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(row.status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(shortDate(row.date), style: const TextStyle(fontSize: 11))),
          Expanded(
            child: Text(
              _rowStatus(row),
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: Text(money(row.dailyRate), style: const TextStyle(fontSize: 11))),
          Expanded(
            child: Text(
              money(row.earned),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _TableHeaderStyle extends TextStyle {
  const _TableHeaderStyle()
      : super(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: EmployeeColors.textBody,
        );
}

String _rowStatus(EmployeePayrollRow row) {
  if (row.holidayName != null) return 'Holiday';
  if (row.status == 'complete') return 'On Time';
  if (row.status == 'incomplete') return 'Under-Time';
  return titleCase(row.status);
}
