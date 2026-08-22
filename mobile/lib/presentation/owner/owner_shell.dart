import 'dart:math' as math;

import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Navigation shell
// ─────────────────────────────────────────────────────────────────────────────

class OwnerShell extends StatefulWidget {
  const OwnerShell({
    super.key,
    required this.selectedIndex,
    required this.title,
    required this.child,
    this.actions,
    this.showBackButton = false,
    this.showAppBar = true,
    this.backgroundColor,
    this.showNotificationBell = true,
  });

  final int selectedIndex;
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final bool showBackButton;
  final bool showAppBar;
  final Color? backgroundColor;
  final bool showNotificationBell;

  static const _routes = [
    '/owner/home',
    '/owner/attendance',
    '/owner/profile',
  ];

  @override
  State<OwnerShell> createState() => _OwnerShellState();
}

class _OwnerShellState extends State<OwnerShell> with WidgetsBindingObserver {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshUnread();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshUnread();
  }

  Future<void> _refreshUnread() async {
    if (!widget.showNotificationBell) return;
    try {
      final count = await sl<OwnerRepository>().unreadCount();
      if (mounted) setState(() => _unread = count);
    } catch (_) {}
  }

  void _onBack(BuildContext context) {
    appNavigateBack(context, fallbackRoute: '/owner/home');
  }

  @override
  Widget build(BuildContext context) {
    final mergedActions = <Widget>[
      ...?widget.actions,
      if (widget.showNotificationBell)
        IconButton(
          tooltip: 'Notifications',
          onPressed: () async {
            await context.push('/owner/notifications');
            if (mounted) _refreshUnread();
          },
          icon: Badge(
            isLabelVisible: _unread > 0,
            label: Text(_unread > 99 ? '99+' : '$_unread'),
            child: const Icon(Icons.notifications_outlined),
          ),
        ),
    ];

    return Scaffold(
      backgroundColor: widget.backgroundColor ?? AppColors.scaffold,
      appBar: widget.showAppBar
          ? AppBar(
              backgroundColor: AppColors.scaffold,
              elevation: 0,
              scrolledUnderElevation: 0,
              automaticallyImplyLeading: false,
              titleSpacing:
                  widget.showBackButton ? 0 : NavigationToolbar.kMiddleSpacing,
              leading: widget.showBackButton
                  ? IconButton(
                      tooltip: 'Back',
                      constraints: const BoxConstraints(
                        minWidth: AppSizes.minTap,
                        minHeight: AppSizes.minTap,
                      ),
                      onPressed: () => _onBack(context),
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        size: AppSizes.iconLg,
                      ),
                    )
                  : null,
              title: Text(widget.title, style: appPageTitleStyle()),
              centerTitle: false,
              actions: mergedActions,
            )
          : null,
      body: widget.showAppBar ? SafeArea(child: widget.child) : widget.child,
      bottomNavigationBar: Material(
        color: AppColors.white,
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.white,
            border: Border(
              top: BorderSide(color: AppColors.border),
            ),
          ),
          child: NavigationBar(
            selectedIndex: widget.selectedIndex,
            height: AppSizes.navHeight,
            backgroundColor: AppColors.white,
            surfaceTintColor: Colors.transparent,
            indicatorColor: AppColors.iconWell,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: (index) =>
                context.go(OwnerShell._routes[index]),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined, size: AppSizes.iconLg),
                selectedIcon:
                    Icon(Icons.home_rounded, size: AppSizes.iconLg),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.fact_check_outlined, size: AppSizes.iconLg),
                selectedIcon:
                    Icon(Icons.fact_check_rounded, size: AppSizes.iconLg),
                label: 'Attendance',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded, size: AppSizes.iconLg),
                selectedIcon:
                    Icon(Icons.person_rounded, size: AppSizes.iconLg),
                label: 'Profile',
              ),
            ],
          ),
        ),
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
    this.selectedIndex = 0,
    this.backgroundColor,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 28),
  });

  final String title;
  final Future<dynamic> future;
  final List<Widget> Function(dynamic) builder;
  final int selectedIndex;
  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => OwnerShell(
        selectedIndex: selectedIndex,
        showBackButton: true,
        title: title,
        backgroundColor: backgroundColor,
        child: FutureBuilder<dynamic>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return appLoadingView();
            }
            if (snapshot.hasError) return const OwnerErrorState();
            return ListView(
              padding: padding,
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
              return appLoadingView();
            }
            if (snapshot.hasError) return const OwnerErrorState();
            final items = snapshot.data ?? const [];
            if (items.isEmpty) {
              return OwnerEmptyState(
                emptyText,
                description: 'New records will appear here automatically.',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.lg),
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
              return appLoadingView();
            }
            if (snapshot.hasError) return const OwnerErrorState();
            final data = snapshot.data ?? const {};
            final items = (data[listKey] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>()
                .toList();
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                if (headerBuilder != null) ...[
                  headerBuilder!(data),
                  const SizedBox(height: 14),
                ],
                if (items.isEmpty)
                  const OwnerEmptyState(
                    'No records yet',
                    description:
                        'When activity starts, it will show up here.',
                    icon: Icons.inbox_outlined,
                  )
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
  const OwnerCard({
    super.key,
    required this.child,
    this.margin,
    this.padding,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets? margin;
  final EdgeInsets? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AppCard(
        margin: margin,
        padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
        onTap: onTap,
        child: child,
      );
}

class OwnerEmptyState extends StatelessWidget {
  const OwnerEmptyState(
    this.message, {
    super.key,
    this.description,
    this.icon = Icons.inbox_outlined,
  });

  final String message;
  final String? description;
  final IconData icon;

  @override
  Widget build(BuildContext context) => AppEmptyState(
        title: message,
        description: description ??
            'Nothing here yet — check back once activity starts.',
        icon: icon,
      );
}

class OwnerErrorState extends StatelessWidget {
  const OwnerErrorState({super.key, this.onRetry});

  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) => AppErrorState(
        message: 'Unable to load owner data. Please try again.',
        onRetry: onRetry,
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
  Widget build(BuildContext context) => AppPressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 0,
          color: prominent ? AppColors.primary : AppColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.card),
            side: BorderSide(
              color: AppColors.border.withValues(alpha: prominent ? 0 : 1),
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(14),
            leading: CircleAvatar(
              backgroundColor:
                  prominent ? Colors.white24 : AppColors.iconWell,
              child: Icon(
                icon,
                size: AppSizes.iconLg,
                color: prominent ? AppColors.white : AppColors.primary,
              ),
            ),
            title: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: prominent ? AppColors.white : AppColors.textPrimary,
              ),
            ),
            subtitle: Text(
              subtitle,
              style: TextStyle(
                color: prominent ? Colors.white70 : AppColors.textMuted,
              ),
            ),
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: prominent ? AppColors.white : AppColors.textMuted,
            ),
          ),
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
          Text(
            'Performance Overview',
            style: appSectionTitleStyle(),
          ),
          const SizedBox(height: 2),
          Text(
            'Live attendance and shift activity.',
            style: appMutedStyle().copyWith(fontSize: 12),
          ),
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
                            Text(
                              '${entry.$2}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Container(
                              height: math.max(7, 70 * entry.$2 / maxValue),
                              decoration: BoxDecoration(
                                color: entry.$3,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              entry.$1,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 9),
                            ),
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
