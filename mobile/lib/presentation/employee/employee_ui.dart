import 'dart:math' as math;

import 'package:aroll_mobile/core/utils/data_uri_image.dart';
import 'package:aroll_mobile/core/utils/format.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/presentation/auth/sign_out_dialog.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// Shared visual tokens aligned with the Business Owner mobile app.
abstract final class EmployeeColors {
  static const scaffold = Color(0xFFF4F6F8);
  static const primary = Color(0xFF1E466E);
  static const primaryDark = Color(0xFF1E3A5F);
  static const border = Color(0xFFE5E7EB);
  static const textPrimary = Color(0xFF111827);
  static const textBody = Color(0xFF374151);
  static const textMuted = Color(0xFF6B7280);
  static const iconWell = Color(0xFFE7EEF5);
  static const fieldFill = Color(0xFFF9FAFB);
  static const chipFill = Color(0xFFF3F4F6);
  static const success = Color(0xFF16A34A);
}

Color employeePrimary(
    BusinessBrandingSettings? branding, BuildContext context) {
  return _hexColor(branding?.theme.primaryColor) ??
      EmployeeColors.primary;
}

String money(num value) => formatPeso(value);

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

Future<void> confirmEmployeeSignOut(BuildContext context) =>
    confirmSignOut(context);

void employeeNavigateBack(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/home');
  }
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
      backgroundColor: EmployeeColors.scaffold,
      appBar: AppBar(
        backgroundColor: EmployeeColors.scaffold,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          title,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: false,
        leading: showBack
            ? IconButton(
                tooltip: 'Back',
                onPressed: () => employeeNavigateBack(context),
                icon: const Icon(Icons.arrow_back_rounded),
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
      const _NavItem(Icons.calendar_month_rounded, 'Schedule', '/schedule'),
      const _NavItem(Icons.face_retouching_natural, 'Scan', '/scan-attendance'),
      const _NavItem(Icons.payments_rounded, 'Payroll', '/payroll'),
      const _NavItem(Icons.person_rounded, 'Profile', '/profile'),
    ];

    return NavigationBar(
      selectedIndex: selectedIndex,
      height: 70,
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
    this.margin,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EmployeeColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: child,
    );
  }
}

class EmployeeActionCard extends StatelessWidget {
  const EmployeeActionCard({
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
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: prominent ? EmployeeColors.primary : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: EmployeeColors.border.withValues(alpha: prominent ? 0 : 1)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(14),
        leading: CircleAvatar(
          backgroundColor:
              prominent ? Colors.white24 : EmployeeColors.iconWell,
          child: Icon(
            icon,
            color: prominent ? Colors.white : EmployeeColors.primary,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: prominent ? Colors.white : EmployeeColors.textPrimary,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: prominent ? Colors.white70 : EmployeeColors.textMuted,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: prominent ? Colors.white : EmployeeColors.textMuted,
        ),
        onTap: onTap,
      ),
    );
  }
}

class EmployeePrimaryButton extends StatelessWidget {
  const EmployeePrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: EmployeeColors.primaryDark,
          foregroundColor: Colors.white,
          disabledBackgroundColor:
              EmployeeColors.primaryDark.withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  if (icon != null) ...[
                    const SizedBox(width: 8),
                    Icon(icon, size: 18),
                  ],
                ],
              ),
      ),
    );
  }
}

class EmployeeOutlinedButton extends StatelessWidget {
  const EmployeeOutlinedButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon ?? Icons.logout_rounded, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: EmployeeColors.textBody,
          side: const BorderSide(color: EmployeeColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

InputDecoration employeeInputDecoration({
  String? hintText,
  String? labelText,
  Widget? prefixIcon,
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: EmployeeColors.border),
  );
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    prefixIcon: prefixIcon,
    filled: true,
    fillColor: EmployeeColors.fieldFill,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: const BorderSide(color: EmployeeColors.primaryDark, width: 1.5),
    ),
  );
}

class EmployeeSectionTitle extends StatelessWidget {
  const EmployeeSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: EmployeeColors.textPrimary,
          ),
    );
  }
}

class EmployeeDetailField extends StatelessWidget {
  const EmployeeDetailField({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: EmployeeColors.textBody,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: EmployeeColors.fieldFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: EmployeeColors.border),
            ),
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: EmployeeColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EmployeeStatusChip extends StatelessWidget {
  const EmployeeStatusChip({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

({String label, Color color}) employeeScheduleStatusStyle(String status) {
  switch (status) {
    case 'today':
      return (label: 'Today', color: const Color(0xFF2563EB));
    case 'completed':
      return (label: 'Completed', color: const Color(0xFF16A34A));
    default:
      return (label: 'Upcoming', color: const Color(0xFF6B7280));
  }
}

String employeeAttendanceHistoryLabel(String status) {
  switch (status.toLowerCase()) {
    case 'complete':
      return 'Present';
    case 'late':
      return 'Late';
    case 'absent':
      return 'Absent';
    case 'in_progress':
      return 'In Progress';
    case 'incomplete':
      return 'Incomplete';
    default:
      return titleCase(status);
  }
}

class EmployeeCoworkerStrip extends StatelessWidget {
  const EmployeeCoworkerStrip({
    super.key,
    required this.coworkers,
    this.maxVisible = 4,
    this.onShowAll,
  });

  final List<EmployeeCoworker> coworkers;
  final int maxVisible;
  final VoidCallback? onShowAll;

  List<EmployeeCoworker> get _others =>
      coworkers.where((coworker) => !coworker.isCurrentEmployee).toList();

  @override
  Widget build(BuildContext context) {
    final others = _others;
    if (others.isEmpty) {
      return const Text(
        'No coworkers assigned for this shift yet.',
        style: TextStyle(
          color: EmployeeColors.textMuted,
          fontSize: 12,
          height: 1.35,
        ),
      );
    }

    final visible = others.take(maxVisible).toList();
    final remaining = others.length - visible.length;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onShowAll ?? () => _showCoworkerSheet(context, others),
      child: Row(
        children: [
          for (var i = 0; i < visible.length; i++)
            Transform.translate(
              offset: Offset(i == 0 ? 0 : -10.0 * i, 0),
              child: EmployeeAvatar(
                imageUrl: visible[i].profileImageUrl,
                name: visible[i].fullName,
                size: 34,
              ),
            ),
          if (remaining > 0) ...[
            const SizedBox(width: 6),
            Container(
              height: 34,
              width: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: EmployeeColors.chipFill,
                shape: BoxShape.circle,
                border: Border.all(color: EmployeeColors.border),
              ),
              child: Text(
                '+$remaining',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: EmployeeColors.textBody,
                ),
              ),
            ),
          ],
          const Spacer(),
          Text(
            '${others.length} coworker${others.length == 1 ? '' : 's'}',
            style: const TextStyle(
              fontSize: 12,
              color: EmployeeColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: EmployeeColors.textMuted,
          ),
        ],
      ),
    );
  }

  void _showCoworkerSheet(
    BuildContext context,
    List<EmployeeCoworker> coworkers,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Working with',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                ...coworkers.map(
                  (coworker) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        EmployeeAvatar(
                          imageUrl: coworker.profileImageUrl,
                          name: coworker.fullName,
                          size: 40,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            coworker.fullName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class EmployeeSectionHeader extends StatelessWidget {
  const EmployeeSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: EmployeeColors.textPrimary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 12,
                color: EmployeeColors.textMuted,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class EmployeeInfoRow extends StatelessWidget {
  const EmployeeInfoRow({
    super.key,
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: EmployeeColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: EmployeeColors.textBody,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EmployeeEmptyState extends StatelessWidget {
  const EmployeeEmptyState({
    super.key,
    required this.title,
    required this.description,
    this.icon = Icons.inbox_outlined,
    this.inCard = false,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool inCard;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 44, color: EmployeeColors.textMuted),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          description,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: EmployeeColors.textMuted,
                height: 1.4,
              ),
        ),
      ],
    );

    if (inCard) {
      return EmployeeCard(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        child: content,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Center(child: content),
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
    return EmployeeEmptyState(
      title: title,
      description: description,
      inCard: true,
    );
  }
}

class EmployeeErrorState extends StatelessWidget {
  const EmployeeErrorState({
    super.key,
    this.message = 'Unable to load employee data. Please try again.',
    this.onRetry,
  });

  final String message;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 40, color: EmployeeColors.textMuted),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: EmployeeColors.textBody),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

Widget loadingView() {
  return const Center(child: CircularProgressIndicator());
}

Widget errorView(Object? error, {Future<void> Function()? onRetry}) {
  return EmployeeErrorState(
    message: 'Unable to load employee data. Please try again.\n$error',
    onRetry: onRetry,
  );
}

class BusinessLogo extends StatelessWidget {
  const BusinessLogo({
    super.key,
    required this.logoUrl,
    this.height = 40,
    this.width = 40,
  });

  final String? logoUrl;
  final double height;
  final double width;

  @override
  Widget build(BuildContext context) {
    if (logoUrl == null || logoUrl!.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final bytes = dataUriBytes(logoUrl);
    if (bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          bytes,
          height: height,
          width: width,
          fit: BoxFit.contain,
        ),
      );
    }

    if (logoUrl!.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          logoUrl!,
          height: height,
          width: width,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      );
    }

    return const SizedBox.shrink();
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
    final color = backgroundColor ?? EmployeeColors.iconWell;

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
              color: EmployeeColors.textMuted,
            ),
    );
  }
}

class EmployeePerformanceChart extends StatelessWidget {
  const EmployeePerformanceChart({
    super.key,
    required this.onTime,
    required this.late,
    required this.undertime,
    required this.overtime,
    required this.absent,
    required this.hasData,
  });

  final int onTime;
  final int late;
  final int undertime;
  final int overtime;
  final int absent;
  final bool hasData;

  @override
  Widget build(BuildContext context) {
    final values = [
      ('On Time', onTime, const Color(0xFF22C55E)),
      ('Late', late, const Color(0xFFF59E0B)),
      ('Under Time', undertime, const Color(0xFFF97316)),
      ('Over Time', overtime, const Color(0xFF3B82F6)),
      ('Absent', absent, const Color(0xFFEF4444)),
    ];
    final maxValue = math.max(
      1,
      values.map((entry) => entry.$2).fold(0, math.max),
    );

    return EmployeeCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Performance Overview',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 2),
          const Text(
            'Live attendance and shift activity.',
            style: TextStyle(color: EmployeeColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
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
                              height: entry.$2 > 0
                                  ? math.max(8, 72 * entry.$2 / maxValue)
                                  : 0,
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
          if (!hasData) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: EmployeeColors.fieldFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: EmployeeColors.border),
              ),
              child: const Text(
                'No attendance records yet.\n'
                'Charts will automatically update once you start clocking in.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: EmployeeColors.textMuted,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
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
    return EmployeeColors.success;
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
