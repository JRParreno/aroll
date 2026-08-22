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

  String _asOfParam(DateTime value) =>
      value.toIso8601String().split('T').first;

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
          if (snapshot.hasError) return errorView(snapshot.error);

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
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: EmployeeColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: brand.iconWell,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.history_rounded,
                          color: brand.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Past pay periods',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: EmployeeColors.textPrimary,
                              ),
                            ),
                            Text(
                              '${items.length} period${items.length == 1 ? '' : 's'} · tap to open payslip',
                              style: const TextStyle(
                                fontSize: 12,
                                color: EmployeeColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                ...items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
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

    return EmployeeCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: brand.iconWell,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.payments_outlined,
                        size: 20,
                        color: brand.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${shortDate(item.periodStart)} – ${shortDate(item.periodEnd)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: EmployeeColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Pay date ${shortDate(item.payDate)}',
                            style: const TextStyle(
                              color: EmployeeColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? brand.iconWell
                            : EmployeeColors.chipFill,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        titleCase(item.payrollStatus),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isCurrent
                              ? brand.primary
                              : EmployeeColors.textBody,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: EmployeeColors.textMuted,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  '${salaryRateRowLabel()}: ${salaryRateDisplay(
                    payBasis: item.payBasis,
                    dailyRate: item.dailyRate,
                    hourlyRate: item.hourlyRate,
                    monthlySalary: item.monthlySalary,
                  )}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: EmployeeColors.textBody,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _AmountColumn(
                        label: 'Gross',
                        value: money(item.grossPay),
                      ),
                    ),
                    Expanded(
                      child: _AmountColumn(
                        label: 'Adjustments',
                        value: money(item.payrollAdjustmentsTotal),
                      ),
                    ),
                    Expanded(
                      child: _AmountColumn(
                        label: 'Days',
                        value: '${item.workedDays}',
                      ),
                    ),
                  ],
                ),
                if (item.payrollAdjustments.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: EmployeeColors.fieldFill,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: item.payrollAdjustments
                          .map(
                            (adj) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${adj.displayName}${adj.kind == 'allowance' ? ' (+)' : ' (−)'}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: EmployeeColors.textMuted,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    money(adj.amount),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: EmployeeColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: brand.primary,
                  ),
                ),
                const Spacer(),
                Text(
                  money(item.displayNetPay),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: brand.primary,
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

class _AmountColumn extends StatelessWidget {
  const _AmountColumn({
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
          style: const TextStyle(
            color: EmployeeColors.textMuted,
            fontSize: 11,
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
            fontWeight: FontWeight.w700,
            color: EmployeeColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
