import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Navigation shell
// ─────────────────────────────────────────────────────────────────────────────

class OwnerShell extends StatelessWidget {
  const OwnerShell({
    super.key,
    required this.selectedIndex,
    required this.title,
    required this.child,
    this.actions,
    this.showBackButton = false,
  });

  final int selectedIndex;
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final bool showBackButton;

  static const _routes = [
    '/owner/home',
    '/owner/attendance',
    '/owner/profile',
  ];

  void _onBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/owner/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F6F8),
        automaticallyImplyLeading: showBackButton,
        leading: showBackButton
            ? IconButton(
                tooltip: 'Back',
                onPressed: () => _onBack(context),
                icon: const Icon(Icons.arrow_back_rounded),
              )
            : null,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: actions,
      ),
      body: SafeArea(child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        height: 70,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) => context.go(_routes[index]),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.fact_check_rounded), label: 'Attendance'),
          NavigationDestination(
              icon: Icon(Icons.person_rounded), label: 'Profile'),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Generic screen layouts
// ─────────────────────────────────────────────────────────────────────────────

/// A secondary owner screen that fetches data and renders a scrollable list
/// of widgets. Handles loading, error, and data states automatically.
class OwnerSecondaryScreen extends StatelessWidget {
  const OwnerSecondaryScreen({
    super.key,
    required this.title,
    required this.future,
    required this.builder,
  });

  final String title;
  final Future<dynamic> future;
  final List<Widget> Function(dynamic) builder;

  @override
  Widget build(BuildContext context) => OwnerShell(
        selectedIndex: 0,
        showBackButton: true,
        title: title,
        child: FutureBuilder<dynamic>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) return const OwnerErrorState();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: builder(snapshot.data),
            );
          },
        ),
      );
}

/// An owner screen that fetches a `List<Map>` and renders each item with
/// [itemBuilder]. Handles loading, error, and empty states.
class OwnerDataScreen extends StatelessWidget {
  const OwnerDataScreen({
    super.key,
    required this.selectedIndex,
    required this.title,
    required this.load,
    required this.emptyText,
    required this.itemBuilder,
  });

  final int selectedIndex;
  final String title;
  final Future<List<Map<String, dynamic>>> Function() load;
  final String emptyText;
  final Widget Function(Map<String, dynamic>) itemBuilder;

  @override
  Widget build(BuildContext context) => OwnerShell(
        selectedIndex: selectedIndex,
        showBackButton: true,
        title: title,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: load(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) return const OwnerErrorState();
            final items = snapshot.data ?? const [];
            if (items.isEmpty) return OwnerEmptyState(emptyText);
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, index) =>
                  OwnerCard(child: itemBuilder(items[index])),
            );
          },
        ),
      );
}

/// An owner screen that fetches a `Map` envelope, extracts a list by [listKey],
/// and renders each item with [itemBuilder]. Optionally renders a [headerBuilder]
/// above the list.
class OwnerMapListScreen extends StatelessWidget {
  const OwnerMapListScreen({
    super.key,
    required this.selectedIndex,
    required this.title,
    required this.load,
    required this.listKey,
    required this.itemBuilder,
    this.headerBuilder,
  });

  final int selectedIndex;
  final String title;
  final Future<Map<String, dynamic>> Function() load;
  final String listKey;
  final Widget Function(Map<String, dynamic>) itemBuilder;
  final Widget Function(Map<String, dynamic>)? headerBuilder;

  @override
  Widget build(BuildContext context) => OwnerShell(
        selectedIndex: selectedIndex,
        showBackButton: true,
        title: title,
        child: FutureBuilder<Map<String, dynamic>>(
          future: load(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) return const OwnerErrorState();
            final data = snapshot.data ?? const {};
            final items = (data[listKey] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>()
                .toList();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (headerBuilder != null) ...[
                  headerBuilder!(data),
                  const SizedBox(height: 14),
                ],
                if (items.isEmpty)
                  const OwnerEmptyState('No records are available yet.')
                else
                  ...items.map(
                    (item) => OwnerCard(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: itemBuilder(item),
                    ),
                  ),
              ],
            );
          },
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared UI widgets
// ─────────────────────────────────────────────────────────────────────────────

class OwnerCard extends StatelessWidget {
  const OwnerCard({super.key, required this.child, this.margin, this.padding});

  final Widget child;
  final EdgeInsets? margin;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: margin,
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .035),
              blurRadius: 14,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: child,
      );
}

class OwnerEmptyState extends StatelessWidget {
  const OwnerEmptyState(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inbox_outlined,
                  size: 44, color: Color(0xFF6B7280)),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

class OwnerErrorState extends StatelessWidget {
  const OwnerErrorState({super.key, this.onRetry});

  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Unable to load owner data. Please try again.'),
              if (onRetry != null)
                TextButton(
                    onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      );
}

class OwnerActionCard extends StatelessWidget {
  const OwnerActionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.prominent = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool prominent;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        color: prominent ? const Color(0xFF1E466E) : Colors.white,
        child: ListTile(
          contentPadding: const EdgeInsets.all(14),
          leading: CircleAvatar(
            backgroundColor:
                prominent ? Colors.white24 : const Color(0xFFE7EEF5),
            child: Icon(icon,
                color: prominent ? Colors.white : const Color(0xFF1E466E)),
          ),
          title: Text(title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: prominent ? Colors.white : null,
              )),
          subtitle: Text(subtitle,
              style: TextStyle(
                color: prominent ? Colors.white70 : const Color(0xFF6B7280),
              )),
          trailing: Icon(Icons.chevron_right_rounded,
              color: prominent ? Colors.white : null),
          onTap: onTap,
        ),
      );
}

/// Bar chart showing attendance and shift performance metrics.
class OwnerPerformanceChart extends StatelessWidget {
  const OwnerPerformanceChart({super.key, required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final values = [
      ('On time', ownerParseInt(summary['on_time_clock_ins']), Colors.green),
      ('Late', ownerParseInt(summary['late_clock_ins']), Colors.amber),
      ('Under', ownerParseInt(summary['undertime_shifts']), Colors.orange),
      ('Over', ownerParseInt(summary['overtime_shifts']), Colors.blue),
      ('Absent', ownerParseInt(summary['absent_shifts']), Colors.redAccent),
    ];
    final maxValue =
        math.max(1, values.map((entry) => entry.$2).fold(0, math.max));
    return OwnerCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Performance Overview',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  )),
          const SizedBox(height: 2),
          const Text('Live attendance and shift activity.',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
          const SizedBox(height: 10),
          SizedBox(
            height: 108,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: values
                  .map(
                    (entry) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('${entry.$2}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                )),
                            const SizedBox(height: 3),
                            Container(
                              height:
                                  math.max(7, 70 * entry.$2 / maxValue),
                              decoration: BoxDecoration(
                                color: entry.$3,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(entry.$1,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 9)),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  _DonutChartPainter({required this.values, required this.colors});

  final List<double> values;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    var startAngle = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = (values[i] / total) * 2 * math.pi;
      paint.color = colors[i % colors.length];
      canvas.drawArc(rect.deflate(5), startAngle, sweep, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.colors != colors;
}

/// Donut chart widget backed by [_DonutChartPainter].
class OwnerDonutChart extends StatelessWidget {
  const OwnerDonutChart({
    super.key,
    required this.values,
    required this.colors,
    this.size = 58,
  });

  final List<double> values;
  final List<Color> colors;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: size,
        width: size,
        child: CustomPaint(
          painter: _DonutChartPainter(values: values, colors: colors),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared utilities
// ─────────────────────────────────────────────────────────────────────────────

/// Coerces a JSON number or string to an [int]. Returns 0 on parse failure.
int ownerParseInt(Object? value) =>
    value is num ? value.round() : int.tryParse('$value') ?? 0;

/// Formats a snake_case API key as Title Case for display.
String ownerFormatKey(String value) => value
    .replaceAll('_', ' ')
    .split(' ')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

/// Returns up to two uppercase initials from [value].
String ownerInitials(String value) {
  final parts = value.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  return parts.take(2).map((part) => part[0].toUpperCase()).join();
}
