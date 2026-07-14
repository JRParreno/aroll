import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class EmployeeScheduleScreen extends StatefulWidget {
  const EmployeeScheduleScreen({super.key});

  @override
  State<EmployeeScheduleScreen> createState() => _EmployeeScheduleScreenState();
}

class _EmployeeScheduleScreenState extends State<EmployeeScheduleScreen> {
  late Future<_ScheduleData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ScheduleData> _load() async {
    final repo = sl<EmployeeRepository>();
    final results = await Future.wait([
      repo.getProfile(),
      repo.getSchedule(activeOnly: true),
    ]);
    final profile = results[0] as EmployeeProfile;
    sl<AppState>().updateEmployeeProfileImage(profile.profileImageUrl);
    return _ScheduleData(
      profile: profile,
      items: results[1] as List<EmployeeScheduleItem>,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return EmployeeScaffold(
      title: 'My Schedule',
      selectedIndex: 1,
      child: FutureBuilder<_ScheduleData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return loadingView();
          }
          if (snapshot.hasError) {
            return errorView(snapshot.error);
          }
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: EmptyState(
                title: 'Unable to load schedule',
                description: 'Pull down to refresh or try again later.',
              ),
            );
          }

          final data = snapshot.data!;
          final todayItems =
              data.items.where((item) => item.status == 'today').toList();
          final upcomingItems =
              data.items.where((item) => item.status == 'upcoming').toList();

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                _ScheduleHeader(
                  profile: data.profile,
                  activeCount: data.items.length,
                ),
                const SizedBox(height: 12),
                _HistoryLinkCard(
                  onTap: () => context.push('/shift-history'),
                ),
                if (data.items.isEmpty) ...[
                  const SizedBox(height: 16),
                  const EmployeeEmptyState(
                    title: 'No upcoming schedules',
                    description:
                        'You have no assigned shifts today or in the future. Completed shifts are kept in Shift History.',
                    icon: Icons.event_available_outlined,
                    inCard: true,
                  ),
                ] else ...[
                  if (todayItems.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const EmployeeSectionHeader(
                      title: 'Today',
                      subtitle: 'Your shift for today',
                    ),
                    ...todayItems.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ActiveScheduleCard(item: item, highlighted: true),
                      ),
                    ),
                  ],
                  if (upcomingItems.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    EmployeeSectionHeader(
                      title: 'Upcoming',
                      subtitle:
                          '${upcomingItems.length} future shift${upcomingItems.length == 1 ? '' : 's'}',
                    ),
                    ...upcomingItems.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ActiveScheduleCard(item: item),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ScheduleData {
  const _ScheduleData({required this.profile, required this.items});

  final EmployeeProfile profile;
  final List<EmployeeScheduleItem> items;
}

class _ScheduleHeader extends StatelessWidget {
  const _ScheduleHeader({
    required this.profile,
    required this.activeCount,
  });

  final EmployeeProfile profile;
  final int activeCount;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final appState = sl<AppState>();

    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final avatarUrl = appState.resolveEmployeeAvatarUrl(
          profile.profileImageUrl,
        );
        return EmployeeCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: EmployeeColors.iconWell,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  color: EmployeeColors.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My Schedule',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${monthName(now)} ${now.year}',
                      style: const TextStyle(
                        color: EmployeeColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      activeCount == 0
                          ? 'No active shifts · ${profile.businessName}'
                          : '$activeCount active shift${activeCount == 1 ? '' : 's'} · ${profile.businessName}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: EmployeeColors.textMuted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              EmployeeAvatar(
                imageUrl: avatarUrl,
                name: profile.fullName,
                size: 42,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HistoryLinkCard extends StatelessWidget {
  const _HistoryLinkCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: EmployeeCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                color: EmployeeColors.iconWell,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.history_rounded,
                color: EmployeeColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Shift History',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'View completed shifts and attendance results',
                    style: TextStyle(
                      color: EmployeeColors.textMuted,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: EmployeeColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveScheduleCard extends StatelessWidget {
  const _ActiveScheduleCard({
    required this.item,
    this.highlighted = false,
  });

  final EmployeeScheduleItem item;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final statusStyle = employeeScheduleStatusStyle(item.status);
    return InkWell(
      onTap: () => context.push('/schedule/detail', extra: item),
      borderRadius: BorderRadius.circular(18),
      child: EmployeeCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dayName(item.workDate),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: highlighted
                              ? EmployeeColors.primary
                              : EmployeeColors.textBody,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        shortDate(item.workDate),
                        style: const TextStyle(
                          color: EmployeeColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                EmployeeStatusChip(
                  label: statusStyle.label,
                  color: statusStyle.color,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(
                  Icons.work_outline_rounded,
                  size: 18,
                  color: EmployeeColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.shiftName,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  size: 18,
                  color: EmployeeColors.textMuted,
                ),
                const SizedBox(width: 8),
                Text(
                  '${item.startLabel} - ${item.endLabel}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: EmployeeColors.textBody,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Working with',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: EmployeeColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            EmployeeCoworkerStrip(coworkers: item.coworkers),
          ],
        ),
      ),
    );
  }
}
