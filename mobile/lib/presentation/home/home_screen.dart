import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/domain/usecase/auth/logout_usecase.dart';
import 'package:aroll_mobile/presentation/attendance/attendance_screen.dart';
import 'package:aroll_mobile/presentation/home/data/dashboard_mock.dart';
import 'package:aroll_mobile/presentation/home/widgets/performance_overview_card.dart';
import 'package:aroll_mobile/presentation/home/widgets/salary_card.dart';
import 'package:aroll_mobile/presentation/home/widgets/scan_attendance_card.dart';
import 'package:aroll_mobile/presentation/home/widgets/schedule_card.dart';
import 'package:aroll_mobile/presentation/home/widgets/welcome_header.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.session});

  final UserSession session;

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to access your dashboard.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    await sl<LogoutUsecase>()();
    sl<AppState>().clearSession();
    if (context.mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
      '[home] HomeScreen.build name=${session.fullName} '
      'mustChangePassword=${session.mustChangePassword}',
    );
    final now = DateTime.now();
    final shift = DashboardMock.todayShift(now);
    final payroll = DashboardMock.currentPayroll(now);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            WelcomeHeader(
              session: session,
              onLogout: () => _logout(context),
            ),
            const SizedBox(height: 16),
            ScheduleCard(shift: shift),
            const SizedBox(height: 16),
            const ScanAttendanceCard(),
            const SizedBox(height: 16),
            SalaryCard(payroll: payroll),
            const SizedBox(height: 16),
            const PerformanceOverviewCard(),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Attendance history'),
              trailing: const Icon(Icons.chevron_right),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.6),
                ),
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AttendanceScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
