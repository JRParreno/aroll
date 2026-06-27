import 'dart:math' as math;

import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/domain/usecase/auth/logout_usecase.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_progress_card.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_wizard_constants.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

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
    _future = Future.wait([repo.performance(), repo.setupStatus()]);
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
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(onRetry: _refresh);
          }
          final performance = snapshot.data![0];
          final setup = snapshot.data![1];
          final summary =
              performance['summary'] as Map<String, dynamic>? ?? const {};
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                _OwnerHeader(session: widget.session),
                if (setup['setup_completed_at'] == null) ...[
                  const SizedBox(height: 14),
                  SetupProgressCard(data: setup),
                ],
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: _PerformanceChart(summary: summary),
                ),
                const SizedBox(height: 10),
                _DashboardSummaryCards(summary: summary),
                const SizedBox(height: 12),
                _ActionCard(
                  title: 'Set Schedule',
                  subtitle: 'Assign shifts and organize the coming week.',
                  icon: Icons.event_available_rounded,
                  onTap: () => context.push('/owner/schedule'),
                  prominent: true,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _DashboardManagementCard(
                        label: 'Manage Employees',
                        icon: Icons.groups_rounded,
                        backgroundColor: const Color(0xFFFFE8D6),
                        iconColor: const Color(0xFF1E466E),
                        onTap: () => context.push('/owner/employees'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DashboardManagementCard(
                        label: 'Setup Location',
                        icon: Icons.location_on_outlined,
                        backgroundColor: const Color(0xFFFFE1E8),
                        iconColor: const Color(0xFFE11D48),
                        onTap: () => context.push('/owner/location'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DashboardManagementCard(
                        label: 'Employee Payroll',
                        icon: Icons.account_balance_wallet_outlined,
                        backgroundColor: const Color(0xFFDBEAFE),
                        iconColor: const Color(0xFF1E466E),
                        onTap: () => context.push('/owner/payroll'),
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

class OwnerProfileScreen extends StatelessWidget {
  const OwnerProfileScreen({super.key, required this.session});

  final UserSession session;

  Future<void> _logout(BuildContext context) async {
    await sl<LogoutUsecase>()();
    sl<AppState>().clearSession();
    if (context.mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return OwnerShell(
      selectedIndex: 2,
      showBackButton: true,
      title: 'Profile',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Card(
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 38,
                  child: Icon(Icons.person_rounded, size: 40),
                ),
                const SizedBox(height: 12),
                Text(session.fullName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                Text(session.email ?? ''),
                const SizedBox(height: 4),
                Text(session.businessName),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _ActionCard(
            title: 'Productivity Insights',
            subtitle: 'Performance trends and employee scores.',
            icon: Icons.insights_rounded,
            onTap: () => context.push('/owner/productivity'),
          ),
          _ActionCard(
            title: 'Business Location',
            subtitle: 'View workplace geofence configuration.',
            icon: Icons.location_on_outlined,
            onTap: () => context.push('/owner/location'),
          ),
          _ActionCard(
            title: 'Settings & Business Setup',
            subtitle: 'Account, payroll, attendance, and setup status.',
            icon: Icons.settings_outlined,
            onTap: () => context.push('/owner/settings'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Log Out'),
          ),
        ],
      ),
    );
  }
}

class OwnerProductivityScreen extends StatelessWidget {
  const OwnerProductivityScreen({super.key});

  @override
  Widget build(BuildContext context) => _SecondaryOwnerScreen(
        title: 'Productivity Insights',
        future: sl<OwnerRepository>().performance(),
        builder: (data) {
          final employees =
              (data['employees'] as List<dynamic>? ?? const [])
                  .whereType<Map<String, dynamic>>()
                  .toList();
          return [
            _PerformanceChart(
              summary:
                  data['summary'] as Map<String, dynamic>? ?? const {},
            ),
            const SizedBox(height: 14),
            if (employees.isEmpty)
              const _EmptyState('No performance records yet.')
            else
              ...employees.map(
                (item) => _Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${item['full_name'] ?? 'Employee'}'),
                    subtitle: Text(
                      'Attendance ${item['attendance_rate'] ?? 0}% • '
                      'Punctuality ${item['punctuality_rate'] ?? 0}%',
                    ),
                    trailing: Text(
                      '${item['productivity_score'] ?? 0}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ];
        },
      );
}

class OwnerLocationScreen extends StatelessWidget {
  const OwnerLocationScreen({super.key});

  @override
  Widget build(BuildContext context) => _SecondaryOwnerScreen(
        title: 'Business Location',
        future: sl<OwnerRepository>().location(),
        builder: (data) => [
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_rounded,
                    size: 42, color: Color(0xFF1E466E)),
                const SizedBox(height: 12),
                Text('${data['label'] ?? 'Primary workplace'}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                const SizedBox(height: 6),
                Text('${data['address'] ?? 'No location configured'}'),
                const SizedBox(height: 12),
                Text('Geofence radius: ${data['geofence_radius_m'] ?? 0} m'),
                Text(
                  'Coordinates: ${data['latitude'] ?? '--'}, '
                  '${data['longitude'] ?? '--'}',
                ),
              ],
            ),
          ),
        ],
      );
}

class OwnerSettingsScreen extends StatelessWidget {
  const OwnerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => _SecondaryOwnerScreen(
        title: 'Settings',
        future: Future.wait([
          sl<OwnerRepository>().accountSettings(),
          sl<OwnerRepository>().businessSettings(),
          sl<OwnerRepository>().payrollConfig(),
          sl<OwnerRepository>().attendancePolicy(),
        ]),
        builder: (data) {
          final values = data as List<Map<String, dynamic>>;
          return [
            _SettingsCard(title: 'Owner account', data: values[0]),
            _SettingsCard(title: 'Business profile', data: values[1]),
            _SettingsCard(title: 'Payroll configuration', data: values[2]),
            _SettingsCard(title: 'Attendance policy', data: values[3]),
            _ActionCard(
              title: 'Business Setup Wizard',
              subtitle: 'Walk through shifts, payroll, attendance, and location.',
              icon: Icons.checklist_rounded,
              onTap: () => context.push('/owner/setup-wizard'),
            ),
          ];
        },
      );
}

class OwnerSetupScreen extends StatelessWidget {
  const OwnerSetupScreen({super.key});

  int _stepIndexForKey(String key) {
    final index = setupWizardStepKeys.indexOf(key);
    return index >= 0 ? index : 0;
  }

  @override
  Widget build(BuildContext context) => _SecondaryOwnerScreen(
        title: 'Business Setup',
        future: sl<OwnerRepository>().setupStatus(),
        builder: (data) {
          final steps = (data['steps'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>();
          final continueStep = firstIncompleteSetupStepIndex(data);
          return [
            SetupProgressCard(data: data, showContinueButton: false),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => context.push(
                  '/owner/setup-wizard?step=$continueStep',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A5F),
                ),
                child: const Text('Open Setup Wizard'),
              ),
            ),
            const SizedBox(height: 12),
            ...steps.where((step) => step['key'] != 'review').map(
              (step) {
                final key = '${step['key']}';
                final stepIndex = _stepIndexForKey(key);
                return _Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      step['complete'] == true
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: step['complete'] == true
                          ? Colors.green
                          : Colors.orange,
                    ),
                    title: Text('${step['label'] ?? step['key']}'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push(
                      '/owner/setup-wizard?step=$stepIndex',
                    ),
                  ),
                );
              },
            ),
            if (data['setup_completed_at'] != null)
              FilledButton(
                onPressed: () => context.go('/owner/home'),
                child: const Text('Continue to Dashboard'),
              ),
          ];
        },
      );
}

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
            if (snapshot.hasError) return const _ErrorState();
            final items = snapshot.data ?? const [];
            if (items.isEmpty) return _EmptyState(emptyText);
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, index) =>
                  _Card(child: itemBuilder(items[index])),
            );
          },
        ),
      );
}

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
            if (snapshot.hasError) return const _ErrorState();
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
                  const _EmptyState('No records are available yet.')
                else
                  ...items.map(
                    (item) => _Card(
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

class _SecondaryOwnerScreen extends StatelessWidget {
  const _SecondaryOwnerScreen({
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
            if (snapshot.hasError) return const _ErrorState();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: builder(snapshot.data),
            );
          },
        ),
      );
}

class _OwnerHeader extends StatelessWidget {
  const _OwnerHeader({required this.session});

  final UserSession session;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFFE7EEF5),
            backgroundImage: session.branding?.displayImageUrl != null
                ? NetworkImage(session.branding!.displayImageUrl!)
                : null,
            child: session.branding?.displayImageUrl == null
                ? const Icon(Icons.storefront_rounded,
                    size: 24, color: Color(0xFF1E466E))
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              session.fullName.isEmpty ? 'Business Owner' : session.fullName,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/owner/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.notifications_none_rounded),
          ),
        ],
      );
}

class _DashboardSummaryCards extends StatelessWidget {
  const _DashboardSummaryCards({required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final attendance = _number(summary['attendance_rate']).clamp(0, 100);
    final productivity = _number(summary['productivity_score']).clamp(0, 100);
    final punctuality = _number(summary['punctuality_rate']).clamp(0, 100);
    final remaining = (100 - productivity - punctuality).clamp(0, 100);

    return Row(
      children: [
        Expanded(
          child: _DashboardSummaryCard(
            label: 'Productivity Insights',
            child: SizedBox(
              height: 58,
              width: 58,
              child: CustomPaint(
                painter: _DonutChartPainter(
                  values: [
                    productivity.toDouble(),
                    punctuality.toDouble(),
                    remaining.toDouble(),
                  ],
                  colors: const [
                    Color(0xFF3B82F6),
                    Color(0xFFF59E0B),
                    Color(0xFF22C55E),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _DashboardSummaryCard(
            label: "Today's Attendance",
            child: SizedBox(
              height: 58,
              width: 58,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: attendance / 100,
                    strokeWidth: 6,
                    backgroundColor: const Color(0xFFE5E7EB),
                    color: const Color(0xFF22C55E),
                  ),
                  Text(
                    '$attendance%',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DashboardSummaryCard extends StatelessWidget {
  const _DashboardSummaryCard({
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => _Card(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            child,
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
              ),
            ),
          ],
        ),
      );
}

class _DashboardManagementCard extends StatelessWidget {
  const _DashboardManagementCard({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _Card(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: backgroundColor,
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151),
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      );
}

class _DonutChartPainter extends CustomPainter {
  _DonutChartPainter({
    required this.values,
    required this.colors,
  });

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

class _PerformanceChart extends StatelessWidget {
  const _PerformanceChart({required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final values = [
      ('On time', _number(summary['on_time_clock_ins']), Colors.green),
      ('Late', _number(summary['late_clock_ins']), Colors.amber),
      ('Under', _number(summary['undertime_shifts']), Colors.orange),
      ('Over', _number(summary['overtime_shifts']), Colors.blue),
      ('Absent', _number(summary['absent_shifts']), Colors.redAccent),
    ];
    final maxValue =
        math.max(1, values.map((entry) => entry.$2).fold(0, math.max));
    return _Card(
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
                              height: math.max(7, 70 * entry.$2 / maxValue),
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

class _ActionCard extends StatelessWidget {
  const _ActionCard({
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

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.title, required this.data});
  final String title;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final visible = data.entries
        .where((entry) =>
            entry.value != null &&
            entry.value is! Map &&
            entry.value is! List &&
            entry.key != 'id')
        .take(6);
    return _Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const Divider(height: 24),
          for (final entry in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(_title(entry.key))),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      '${entry.value}',
                      textAlign: TextAlign.end,
                      style: const TextStyle(color: Color(0xFF6B7280)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.margin, this.padding});
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

class _EmptyState extends StatelessWidget {
  const _EmptyState(this.message);
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({this.onRetry});
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

int _number(Object? value) =>
    value is num ? value.round() : int.tryParse('$value') ?? 0;

String _initials(String value) {
  final parts = value.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  return parts.take(2).map((part) => part[0].toUpperCase()).join();
}

String _title(String value) => value
    .replaceAll('_', ' ')
    .split(' ')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

String _money(Object? value) => NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    ).format(value is num ? value : num.tryParse('$value') ?? 0);
