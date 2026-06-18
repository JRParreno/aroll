import 'package:aroll_mobile/presentation/home/models/dashboard_models.dart';
import 'package:aroll_mobile/presentation/home/widgets/dashboard_card.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ScheduleCard extends StatelessWidget {
  const ScheduleCard({super.key, required this.shift});

  final TodayShift shift;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeFormat = DateFormat.jm();

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule, color: theme.colorScheme.primary, size: 22),
              const SizedBox(width: 8),
              Text(
                "Today's Schedule",
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (shift.status == ShiftStatus.offToday &&
              shift.label == 'No shift assigned')
            Text(
              'You are off today.',
              style: theme.textTheme.bodyLarge,
            )
          else ...[
            Text(
              shift.label,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _TimeBlock(
                    label: 'Start',
                    time: timeFormat.format(shift.startTime),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TimeBlock(
                    label: 'End',
                    time: timeFormat.format(shift.endTime),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          _StatusChip(status: shift.status),
        ],
      ),
    );
  }
}

class _TimeBlock extends StatelessWidget {
  const _TimeBlock({required this.label, required this.time});

  final String label;
  final String time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            time,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ShiftStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ShiftStatus.onDuty => ('On Duty', const Color(0xFF2E7D32)),
      ShiftStatus.upcoming => ('Upcoming', const Color(0xFF1565C0)),
      ShiftStatus.offToday => ('Off Today', const Color(0xFF757575)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}
