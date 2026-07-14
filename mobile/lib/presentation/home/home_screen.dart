import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
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

class _HomeScreenState extends State<HomeScreen> {
  late Future<EmployeeDashboard> _future;

  static const double _actionCardHeight = 144;
  static const double _sectionGap = 14.0;

  @override
  void initState() {
    super.initState();
    _future = sl<EmployeeRepository>().getDashboard().then((dashboard) {
      sl<AppState>().updateEmployeeProfileImage(
        dashboard.profile.profileImageUrl,
      );
      return dashboard;
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _future = sl<EmployeeRepository>().getDashboard().then((dashboard) {
        sl<AppState>().updateEmployeeProfileImage(
          dashboard.profile.profileImageUrl,
        );
        return dashboard;
      });
    });
    await _future;
  }

  Future<void> _confirmLogout(BuildContext context) async {
    await confirmEmployeeSignOut(context);
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
          actions: [
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
                          onRefresh: _refresh,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            children: [
                              _DashboardHeader(profile: data.profile),
                              const SizedBox(height: _sectionGap),
                              _ScheduleHero(
                                  item: data.todaySchedule, data: data),
                              const SizedBox(height: _sectionGap),
                              SizedBox(
                                height: _actionCardHeight,
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: _QuickActionCard(
                                        icon: Icons.center_focus_strong_rounded,
                                        label: 'Clock Attendance',
                                        helper: 'GPS check',
                                        onTap: () {
                                          final assignmentId =
                                              data.todaySchedule?.assignmentId;
                                          if (assignmentId != null) {
                                            context.go(
                                              '/scan-attendance?shift_assignment_id=$assignmentId',
                                            );
                                          } else {
                                            context.go('/scan-attendance');
                                          }
                                        },
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
                              ),
                              const SizedBox(height: _sectionGap),
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

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.profile});

  final EmployeeProfile profile;

  @override
  Widget build(BuildContext context) {
    final businessName = profile.businessName.trim();
    final appState = sl<AppState>();

    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final avatarUrl = appState.resolveEmployeeAvatarUrl(
          profile.profileImageUrl,
        );
        return Row(
          children: [
            EmployeeAvatar(
              imageUrl: avatarUrl,
              name: profile.fullName,
              size: 62,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    businessName.isNotEmpty ? businessName : 'Welcome back',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: const Color(0xFF6B7280),
                        ),
                  ),
                  Text(
                    profile.fullName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
            BusinessLogo(
              logoUrl: profile.branding?.logoUrl,
              height: 44,
              width: 44,
            ),
          ],
        );
      },
    );
  }
}

class _ScheduleHero extends StatelessWidget {
  const _ScheduleHero({required this.item, required this.data});

  final EmployeeScheduleItem? item;
  final EmployeeDashboard data;

  @override
  Widget build(BuildContext context) {
    final primary = employeePrimary(data.profile.branding, context);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => context.go('/schedule'),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 132),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: primary.withValues(alpha: 0.16),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              height: 80,
              width: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.18),
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: const Icon(
                Icons.calendar_month_rounded,
                color: Colors.white,
                size: 38,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'My Schedule',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 22,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item == null
                        ? 'No assigned shift today · Tap to view all'
                        : '${item!.shiftName} - ${item!.startLabel} to ${item!.endLabel}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white, size: 28),
          ],
        ),
      ),
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
      _ => titleCase(status.status),
    };

    return EmployeeCard(
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.fact_check_rounded, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Attendance Status',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (status.timeIn != null)
                  Text(
                    'Time in: ${timeOnly(status.timeIn)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
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
  });

  final IconData icon;
  final String label;
  final String helper;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: EmployeeCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 64,
              width: 64,
              decoration: BoxDecoration(
                color: EmployeeColors.iconWell,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 32,
                color: EmployeeColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              helper,
              maxLines: 1,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF6B7280),
                    fontSize: 10,
                  ),
            ),
          ],
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
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: EmployeeCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 64,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    money(value),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: EmployeeColors.success,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Current Salary',
              textAlign: TextAlign.center,
              maxLines: 2,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              'Tap to view',
              maxLines: 1,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF6B7280),
                    fontSize: 10,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardLink extends StatelessWidget {
  const _DashboardLink({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: EmployeeCard(
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}
