import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/theme/business_brand_theme.dart';
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
    final profile = results[0] as EmployeeProfile;
    final appState = sl<AppState>();
    appState.updateEmployeeProfileImage(profile.profileImageUrl);
    appState.updateBusinessBranding(profile.branding);
    return _PayrollData(
      profile: profile,
      payroll: results[1] as EmployeePayroll,
    );
  }

  @override
  Widget build(BuildContext context) {
    return EmployeeScaffold(
      title: 'Payroll',
      selectedIndex: 3,
      showBack: true,
      actions: [
        IconButton(
          tooltip: 'Payroll History',
          onPressed: () => context.push('/payroll/history'),
          icon: const Icon(Icons.history_rounded),
        ),
      ],
      child: FutureBuilder<_PayrollData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return loadingView();
          }
          if (snapshot.hasError) return errorView(snapshot.error);
          final data = snapshot.data!;
          final payroll = data.payroll;
          final primary = employeePrimary(data.profile.branding, context);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              _PayrollHeader(profile: data.profile, accent: primary),
              const SizedBox(height: 14),
              _CurrentSalaryCard(payroll: payroll),
              const SizedBox(height: 14),
              _DailyWageCard(payroll: payroll),
              const SizedBox(height: 18),
              EmployeePrimaryButton(
                label: 'View Payslip',
                onPressed: () => context.go('/payslip'),
                icon: Icons.receipt_long_rounded,
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () => context.push('/payroll/history'),
                icon: const Icon(Icons.history_rounded, size: 18),
                label: const Text('View payroll history'),
                style: TextButton.styleFrom(
                  foregroundColor: brandPrimary(context),
                  textStyle: const TextStyle(fontWeight: FontWeight.w600),
                ),
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
  const _PayrollHeader({
    required this.profile,
    required this.accent,
  });

  final EmployeeProfile profile;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final appState = sl<AppState>();

    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final avatarUrl = appState.resolveEmployeeAvatarUrl(
          profile.profileImageUrl,
        );
        final brand = BrandColors.of(context);
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
          decoration: BoxDecoration(
            gradient: brand.headerGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.2),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.85),
                    width: 2.5,
                  ),
                ),
                child: EmployeeAvatar(
                  imageUrl: avatarUrl,
                  name: profile.fullName,
                  size: 56,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome back',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      profile.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profile.position?.trim().isNotEmpty == true
                          ? profile.position!
                          : 'Employee',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                clipBehavior: Clip.antiAlias,
                child: BusinessLogo(
                  logoUrl: profile.branding?.logoUrl,
                  height: 42,
                  width: 42,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CurrentSalaryCard extends StatelessWidget {
  const _CurrentSalaryCard({required this.payroll});

  final EmployeePayroll payroll;

  @override
  Widget build(BuildContext context) {
    final summary = payroll.summary;
    final brand = BrandColors.of(context);
    return EmployeeCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              color: brand.iconWell,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current net pay',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: brand.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  money(summary.displayNetPay),
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: brand.primary,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${shortDate(summary.periodStart)} – ${shortDate(summary.periodEnd)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: brand.secondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              children: [
                _SummaryLine(
                  salaryRateRowLabel(),
                  salaryRateDisplayFromPayslip(summary),
                ),
                _SummaryLine(
                  'Employment type',
                  titleCase(summary.employmentType),
                ),
                _SummaryLine(
                  'Job position',
                  summary.positionTitle ?? 'Employee',
                ),
                _SummaryLine(
                  'Worked days',
                  '${summary.workedDays}',
                  showDivider: false,
                ),
              ],
            ),
          ),
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
    final brand = BrandColors.of(context);
    final month = monthName(payroll.summary.periodEnd);
    final year = '${payroll.summary.periodEnd.year}';

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
                  color: brand.iconWell,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.calendar_view_week_rounded,
                  color: brand.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Basic daily wage',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const Text(
                      'Day-by-day earnings this period',
                      style: TextStyle(
                        fontSize: 12,
                        color: EmployeeColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              _PeriodChip(month.length >= 3 ? month.substring(0, 3) : month),
              const SizedBox(width: 6),
              _PeriodChip(year),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: EmployeeColors.fieldFill,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text('Date', style: _TableHeaderStyle()),
                ),
                Expanded(
                  child: Text('Status', style: _TableHeaderStyle()),
                ),
                Expanded(
                  child: Text('Rate', style: _TableHeaderStyle()),
                ),
                Expanded(
                  child: Text(
                    'Earned',
                    textAlign: TextAlign.right,
                    style: _TableHeaderStyle(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (payroll.rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: EmployeeEmptyState(
                title: 'No payroll records yet',
                description:
                    'Daily wage entries will appear here for the current pay period.',
                icon: Icons.payments_outlined,
                inCard: true,
              ),
            )
          else
            ...payroll.rows.map(
              (row) => _PayrollRow(
                row: row,
                rateLabel: salaryRateDisplayFromPayslip(payroll.summary),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine(
    this.label,
    this.value, {
    this.showDivider = true,
  });

  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(
                bottom: BorderSide(color: EmployeeColors.border),
              )
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: EmployeeColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: EmployeeColors.textPrimary,
              ),
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
    final brand = BrandColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: brand.iconWell,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: brand.primary,
        ),
      ),
    );
  }
}

class _PayrollRow extends StatelessWidget {
  const _PayrollRow({required this.row, required this.rateLabel});

  final EmployeePayrollRow row;
  final String rateLabel;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(row.status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              shortDate(row.date),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: EmployeeColors.textPrimary,
              ),
            ),
          ),
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
          Expanded(
            child: Text(
              rateLabel,
              style: const TextStyle(
                fontSize: 11,
                color: EmployeeColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              money(row.earned),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: EmployeeColors.textPrimary,
              ),
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
          color: EmployeeColors.textMuted,
        );
}

String _rowStatus(EmployeePayrollRow row) {
  if (row.holidayName != null) return 'Holiday';
  if (row.status == 'complete') return 'On Time';
  if (row.status == 'incomplete') {
    return 'Incomplete Attendance · Pending Correction';
  }
  return titleCase(row.status);
}
