import 'dart:convert';
import 'dart:typed_data';

import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

Color employeePrimary(
    BusinessBrandingSettings? branding, BuildContext context) {
  return _hexColor(branding?.theme.primaryColor) ??
      Theme.of(context).colorScheme.primary;
}

String money(num value) {
  return NumberFormat.currency(
    locale: 'en_PH',
    symbol: 'PHP ',
    decimalDigits: 2,
  ).format(value);
}

String shortDate(DateTime value) => DateFormat('MMM d, yyyy').format(value);

String monthDay(DateTime value) => DateFormat('MMM d').format(value);

String monthName(DateTime value) => DateFormat('MMMM').format(value);

String dayName(DateTime value) => DateFormat('E').format(value);

String dayNumber(DateTime value) => DateFormat('d').format(value);

String timeOnly(DateTime? value) {
  if (value == null) return '--';
  return DateFormat.jm().format(value);
}

String titleCase(String value) {
  return value
      .replaceAll('_', ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

class EmployeeScaffold extends StatelessWidget {
  const EmployeeScaffold({
    super.key,
    required this.title,
    required this.selectedIndex,
    required this.child,
    this.showBack = false,
    this.actions,
  });

  final String title;
  final int selectedIndex;
  final Widget child;
  final bool showBack;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F8FA),
        elevation: 0,
        title: Text(
          title,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        leading: showBack
            ? IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.chevron_left),
              )
            : null,
        actions: actions,
      ),
      body: SafeArea(child: child),
      bottomNavigationBar: EmployeeBottomNav(selectedIndex: selectedIndex),
    );
  }
}

class EmployeeBottomNav extends StatelessWidget {
  const EmployeeBottomNav({super.key, required this.selectedIndex});

  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    final items = [
      const _NavItem(Icons.home_rounded, 'Home', '/home'),
      const _NavItem(
          Icons.assignment_rounded, 'Shift History', '/shift-history'),
      const _NavItem(Icons.face_retouching_natural, 'Scan', '/scan-attendance'),
      const _NavItem(Icons.payments_rounded, 'Payroll', '/payroll'),
      const _NavItem(Icons.person_rounded, 'Profile', '/profile'),
    ];

    return NavigationBar(
      selectedIndex: selectedIndex,
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
      onDestinationSelected: (index) => context.go(items[index].route),
      destinations: items
          .map(
            (item) => NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.icon),
              label: item.label,
            ),
          )
          .toList(),
    );
  }
}

class _NavItem {
  const _NavItem(this.icon, this.label, this.route);

  final IconData icon;
  final String label;
  final String route;
}

class EmployeeCard extends StatelessWidget {
  const EmployeeCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class EmployeeAvatar extends StatelessWidget {
  const EmployeeAvatar({
    super.key,
    required this.imageUrl,
    required this.name,
    this.size = 48,
    this.backgroundColor,
  });

  final String? imageUrl;
  final String name;
  final double size;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final bytes = dataUriBytes(imageUrl);
    final color = backgroundColor ?? const Color(0xFFE8D8BF);

    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: bytes != null
          ? Image.memory(bytes, fit: BoxFit.cover)
          : Icon(
              Icons.person_rounded,
              size: size * 0.58,
              color: const Color(0xFF6B7280),
            ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return EmployeeCard(
      child: Column(
        children: [
          Icon(
            Icons.info_outline,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            description,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

Widget loadingView() {
  return const Center(child: CircularProgressIndicator());
}

Widget errorView(Object? error) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'Unable to load employee data. Please try again.\n$error',
        textAlign: TextAlign.center,
      ),
    ),
  );
}

Color statusColor(String status) {
  final normalized = status.toLowerCase();
  if (normalized == 'late' ||
      normalized == 'incomplete' ||
      normalized == 'under_time' ||
      normalized == 'undertime') {
    return const Color(0xFFD97706);
  }
  if (normalized == 'overtime' || normalized == 'over_time') {
    return const Color(0xFF2563EB);
  }
  if (normalized == 'absent') return const Color(0xFFDC2626);
  if (normalized == 'complete' || normalized == 'on_time') {
    return const Color(0xFF16A34A);
  }
  return const Color(0xFF2563EB);
}

Color? _hexColor(String? value) {
  if (value == null || value.isEmpty) return null;
  final normalized = value.replaceFirst('#', '');
  if (normalized.length != 6) return null;
  final parsed = int.tryParse('FF$normalized', radix: 16);
  if (parsed == null) return null;
  return Color(parsed);
}

Uint8List? dataUriBytes(String? value) {
  if (value == null || !value.startsWith('data:image/')) return null;
  final commaIndex = value.indexOf(',');
  if (commaIndex < 0 || commaIndex == value.length - 1) return null;
  try {
    return base64Decode(value.substring(commaIndex + 1));
  } on FormatException {
    return null;
  }
}
