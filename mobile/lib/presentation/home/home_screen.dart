import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/theme/business_brand_theme.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session});

  final UserSession session;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late Future<EmployeeDashboard> _future;
  int _unread = 0;

  static const double _sectionGap = 14.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = sl<EmployeeRepository>().getDashboard().then(_applyDashboard);
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

  EmployeeDashboard _applyDashboard(EmployeeDashboard dashboard) {
    final appState = sl<AppState>();
    appState.updateEmployeeProfileImage(dashboard.profile.profileImageUrl);
    appState.updateBusinessBranding(dashboard.profile.branding);
    return dashboard;
  }

  Future<void> _refresh() async {
    setState(() {
      _future = sl<EmployeeRepository>().getDashboard().then(_applyDashboard);
    });
    await _future;
    await _refreshUnread();
  }

  Future<void> _refreshUnread() async {
    try {
      final count = await sl<EmployeeRepository>().unreadNotificationCount();
      if (mounted) setState(() => _unread = count);
    } catch (_) {}
  }

  Future<void> _confirmLogout(BuildContext context) async {
    await confirmEmployeeSignOut(context);
  }

  void _openAttendance(EmployeeDashboard data) {
    final assignmentId = data.todaySchedule?.assignmentId;
    if (assignmentId != null) {
      context.go('/scan-attendance?shift_assignment_id=$assignmentId');
    } else {
      context.go('/scan-attendance');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EmployeeDashboard>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return EmployeeScaffold(
          title: '',
          selectedIndex: 0,
          showBack: false,
          actions: [
            IconButton(
              tooltip: 'Notifications',
              onPressed: () async {
                await context.push('/notifications');
                if (mounted) await _refreshUnread();
              },
              icon: Badge(
                isLabelVisible: _unread > 0,
                label: Text(_unread > 99 ? '99+' : '$_unread'),
                child: const Icon(Icons.notifications_outlined),
              ),
            ),
            IconButton(
              tooltip: 'Log out',
              onPressed: () => _confirmLogout(context),
              icon: const Icon(Icons.logout_rounded),
            ),
          ],
          child: snapshot.connectionState == ConnectionState.waiting
              ? loadingView()
              : snapshot.hasError
                  ? errorView(snapshot.error)
                  : data == null
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: EmptyState(
                            title: 'Unable to load dashboard',
                            description: 'Please refresh or sign in again.',
                          ),
                        )
                      : RefreshIndicator(
                          color: employeePrimary(data.profile.branding, context),
                          onRefresh: _refresh,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                            children: [
                              _DashboardHeader(profile: data.profile),
                              if (data.incompleteAttendanceReminder?.show ==
                                  true) ...[
                                const SizedBox(height: _sectionGap),
                                _IncompleteAttendanceBanner(
                                  message: data
                                      .incompleteAttendanceReminder!.message,
                                  onFix: () {
                                    final reminder =
                                        data.incompleteAttendanceReminder!;
                                    final params = <String, String>{};
                                    final attendanceId =
                                        reminder.attendanceRecordId?.trim();
                                    final assignmentId =
                                        reminder.shiftAssignmentId?.trim();
                                    if (attendanceId != null &&
                                        attendanceId.isNotEmpty) {
                                      params['attendance_record_id'] =
                                          attendanceId;
                                    }
                                    if (assignmentId != null &&
                                        assignmentId.isNotEmpty) {
                                      params['shift_assignment_id'] =
                                          assignmentId;
                                    }
                                    final query = params.entries
                                        .map(
                                          (entry) =>
                                              '${entry.key}=${Uri.encodeQueryComponent(entry.value)}',
                                        )
                                        .join('&');
                                    context.go(
                                      query.isEmpty
                                          ? '/shift-history'
                                          : '/shift-history?$query',
                                    );
                                  },
                                ),
                              ],
                              const SizedBox(height: _sectionGap),
                              _AttendanceStatusCard(
                                status: data.attendanceStatus,
                              ),
                              const SizedBox(height: _sectionGap),
                              _ScheduleHero(
                                item: data.todaySchedule,
                                data: data,
                              ),
                              const SizedBox(height: 10),
                              _LeaveActionCard(
                                accent: employeePrimary(
                                  data.profile.branding,
                                  context,
                                ),
                                onTap: () => context.push('/leave-requests'),
                              ),
                              const SizedBox(height: 18),
                              const _SectionLabel(
                                title: 'Quick actions',
                                subtitle: 'Time in or check your current pay',
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _QuickActionCard(
                                      icon: Icons.center_focus_strong_rounded,
                                      label: ' Attendance',
                                      helper: 'Face & GPS check',
                                      accent: employeePrimary(
                                        data.profile.branding,
                                        context,
                                      ),
                                      onTap: () => _openAttendance(data),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _SalaryCard(
                                      value: data.payrollSummary.netPay,
                                      onTap: () => context.go('/payroll'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              const _SectionLabel(
                                title: 'Your performance',
                                subtitle:
                                    'Attendance breakdown from recent shifts',
                              ),
                              const SizedBox(height: 10),
                              EmployeePerformanceChart(
                                onTime: data.performance.onTime,
                                late: data.performance.late,
                                undertime: data.performance.undertime,
                                overtime: data.performance.overtime,
                                absent: data.performance.absent,
                                hasData: data.performance.hasData,
                              ),
                            ],
                          ),
                        ),
        );
      },
    );
  }
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
            ),
          ),
        ],
      ],
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.profile});

  final EmployeeProfile profile;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final businessName = profile.businessName.trim();
    final appState = sl<AppState>();
    final brand = BrandColors.of(context);
    final primary = employeePrimary(profile.branding, context);

    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final avatarUrl = appState.resolveEmployeeAvatarUrl(
          profile.profileImageUrl,
        );
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
          decoration: BoxDecoration(
            gradient: brand.headerGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: primary.withValues(alpha: 0.22),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.85),
                    width: 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: EmployeeAvatar(
                  imageUrl: avatarUrl,
                  name: profile.fullName,
                  size: 53,
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
                      profile.fullName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      businessName.isNotEmpty ? businessName : 'Employee',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: BusinessLogo(
                  logoUrl: profile.branding?.logoUrl,
                  height: 46,
                  width: 46,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AttendanceStatusCard extends StatelessWidget {
  const _AttendanceStatusCard({required this.status});

  final EmployeeAttendanceStatus status;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status.status);
    final label = switch (status.status) {
      'not_started' => 'Not clocked in yet',
      'in_progress' => 'Clocked in',
      'completed' => 'Shift completed',
      'on_leave' => 'On Leave',
      _ => titleCase(status.status),
    };

    return EmployeeCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.fact_check_rounded, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Today’s attendance',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: EmployeeColors.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: EmployeeColors.textPrimary,
                  ),
                ),
                if (status.timeIn != null)
                  Text(
                    status.timeOut != null
                        ? 'In ${timeOnly(status.timeIn)} · Out ${timeOnly(status.timeOut)}'
                        : 'Time in ${timeOnly(status.timeIn)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: EmployeeColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              titleCase(status.status),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleHero extends StatelessWidget {
  const _ScheduleHero({required this.item, required this.data});

  final EmployeeScheduleItem? item;
  final EmployeeDashboard data;

  @override
  Widget build(BuildContext context) {
    final brand = BrandColors.of(context);
    final primary = employeePrimary(data.profile.branding, context);
    final hasShift = item != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.go('/schedule'),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 18, 12, 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                primary.withValues(alpha: 0.95),
                Color.lerp(primary, brand.secondary, 0.4) ?? brand.secondary,
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: primary.withValues(alpha: 0.18),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                height: 64,
                width: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.85),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My Schedule',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasShift ? item!.shiftName : 'No shift today',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasShift
                          ? '${item!.startLabel} – ${item!.endLabel}'
                          : 'Tap to view your full schedule',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.9),
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeaveActionCard extends StatelessWidget {
  const _LeaveActionCard({
    required this.accent,
    required this.onTap,
  });

  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final soft = Color.lerp(accent, Colors.white, 0.22) ?? accent;
    final mid = Color.lerp(accent, soft, 0.35) ?? soft;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [soft, mid],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.18),
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
                child: const Icon(
                  Icons.event_busy_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Leave Requests',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Request time off and track approval status',
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
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.helper,
    required this.onTap,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String helper;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.14)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 36,
                width: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent.withValues(alpha: 0.16),
                      accent.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  height: 1.2,
                  color: EmployeeColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                helper,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: EmployeeColors.textMuted,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SalaryCard extends StatelessWidget {
  const _SalaryCard({required this.value, required this.onTap});

  final double value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = BrandColors.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: brand.primary.withValues(alpha: 0.14)),
            boxShadow: [
              BoxShadow(
                color: brand.primary.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 36,
                width: double.infinity,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    money(value),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: EmployeeColors.success,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Current Salary',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  height: 1.2,
                  color: EmployeeColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'View payslip',
                maxLines: 1,
                style: TextStyle(
                  color: EmployeeColors.textMuted,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IncompleteAttendanceBanner extends StatelessWidget {
  const _IncompleteAttendanceBanner({
    required this.message,
    required this.onFix,
  });

  final String message;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final lines = message
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final lineOne = lines.isNotEmpty
        ? lines.first
        : 'You forgot to time out.';
    final lineTwo = lines.length > 1
        ? lines.sublist(1).join(' ')
        : 'Please submit your correct time-out time.';

    return Material(
      color: const Color(0xFFFFFBEB),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onFix,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.55),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFD97706),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lineOne,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF92400E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lineTwo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Fix',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: BrandColors.of(context).primary,
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: BrandColors.of(context).primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
