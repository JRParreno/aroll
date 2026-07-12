import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/domain/usecase/auth/logout_usecase.dart';
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
  static const double _sectionGap = 10.0;

  @override
  void initState() {
    super.initState();
    _future = sl<EmployeeRepository>().getDashboard();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = sl<EmployeeRepository>().getDashboard();
    });
    await _future;
  }

  Future<void> _logout(BuildContext context) async {
    await sl<LogoutUsecase>()();
    sl<AppState>().clearSession();
    if (context.mounted) context.go('/login');
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
              onPressed: () => _logout(context),
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
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
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
                                        label: 'Scan for Attendance',
                                        helper: 'Tap to scan',
                                        onTap: () =>
                                            context.go('/scan-attendance'),
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
                              _PerformanceCard(performance: data.performance),
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
    return Row(
      children: [
        EmployeeAvatar(
          imageUrl: profile.profileImageUrl,
          name: profile.fullName,
          size: 62,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hello, Barista!',
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
      ],
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
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.go('/schedule'),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 132),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(16),
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
                        ? 'No assigned shift today'
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
              borderRadius: BorderRadius.circular(14),
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
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: EmployeeCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 64,
              width: 64,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.18),
                ),
              ),
              child: Icon(
                icon,
                size: 36,
                color: Theme.of(context).colorScheme.primary,
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
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: EmployeeCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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

class _PerformanceCard extends StatelessWidget {
  const _PerformanceCard({required this.performance});

  final EmployeePerformanceSummary performance;

  @override
  Widget build(BuildContext context) {
    final values = [
      ('On Time', performance.onTime, const Color(0xFF39D92F)),
      ('Late', performance.late, const Color(0xFFF7C873)),
      ('Under', performance.undertime, const Color(0xFFF97316)),
      ('Over', performance.overtime, const Color(0xFF4D9A21)),
      ('Absent', performance.absent, const Color(0xFFCC1111)),
    ];
    final maxValue = values.map((item) => item.$2).fold<int>(
        1, (previous, current) => previous > current ? previous : current);

    return EmployeeCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Performance Overview',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 26,
            decoration: BoxDecoration(
              color: const Color(0xFFF8D777),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text('Weekly', style: TextStyle(fontSize: 11)),
                Text('Monthly', style: TextStyle(fontSize: 11)),
                Text('Yearly', style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (!performance.hasData)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No attendance records yet.')),
            )
          else
            SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: values
                    .map(
                      (item) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Flexible(
                                child: FractionallySizedBox(
                                  heightFactor:
                                      (item.$2 / maxValue).clamp(0.06, 1),
                                  child: Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: item.$3,
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(4),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                item.$1,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 10),
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
