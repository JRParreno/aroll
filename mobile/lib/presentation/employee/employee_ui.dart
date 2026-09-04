import 'dart:math' as math;

import 'package:aroll_mobile/core/theme/business_brand_theme.dart';
import 'package:aroll_mobile/core/utils/data_uri_image.dart';
import 'package:aroll_mobile/core/utils/format.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/presentation/auth/sign_out_dialog.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:aroll_mobile/presentation/shared/tenant_mode_banner.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// Shared visual tokens. Brand accents should prefer [BrandColors.of].
abstract final class EmployeeColors {
  static const scaffold = AppColors.scaffold;
  static const primary = AppColors.primary;
  static const primaryDark = AppColors.primaryDark;
  static const border = AppColors.border;
  static const textPrimary = AppColors.textPrimary;
  static const textBody = AppColors.textBody;
  static const textMuted = AppColors.textMuted;
  static const iconWell = AppColors.iconWell;
  static const fieldFill = AppColors.fieldFill;
  static const chipFill = AppColors.chipFill;
  static const success = AppColors.success;
}

/// Owner setup primary color from the active [Theme] (session branding).
Color brandPrimary(BuildContext context) => BrandColors.of(context).primary;

Color brandSecondary(BuildContext context) => BrandColors.of(context).secondary;

Color brandButton(BuildContext context) => BrandColors.of(context).button;

Color brandAccent(BuildContext context) => BrandColors.of(context).accent;

Color brandIconWell(BuildContext context) => BrandColors.of(context).iconWell;

/// Resolves branding primary, preferring live theme then optional profile branding.
Color employeePrimary(
  BusinessBrandingSettings? branding,
  BuildContext context,
) {
  final fromBranding = parseBrandHex(branding?.theme.primaryColor);
  if (fromBranding != null) return fromBranding;
  return BrandColors.of(context).primary;
}

String money(num value) => formatPeso(value);

String salaryRateRowLabel() => salaryRateLabel();

/// Salary rate label from payslip / payroll summary pay_basis fields.
String salaryRateDisplay({
  required String payBasis,
  required num dailyRate,
  num? hourlyRate,
  num? monthlySalary,
}) {
  return formatSalaryRate(
    payBasis: payBasis,
    dailyRate: dailyRate,
    hourlyRate: hourlyRate,
    monthlySalary: monthlySalary,
  );
}

String salaryRateDisplayFromPayslip(EmployeePayslip payslip) {
  return salaryRateDisplay(
    payBasis: payslip.payBasis,
    dailyRate: payslip.dailyRate,
    hourlyRate: payslip.hourlyRate,
    monthlySalary: payslip.monthlySalary,
  );
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

Future<void> confirmEmployeeSignOut(BuildContext context) =>
    confirmSignOut(context);

void employeeNavigateBack(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/home');
  }
}

/// Standard page header title — matches the Profile [AppBar] title.
TextStyle employeePageTitleStyle([Color? color]) => appPageTitleStyle(color);

class EmployeePageTitle extends StatelessWidget {
  const EmployeePageTitle(
    this.text, {
    super.key,
    this.color,
  });

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      overflow: TextOverflow.ellipsis,
      style: employeePageTitleStyle(color),
    );
  }
}

class EmployeeScaffold extends StatelessWidget {
  const EmployeeScaffold({
    super.key,
    required this.title,
    required this.selectedIndex,
    required this.child,
    this.showBack = true,
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
        automaticallyImplyLeading: false,
        titleSpacing: showBack ? 0 : NavigationToolbar.kMiddleSpacing,
        title: EmployeePageTitle(title),
        centerTitle: false,
        leading: showBack
            ? IconButton(
                tooltip: 'Back',
                constraints: const BoxConstraints(
                  minWidth: AppSizes.minTap,
                  minHeight: AppSizes.minTap,
                ),
                onPressed: () => employeeNavigateBack(context),
                icon: const Icon(Icons.arrow_back_rounded, size: AppSizes.iconLg),
              )
            : null,
        actions: actions,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const TenantModeBanner(),
            Expanded(child: child),
          ],
        ),
      ),
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
      const _NavItem(Icons.home_outlined, Icons.home_rounded, 'Home', '/home'),
      const _NavItem(
        Icons.history_outlined,
        Icons.history_rounded,
        'Shift History',
        '/shift-history',
      ),
      const _NavItem(
        Icons.face_retouching_natural_outlined,
        Icons.face_retouching_natural,
        'Scan',
        '/scan-attendance',
      ),
      const _NavItem(
        Icons.payments_outlined,
        Icons.payments_rounded,
        'Payroll',
        '/payroll',
      ),
      const _NavItem(
        Icons.person_outline_rounded,
        Icons.person_rounded,
        'Profile',
        '/profile',
      ),
    ];

    final brand = BrandColors.of(context);
    return Material(
      color: Colors.white,
      elevation: 0,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: EmployeeColors.border),
          ),
        ),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          height: AppSizes.navHeight,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          indicatorColor: brand.iconWell,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
          onDestinationSelected: (index) => context.go(items[index].route),
          destinations: [
            for (var i = 0; i < items.length; i++)
              NavigationDestination(
                icon: Icon(
                  items[i].icon,
                  size: i == 2 ? AppSizes.iconXl : AppSizes.iconLg,
                  color: EmployeeColors.textBody,
                ),
                selectedIcon: Icon(
                  items[i].selectedIcon,
                  size: i == 2 ? AppSizes.iconXl : AppSizes.iconLg,
                  color: brand.primary,
                ),
                label: items[i].label,
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.icon, this.selectedIcon, this.label, this.route);

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String route;
}

class EmployeeCard extends StatelessWidget {
  const EmployeeCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.margin,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets? margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: padding,
      margin: margin,
      onTap: onTap,
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
    final brand = BrandColors.of(context);
    return AppPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: prominent ? brand.primary : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: BorderSide(
            color: EmployeeColors.border.withValues(alpha: prominent ? 0 : 1),
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.all(14),
          leading: CircleAvatar(
            backgroundColor: prominent ? Colors.white24 : brand.iconWell,
            child: Icon(
              icon,
              size: AppSizes.iconLg,
              color: prominent ? Colors.white : brand.primary,
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
        ),
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
    return AppPrimaryButton(
      label: label,
      onPressed: onPressed == null
          ? null
          : () {
              appLightHaptic();
              onPressed!();
            },
      loading: loading,
      icon: icon,
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
    return AppOutlinedButton(
      label: label,
      onPressed: onPressed,
      icon: icon,
    );
  }
}

InputDecoration employeeInputDecoration(
  BuildContext context, {
  String? hintText,
  String? labelText,
  Widget? prefixIcon,
}) {
  return appBrandedInputDecoration(
    context,
    hintText: hintText,
    labelText: labelText,
    prefixIcon: prefixIcon,
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
    case 'on_leave':
      return (label: 'On Leave', color: const Color(0xFF2563EB));
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
      return 'Incomplete Attendance – Time Out Missing';
    case 'on_leave':
      return 'On Leave';
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
    return AppEmptyState(
      title: title,
      description: description,
      icon: icon,
      inCard: inCard,
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

Widget loadingView() => appLoadingView();

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

    final size = math.min(height, width);
    final bytes = dataUriBytes(logoUrl);
    Widget? image;
    if (bytes != null) {
      image = Image.memory(
        bytes,
        height: size,
        width: size,
        fit: BoxFit.cover,
      );
    } else if (logoUrl!.startsWith('http')) {
      image = Image.network(
        logoUrl!,
        height: size,
        width: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }

    if (image == null) return const SizedBox.shrink();

    return ClipOval(
      child: SizedBox(
        height: size,
        width: size,
        child: image,
      ),
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
    final color = backgroundColor ?? BrandColors.of(context).iconWell;
    final networkUrl = (imageUrl != null &&
            imageUrl!.trim().isNotEmpty &&
            bytes == null &&
            (imageUrl!.startsWith('http://') ||
                imageUrl!.startsWith('https://')))
        ? imageUrl!.trim()
        : null;

    Widget imageChild;
    if (bytes != null) {
      imageChild = Image.memory(
        bytes,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );
    } else if (networkUrl != null) {
      imageChild = Image.network(
        networkUrl,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => _AvatarPlaceholder(size: size),
      );
    } else {
      imageChild = _AvatarPlaceholder(size: size);
    }

    return SizedBox(
      height: size,
      width: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipOval(
            child: ColoredBox(
              color: color,
              child: SizedBox.expand(child: imageChild),
            ),
          ),
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.fromBorderSide(
                  BorderSide(color: Colors.white, width: 2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
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
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 128,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: values
                  .map(
                    (entry) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              '${entry.$2}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: EmployeeColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height: entry.$2 > 0
                                  ? math.max(10, 78 * entry.$2 / maxValue)
                                  : 4,
                              decoration: BoxDecoration(
                                color: entry.$2 > 0
                                    ? entry.$3
                                    : EmployeeColors.chipFill,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              entry.$1,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: EmployeeColors.textMuted,
                                height: 1.15,
                              ),
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
                'Charts will update once you start timing in.',
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

