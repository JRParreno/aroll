import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/theme/business_brand_theme.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class EmployeePayrollHistoryScreen extends StatefulWidget {
  const EmployeePayrollHistoryScreen({super.key});

  @override
  State<EmployeePayrollHistoryScreen> createState() =>
      _EmployeePayrollHistoryScreenState();
}

class _EmployeePayrollHistoryScreenState
    extends State<EmployeePayrollHistoryScreen> {
  late Future<List<EmployeePayrollHistoryItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<EmployeePayrollHistoryItem>> _load() async {
    final payroll = await sl<EmployeeRepository>().getPayroll();
    return payroll.history;
  }

  String _asOfParam(DateTime value) => value.toIso8601String().split('T').first;

  @override
  Widget build(BuildContext context) {
    return EmployeeScaffold(
      title: 'Payroll History',
      selectedIndex: 3,
      showBack: true,
      child: FutureBuilder<List<EmployeePayrollHistoryItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return loadingView();
          }
          if (snapshot.hasError) return payrollErrorView(snapshot.error);

          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: EmployeeEmptyState(
                  title: 'No payroll history yet',
                  description:
                      'Past pay periods will appear here once they are available.',
                  icon: Icons.history_rounded,
                ),
              ),
            );
          }

          final brand = BrandColors.of(context);
          return RefreshIndicator(
            color: brand.primary,
            onRefresh: () async {
              setState(() => _future = _load());
              await _future;
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                _PastPeriodsEntry(count: items.length),
                const SizedBox(height: 10),
                ...items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _PayrollHistoryCard(
                      item: item,
                      onTap: () => context.push(
                        '/payslip?as_of=${_asOfParam(item.periodEnd)}',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PastPeriodsEntry extends StatelessWidget {
  const _PastPeriodsEntry({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final brand = BrandColors.of(context);
    final periods = '$count ${count == 1 ? 'period' : 'periods'} available';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EmployeeColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: brand.iconWell,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.history_rounded,
              color: brand.primary,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Past pay periods',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    height: 1.2,
                    color: EmployeeColors.textPrimary,
                  ),
                ),
                Text(
                  periods,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.25,
                    color: EmployeeColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _periodRange(DateTime start, DateTime end) {
  if (start.year == end.year) {
    return '${monthDay(start)} – ${shortDate(end)}';
  }
  return '${shortDate(start)} – ${shortDate(end)}';
}

class _PayrollHistoryCard extends StatelessWidget {
  const _PayrollHistoryCard({
    required this.item,
    required this.onTap,
  });

  final EmployeePayrollHistoryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isCurrent = item.payrollStatus == 'current';
    final brand = BrandColors.of(context);

    final rate = salaryRateDisplay(
      payBasis: item.payBasis,
      dailyRate: item.dailyRate,
      hourlyRate: item.hourlyRate,
      monthlySalary: item.monthlySalary,
    );

    return EmployeeCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _periodRange(item.periodStart, item.periodEnd),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              height: 1.2,
                              color: EmployeeColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Pay date · ${shortDate(item.payDate)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: EmployeeColors.textMuted,
                              fontSize: 12,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? brand.iconWell
                            : EmployeeColors.chipFill,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        titleCase(item.payrollStatus),
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          color: isCurrent
                              ? brand.primary
                              : EmployeeColors.textBody,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: EmployeeColors.textMuted,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _PayrollMetrics(item: item, salaryRate: rate),
                if (item.payrollAdjustments.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: EmployeeColors.fieldFill,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < item.payrollAdjustments.length; i++)
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: i == item.payrollAdjustments.length - 1
                                  ? 0
                                  : 4,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item.payrollAdjustments[i].displayName}${item.payrollAdjustments[i].kind == 'allowance' ? ' (+)' : ' (−)'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: EmployeeColors.textMuted,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  money(item.payrollAdjustments[i].amount),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: EmployeeColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: brand.iconWell,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(18),
              ),
            ),
            child: Row(
              children: [
                Text(
                  'Final net pay',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: brand.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    money(item.displayNetPay),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: brand.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PayrollMetrics extends StatelessWidget {
  const _PayrollMetrics({
    required this.item,
    required this.salaryRate,
  });

  final EmployeePayrollHistoryItem item;
  final String salaryRate;

  @override
  Widget build(BuildContext context) {
    final gross = money(item.grossPay);
    final adjustments = money(item.payrollAdjustmentsTotal);
    final days = '${item.workedDays}';
    return LayoutBuilder(
      builder: (context, constraints) {
        final cells = [
          _MetricCell(label: 'Gross pay', value: gross),
          _MetricCell(label: 'Adjustments', value: adjustments),
          _MetricCell(label: 'Days worked', value: days),
          _MetricCell(label: 'Salary rate', value: salaryRate),
        ];
        if (constraints.maxWidth < 220) {
          return Column(
            children: [
              for (var i = 0; i < cells.length; i++)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
                  child: cells[i],
                ),
            ],
          );
        }
        return Column(
          children: [
            Row(
              children: [
                Expanded(child: cells[0]),
                const SizedBox(width: 12),
                Expanded(child: cells[1]),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: cells[2]),
                const SizedBox(width: 12),
                Expanded(child: cells[3]),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: EmployeeColors.textMuted,
            fontSize: 11,
            height: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            height: 1.2,
            fontWeight: FontWeight.w700,
            color: EmployeeColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
