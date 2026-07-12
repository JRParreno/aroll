import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_progress_card.dart';
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
            return OwnerErrorState(onRetry: _refresh);
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
                  child: OwnerPerformanceChart(summary: summary),
                ),
                const SizedBox(height: 10),
                _DashboardSummaryCards(summary: summary),
                const SizedBox(height: 12),
                OwnerActionCard(
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
        ],
      );
}

class _DashboardSummaryCards extends StatelessWidget {
  const _DashboardSummaryCards({required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final attendance =
        ownerParseInt(summary['attendance_rate']).clamp(0, 100);
    final productivity =
        ownerParseInt(summary['productivity_score']).clamp(0, 100);
    final punctuality =
        ownerParseInt(summary['punctuality_rate']).clamp(0, 100);
    final remaining = (100 - productivity - punctuality).clamp(0, 100);

    return Row(
      children: [
        Expanded(
          child: _DashboardSummaryCard(
            label: 'Productivity Insights',
            child: OwnerDonutChart(
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
  Widget build(BuildContext context) => OwnerCard(
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
  Widget build(BuildContext context) => OwnerCard(
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
