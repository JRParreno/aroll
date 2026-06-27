import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:flutter/material.dart';

class EmployeeScheduleScreen extends StatefulWidget {
  const EmployeeScheduleScreen({super.key});

  @override
  State<EmployeeScheduleScreen> createState() => _EmployeeScheduleScreenState();
}

class _EmployeeScheduleScreenState extends State<EmployeeScheduleScreen> {
  late Future<_ScheduleData> _future;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ScheduleData> _load() async {
    final repo = sl<EmployeeRepository>();
    final results = await Future.wait([
      repo.getProfile(),
      repo.getSchedule(),
    ]);
    return _ScheduleData(
      profile: results[0] as EmployeeProfile,
      items: results[1] as List<EmployeeScheduleItem>,
    );
  }

  @override
  Widget build(BuildContext context) {
    return EmployeeScaffold(
      title: 'My Schedule',
      selectedIndex: 1,
      showBack: true,
      actions: const [
        Padding(
          padding: EdgeInsets.only(right: 12),
          child: Icon(Icons.calendar_month_rounded),
        ),
      ],
      child: FutureBuilder<_ScheduleData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return loadingView();
          }
          if (snapshot.hasError) return errorView(snapshot.error);
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: EmptyState(
                title: 'No schedule assigned yet.',
                description:
                    'Your assigned shifts will appear here once published.',
              ),
            );
          }

          final data = snapshot.data!;
          final week = _weekDates(_selectedDate);
          final visibleItems = data.items;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              _Header(date: _selectedDate, profile: data.profile),
              const SizedBox(height: 12),
              _WeekStrip(
                dates: week,
                selectedDate: _selectedDate,
                onChanged: (date) => setState(() => _selectedDate = date),
              ),
              const SizedBox(height: 18),
              const Row(
                children: [
                  SizedBox(
                    width: 88,
                    child: Text(
                      'Date & Time',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Shift',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (visibleItems.isEmpty)
                const EmptyState(
                  title: 'No schedule assigned yet.',
                  description:
                      'Your assigned shifts will appear here once published.',
                )
              else
                ...visibleItems.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ScheduleRow(item: item),
                  ),
                ),
            ],
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

class _Header extends StatelessWidget {
  const _Header({required this.date, required this.profile});

  final DateTime date;
  final EmployeeProfile profile;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          dayNumber(date),
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dayName(date),
                  style: Theme.of(context).textTheme.labelMedium),
              Text(
                '${monthName(date)} ${date.year}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              Text(
                profile.businessName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF6B7280),
                    ),
              ),
            ],
          ),
        ),
        EmployeeAvatar(
          imageUrl: profile.profileImageUrl,
          name: profile.fullName,
          size: 42,
        ),
      ],
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.dates,
    required this.selectedDate,
    required this.onChanged,
  });

  final List<DateTime> dates;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return EmployeeCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: dates.map((date) {
          final selected = _sameDay(date, selectedDate);
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onChanged(date),
            child: Container(
              width: 36,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFEAF3FF) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    dayName(date).substring(0, 2),
                    style: const TextStyle(fontSize: 10),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    dayNumber(date),
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.item});

  final EmployeeScheduleItem item;

  @override
  Widget build(BuildContext context) {
    final cardColor = _shiftColor(item.shiftName);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 88,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                monthDay(item.workDate),
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '${item.startLabel} - ${item.endLabel}',
                style: const TextStyle(fontSize: 9),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.shiftName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: Colors.white),
                  ],
                ),
                if (item.holidayName != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    '${item.holidayName} Holiday',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 11,
                    ),
                  ),
                ],
                if (item.locationAddress != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    item.locationAddress!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.86),
                      fontSize: 11,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                if (item.coworkers
                    .where((item) => !item.isCurrentEmployee)
                    .isEmpty)
                  Text(
                    'No coworkers assigned for this shift yet.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.86),
                      fontSize: 11,
                    ),
                  )
                else
                  SizedBox(
                    height: 56,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: item.coworkers
                          .where((item) => !item.isCurrentEmployee)
                          .length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final coworker = item.coworkers
                            .where((item) => !item.isCurrentEmployee)
                            .toList()[index];
                        return _CoworkerAvatar(coworker: coworker);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CoworkerAvatar extends StatelessWidget {
  const _CoworkerAvatar({required this.coworker});

  final EmployeeCoworker coworker;

  @override
  Widget build(BuildContext context) {
    final firstName =
        coworker.isCurrentEmployee ? 'You' : coworker.fullName.split(' ').first;
    return SizedBox(
      width: 46,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          EmployeeAvatar(
            imageUrl: coworker.profileImageUrl,
            name: coworker.fullName,
            size: 30,
          ),
          const SizedBox(height: 3),
          Text(
            firstName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

List<DateTime> _weekDates(DateTime date) {
  final start = date.subtract(Duration(days: date.weekday % 7));
  return List.generate(
      7, (index) => DateTime(start.year, start.month, start.day + index));
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

Color _shiftColor(String shiftName) {
  final normalized = shiftName.toLowerCase();
  if (normalized.contains('closing')) return const Color(0xFF6FA1C8);
  if (normalized.contains('mid')) return const Color(0xFF8AB7D9);
  return const Color(0xFF12355B);
}
