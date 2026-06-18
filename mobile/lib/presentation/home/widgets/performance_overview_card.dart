import 'package:aroll_mobile/presentation/home/data/dashboard_mock.dart';
import 'package:aroll_mobile/presentation/home/models/dashboard_models.dart';
import 'package:aroll_mobile/presentation/home/widgets/dashboard_card.dart';
import 'package:flutter/material.dart';

class PerformanceOverviewCard extends StatefulWidget {
  const PerformanceOverviewCard({super.key});

  @override
  State<PerformanceOverviewCard> createState() =>
      _PerformanceOverviewCardState();
}

class _PerformanceOverviewCardState extends State<PerformanceOverviewCard> {
  PerformancePeriod _period = PerformancePeriod.weekly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = DashboardMock.performance(_period);
    final maxValue = snapshot.metrics
        .map((m) => m.value)
        .fold(1, (a, b) => a > b ? a : b);

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Performance Overview',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          SegmentedButton<PerformancePeriod>(
            segments: const [
              ButtonSegment(
                value: PerformancePeriod.weekly,
                label: Text('Weekly'),
              ),
              ButtonSegment(
                value: PerformancePeriod.monthly,
                label: Text('Monthly'),
              ),
              ButtonSegment(
                value: PerformancePeriod.yearly,
                label: Text('Yearly'),
              ),
            ],
            selected: {_period},
            onSelectionChanged: (selection) {
              setState(() => _period = selection.first);
            },
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 180,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: snapshot.metrics.map((metric) {
                final fraction = metric.value / maxValue;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${metric.value}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Flexible(
                          child: FractionallySizedBox(
                            heightFactor: fraction.clamp(0.08, 1.0),
                            child: Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Color(metric.colorArgb),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _shortLabel(metric.label),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 10,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _shortLabel(String label) {
    return switch (label) {
      'Under Time' => 'Under',
      'Over Time' => 'Over',
      _ => label,
    };
  }
}
