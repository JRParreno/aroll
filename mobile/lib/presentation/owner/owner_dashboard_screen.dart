import 'package:aroll_mobile/core/di/injection.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final repo = sl<OwnerRepository>();
    _future = Future.wait([
      repo.performance(),
      repo.setupStatus(),
      repo.accountSettings(),
    ]);
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return OwnerShell(
      selectedIndex: 0,
      title: '',
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
          final ownerName = _ownerDisplayName(
            session: widget.session,
            account: account,
          );
          final logoUrl = _ownerLogoUrl(
            session: widget.session,
            account: account,
          );
          return RefreshIndicator(
            color: AppColors.primaryDark,
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
                      : 'Attendance breakdown across recent shifts',
                ),
                const SizedBox(height: 12),
                _PerformanceOverviewCard(summary: summary),
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
                  gradient: const [
                    AppColors.primary,
                    AppColors.primaryDark,
                  ],
                  onTap: () => context.push('/owner/schedule'),
                ),
                const SizedBox(height: 10),
                _PrimaryActionCard(
                  title: 'Leave Management',
                  subtitle: 'Review pending leave requests',
                  icon: Icons.event_busy_rounded,
                  gradient: const [
                    Color(0xFF3B6D96),
                    Color(0xFF2A5680),
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

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 10, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            AppColors.primaryDark,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.35),
                width: 2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
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
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.storefront_rounded,
                          size: 26,
                          color: AppColors.primary,
                        ),
                      ))
                : const Icon(
                    Icons.storefront_rounded,
                    size: 26,
                    color: AppColors.primary,
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

class _PerformanceOverviewCard extends StatelessWidget {
  const _PerformanceOverviewCard({required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    return OwnerOverviewBarChart(
      onTime: ownerParseInt(summary['on_time_clock_ins']),
      late: ownerParseInt(summary['late_clock_ins']),
      undertime: ownerParseInt(summary['undertime_shifts']),
      overtime: ownerParseInt(summary['overtime_shifts']),
      absent: ownerParseInt(summary['absent_shifts']),
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
                color: AppColors.iconWell,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColors.primary, size: 22),
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
