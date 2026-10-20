import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/utils/business_time.dart';
import 'package:aroll_mobile/core/theme/business_brand_theme.dart';
import 'package:aroll_mobile/core/utils/data_uri_image.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_progress_card.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:aroll_mobile/presentation/shared/tenant_mode_banner.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key, required this.session});

  final UserSession session;

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  String _period = 'week';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final repo = sl<OwnerRepository>();
    _future = Future.wait([
      repo.performance(period: _period),
      repo.setupStatus(),
      repo.accountSettings(),
    ]);
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  void _setPeriod(String period) {
    if (_period == period) return;
    setState(() {
      _period = period;
      _load();
    });
  }

  void _showStatusEvents({
    required String category,
    required String label,
    required List<Map<String, dynamic>> events,
  }) {
    final filtered = events
        .where((event) => '${event['category']}' == category)
        .toList();
    final timeZone = sl<AppState>().session?.timezone;
    final statusColor = _statusAccent(category);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: filtered.isEmpty ? 0.38 : 0.52,
          minChildSize: 0.32,
          maxChildSize: 0.88,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1D5DB),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 10, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(top: 5),
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$label Employees',
                                style: appSectionTitleStyle().copyWith(
                                  fontSize: 17,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                filtered.isEmpty
                                    ? 'No employees for this period'
                                    : '${filtered.length} record${filtered.length == 1 ? '' : 's'} · exact Time In / Time Out',
                                style: appMutedStyle().copyWith(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          tooltip: 'Close',
                          icon: const Icon(
                            Icons.close_rounded,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.border),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      color: AppColors.chipFill,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Icon(
                                      Icons.person_off_outlined,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No employees found for this period.',
                                    textAlign: TextAlign.center,
                                    style: appMutedStyle().copyWith(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final event = filtered[index];
                              final name =
                                  '${event['full_name'] ?? 'Employee'}';
                              final workDate = '${event['work_date'] ?? ''}';
                              final timeIn = formatBusinessAttendanceTimeIso(
                                event['time_in'] as String?,
                                timeZone: timeZone,
                                fallback: '—',
                              );
                              final timeOut = formatBusinessAttendanceTimeIso(
                                event['time_out'] as String?,
                                timeZone: timeZone,
                                fallback: '—',
                              );
                              return Container(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  12,
                                  14,
                                  12,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    if (workDate.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        workDate,
                                        style: appMutedStyle().copyWith(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _TimeDetail(
                                            label: 'Time In',
                                            value: timeIn,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: _TimeDetail(
                                            label: 'Time Out',
                                            value: timeOut,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Color _statusAccent(String category) {
    switch (category) {
      case 'on_time':
        return AppColors.success;
      case 'late':
        return AppColors.warning;
      case 'undertime':
        return const Color(0xFFEA580C);
      case 'overtime':
        return AppColors.primary;
      case 'absent':
        return AppColors.danger;
      default:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return OwnerShell(
      selectedIndex: 0,
      title: '',
      showLogoutButton: true,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return appLoadingView(cardCount: 4);
          }
          if (snapshot.hasError) {
            return OwnerErrorState(onRetry: _refresh);
          }
          final performance = snapshot.data![0];
          final setup = snapshot.data![1];
          final account = snapshot.data![2];
          final summary =
              performance['summary'] as Map<String, dynamic>? ?? const {};
          final events = (performance['events'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
          final ownerName = _ownerDisplayName(
            session: widget.session,
            account: account,
          );
          final logoUrl = _ownerLogoUrl(
            session: widget.session,
            account: account,
          );
          return RefreshIndicator(
            color: BrandColors.of(context).tonePrimary,
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                _DashboardHeader(
                  session: widget.session,
                  ownerName: ownerName,
                  logoUrl: logoUrl,
                ),
                if (widget.session.isDemo) ...[
                  const SizedBox(height: 10),
                  const PrototypeNoticeCard(),
                ],
                if (setup['setup_completed_at'] == null) ...[
                  const SizedBox(height: 16),
                  SetupProgressCard(data: setup),
                ],
                const SizedBox(height: 20),
                _SectionLabel(
                  title: widget.session.isDemo
                      ? 'Simulated attendance overview'
                      : 'Performance overview',
                  subtitle: widget.session.isDemo
                      ? 'Demo records only — not a real employee performance evaluation'
                      : 'Tap a bar to view employees for the selected period',
                ),
                const SizedBox(height: 10),
                _PeriodSelector(
                  period: _period,
                  onChanged: _setPeriod,
                ),
                const SizedBox(height: 12),
                _PerformanceOverviewCard(
                  summary: summary,
                  onBarTap: (category, label) => _showStatusEvents(
                    category: category,
                    label: label,
                    events: events,
                  ),
                ),
                const SizedBox(height: 20),
                const _SectionLabel(
                  title: 'Team insights',
                  subtitle: 'Attendance rate and punctuality',
                ),
                const SizedBox(height: 12),
                _InsightCards(summary: summary),
                const SizedBox(height: 20),
                const _SectionLabel(
                  title: 'Quick actions',
                  subtitle: 'Jump into everyday business tasks',
                ),
                const SizedBox(height: 12),
                _PrimaryActionCard(
                  title: 'Set Schedule',
                  subtitle: 'Assign shifts and plan the coming week',
                  icon: Icons.event_available_rounded,
                  gradient: [
                    BrandColors.of(context).tonePrimary,
                    BrandColors.of(context).toneSecondary,
                  ],
                  onTap: () => context.push('/owner/schedule'),
                ),
                const SizedBox(height: 10),
                _PrimaryActionCard(
                  title: 'Leave Management',
                  subtitle: 'Review pending leave requests',
                  icon: Icons.event_busy_rounded,
                  gradient: [
                    BrandColors.of(context).toneButton,
                    BrandColors.of(context).toneSidebar,
                  ],
                  onTap: () => context.push('/owner/leave'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _QuickActionTile(
                        label: 'Employees',
                        icon: Icons.groups_rounded,
                        onTap: () => context.push('/owner/employees'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _QuickActionTile(
                        label: 'Payroll',
                        icon: Icons.payments_outlined,
                        onTap: () => context.push('/owner/payroll'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _QuickActionTile(
                        label: 'Location',
                        icon: Icons.location_on_outlined,
                        onTap: () => context.push('/owner/location'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

String _ownerDisplayName({
  required UserSession session,
  required Map<String, dynamic> account,
}) {
  final fromAccount = '${account['owner_name'] ?? ''}'.trim();
  if (fromAccount.isNotEmpty) return fromAccount;

  final fromSession = session.fullName.trim();
  if (fromSession.isNotEmpty && !fromSession.contains('@')) {
    return fromSession;
  }

  final fromEmail = (session.email ?? '').trim();
  if (fromEmail.isNotEmpty) {
    final local = fromEmail.split('@').first.trim();
    if (local.isNotEmpty) return local;
  }
  return 'Business Owner';
}

String? _ownerLogoUrl({
  required UserSession session,
  required Map<String, dynamic> account,
}) {
  final branding = account['branding'];
  if (branding is Map) {
    final logo = '${branding['logo_url'] ?? ''}'.trim();
    if (logo.isNotEmpty) return logo;
  }
  final sessionLogo = session.branding?.logoUrl?.trim();
  if (sessionLogo != null && sessionLogo.isNotEmpty) return sessionLogo;
  return null;
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: appSectionTitleStyle()),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: appMutedStyle().copyWith(fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.session,
    required this.ownerName,
    this.logoUrl,
  });

  final UserSession session;
  final String ownerName;
  final String? logoUrl;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final business = session.businessName.trim();
    final resolvedLogoUrl = logoUrl?.trim();
    final logoBytes = dataUriBytes(resolvedLogoUrl);
    final networkLogo = resolvedLogoUrl != null &&
            resolvedLogoUrl.isNotEmpty &&
            logoBytes == null &&
            (resolvedLogoUrl.startsWith('http://') ||
                resolvedLogoUrl.startsWith('https://'))
        ? resolvedLogoUrl
        : null;
    final hasLogo = logoBytes != null || networkLogo != null;

    final brand = BrandColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 10, 16),
      decoration: BoxDecoration(
        gradient: brand.headerGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: brand.tonePrimary.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipOval(
            child: SizedBox(
              width: 56,
              height: 56,
              child: hasLogo
                  ? (logoBytes != null
                      ? Image.memory(
                          logoBytes,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                        )
                      : Image.network(
                          networkLogo!,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => ColoredBox(
                            color: brand.toneWell,
                            child: Icon(
                              Icons.storefront_rounded,
                              size: 26,
                              color: brand.tonePrimary,
                            ),
                          ),
                        ))
                  : ColoredBox(
                      color: brand.toneWell,
                      child: Icon(
                        Icons.storefront_rounded,
                        size: 26,
                        color: brand.tonePrimary,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  ownerName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Business Owner',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (business.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    business,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/owner/settings'),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
    );
  }
}

class _InsightCards extends StatelessWidget {
  const _InsightCards({required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final attendance =
        ownerParseInt(summary['attendance_rate']).clamp(0, 100);
    final punctuality =
        ownerParseInt(summary['punctuality_rate']).clamp(0, 100);

    return _InsightCard(
      title: 'Attendance',
      value: '$attendance%',
      caption: 'Punctuality $punctuality%',
      progress: attendance / 100,
      accent: AppColors.success,
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.title,
    required this.value,
    required this.caption,
    required this.progress,
    required this.accent,
  });

  final String title;
  final String value;
  final String caption;
  final double progress;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: appCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textBody,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: accent,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: appMutedStyle().copyWith(fontSize: 11),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.clamp(0, 1),
              minHeight: 4,
              backgroundColor: accent.withValues(alpha: 0.12),
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeDetail extends StatelessWidget {
  const _TimeDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: appMutedStyle().copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.period,
    required this.onChanged,
  });

  final String period;
  final ValueChanged<String> onChanged;

  static const _options = [
    ('week', 'Weekly'),
    ('month', 'Monthly'),
    ('year', 'Yearly'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.chipFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          for (final option in _options)
            Expanded(
              child: Material(
                color: period == option.$1
                    ? AppColors.white
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onChanged(option.$1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      option.$2,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: period == option.$1
                            ? BrandColors.of(context).tonePrimary
                            : AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PerformanceOverviewCard extends StatelessWidget {
  const _PerformanceOverviewCard({
    required this.summary,
    this.onBarTap,
  });

  final Map<String, dynamic> summary;
  final void Function(String category, String label)? onBarTap;

  @override
  Widget build(BuildContext context) {
    return OwnerOverviewBarChart(
      onTime: ownerParseInt(summary['on_time_clock_ins']),
      late: ownerParseInt(summary['late_clock_ins']),
      undertime: ownerParseInt(summary['undertime_shifts']),
      overtime: ownerParseInt(summary['overtime_shifts']),
      absent: ownerParseInt(summary['absent_shifts']),
      onBarTap: onBarTap,
    );
  }
}

class _PrimaryActionCard extends StatelessWidget {
  const _PrimaryActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.gradient = const [AppColors.primary, AppColors.primaryDark],
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final List<Color> gradient;

  @override
  Widget build(BuildContext context) {
    final shadowColor = gradient.last;
    return AppPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: gradient,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: shadowColor.withValues(alpha: 0.2),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_rounded,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: appCardShadow,
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: BrandColors.of(context).toneWell,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: BrandColors.of(context).tonePrimary,
                size: 22,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textBody,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
