import 'package:aroll_mobile/presentation/home/models/dashboard_models.dart';
import 'package:aroll_mobile/presentation/home/widgets/dashboard_card.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SalaryCard extends StatelessWidget {
  const SalaryCard({super.key, required this.payroll});

  final PayrollSummary payroll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.payments_outlined,
                  color: theme.colorScheme.primary, size: 22),
              const SizedBox(width: 8),
              Text(
                'Salary Earned',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            payroll.periodLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            currency.format(payroll.amount),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
