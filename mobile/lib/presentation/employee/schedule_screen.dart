import 'dart:async';

import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/theme/business_brand_theme.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

enum _AttendanceOutcome { done, missed, onLeave }

class EmployeeScheduleScreen extends StatefulWidget {
  const EmployeeScheduleScreen({super.key});

  @override
  State<EmployeeScheduleScreen> createState() => _EmployeeScheduleScreenState();
}

class _EmployeeScheduleScreenState extends State<EmployeeScheduleScreen>
    with WidgetsBindingObserver {
  late Future<_ScheduleData> _future;

  /// UI-only: which day is highlighted in the week strip.
  late DateTime _selectedDay;

  /// Week-start (Sunday) for the data currently loaded.
  DateTime? _loadedWeekStart;

  Timer? _weekWatchTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final today = _dateOnly(DateTime.now());
    _selectedDay = today;
    _future = _load();
    _weekWatchTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _ensureCurrentWeek();
    });
  }

  @override
  void dispose() {
    _weekWatchTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _ensureCurrentWeek();
    }
  }

  DateTime get _currentWeekStart => _weekDays(DateTime.now()).first;

  void _ensureCurrentWeek() {
    final weekStart = _currentWeekStart;
    final today = _dateOnly(DateTime.now());
    final weekChanged =
        _loadedWeekStart == null || !_isSameDay(_loadedWeekStart!, weekStart);
    final dayDrift = !_isSameDay(_selectedDay, today) &&
        !_weekDays(today).any((d) => _isSameDay(d, _selectedDay));

    if (!weekChanged && !dayDrift) return;
    if (!mounted) return;
    setState(() {
      if (weekChanged || dayDrift) {
        _selectedDay = today;
      }
      if (weekChanged) {
        _future = _load();
      }
    });
  }

  Future<_ScheduleData> _load() async {
    final repo = sl<EmployeeRepository>();
    final week = _weekDays(DateTime.now());
    final start = week.first;
    final end = week.last;

    final results = await Future.wait([
      repo.getProfile(),
      // Current week only — includes past days in this week (not activeOnly).
      repo.getSchedule(
        startDate: start,
        endDate: end,
        activeOnly: false,
      ),
      repo.getShiftHistory(),
    ]);

    final profile = results[0] as EmployeeProfile;
    final appState = sl<AppState>();
    appState.updateEmployeeProfileImage(profile.profileImageUrl);
    appState.updateBusinessBranding(profile.branding);

    final rawItems = results[1] as List<EmployeeScheduleItem>;
    final items = rawItems
        .where((item) {
          final day = _dateOnly(item.workDate);
          return !day.isBefore(start) && !day.isAfter(end);
        })
        .toList()
      ..sort((a, b) {
        final byDate = a.workDate.compareTo(b.workDate);
        if (byDate != 0) return byDate;
        return a.startTime.compareTo(b.startTime);
      });

    final history = results[2] as List<EmployeeShiftHistoryItem>;
    final historyByAssignment = <String, EmployeeShiftHistoryItem>{
      for (final row in history) row.assignmentId: row,
    };

    _loadedWeekStart = start;

    return _ScheduleData(
      profile: profile,
      items: items,
      historyByAssignment: historyByAssignment,
      weekStart: start,
      weekEnd: end,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  void _jumpToToday() {
    final today = _dateOnly(DateTime.now());
    setState(() => _selectedDay = today);
    _ensureCurrentWeek();
  }

  void _selectDay(DateTime day) {
    setState(() => _selectedDay = _dateOnly(day));
  }

  @override
  Widget build(BuildContext context) {
    final weekDays = _weekDays(DateTime.now());

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
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
            final rows = data.items
                .map(
                  (item) => _AssignedRowData(
                    item: item,
                    outcome: _outcomeFor(item, data.historyByAssignment),
                  ),
                )
                .toList();

            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                children: [
                  _ScheduleTopBar(
                    onBack: () => employeeNavigateBack(context),
                    onCalendar: () => context.push('/shift-history'),
                  ),
                  const SizedBox(height: 24),
                  _DateHero(
                    day: _selectedDay,
                    onToday: _jumpToToday,
                  ),
                  const SizedBox(height: 14),
                  _WeekCalendarCard(
                    days: weekDays,
                    selectedDay: _selectedDay,
                    onSelect: _selectDay,
                  ),
                  const SizedBox(height: 18),
                  const _SectionColumns(),
                  const SizedBox(height: 10),
                  if (rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: EmployeeEmptyState(
                        title: 'No shifts scheduled yet',
                        description:
                            'When your manager assigns shifts for this week, they will appear here. Past completed shifts stay in Shift History.',
                        icon: Icons.event_available_outlined,
                        inCard: true,
                      ),
                    )
                  else
                    ...rows.map(
                      (row) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ScheduleRow(row: row),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: const EmployeeBottomNav(selectedIndex: 0),
    );
  }
}

class _ScheduleData {
  const _ScheduleData({
    required this.profile,
    required this.items,
    required this.historyByAssignment,
    required this.weekStart,
    required this.weekEnd,
  });

  final EmployeeProfile profile;
  final List<EmployeeScheduleItem> items;
  final Map<String, EmployeeShiftHistoryItem> historyByAssignment;
  final DateTime weekStart;
  final DateTime weekEnd;
}

class _AssignedRowData {
  const _AssignedRowData({
    required this.item,
    required this.outcome,
  });

  final EmployeeScheduleItem item;
  final _AttendanceOutcome? outcome;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Sunday-start week to match the reference strip (Su–Sa).
List<DateTime> _weekDays(DateTime anchor) {
  final day = _dateOnly(anchor);
  final sundayOffset = day.weekday % 7; // Sun=0 … Sat=6
  final start = day.subtract(Duration(days: sundayOffset));
  return List.generate(7, (i) => start.add(Duration(days: i)));
}

DateTime? _combineWorkDateAndTime(DateTime workDate, String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return DateTime(workDate.year, workDate.month, workDate.day, hour, minute);
}

DateTime? _shiftEndDateTime(EmployeeScheduleItem item) {
  final start = _combineWorkDateAndTime(item.workDate, item.startTime);
  final end = _combineWorkDateAndTime(item.workDate, item.endTime);
  if (end == null) return null;
  if (start != null && !end.isAfter(start)) {
    // Overnight shift ends the next calendar day.
    return end.add(const Duration(days: 1));
  }
  return end;
}

bool _shiftHasEnded(EmployeeScheduleItem item, {DateTime? now}) {
  final end = _shiftEndDateTime(item);
  if (end == null) {
    return _dateOnly(item.workDate).isBefore(_dateOnly(now ?? DateTime.now()));
  }
  return (now ?? DateTime.now()).isAfter(end);
}

_AttendanceOutcome? _outcomeFor(
  EmployeeScheduleItem item,
  Map<String, EmployeeShiftHistoryItem> historyByAssignment,
) {
  if (item.status.toLowerCase() == 'on_leave') {
    return _AttendanceOutcome.onLeave;
  }

  final history = historyByAssignment[item.assignmentId];
  if (history != null && history.status.toLowerCase() == 'on_leave') {
    return _AttendanceOutcome.onLeave;
  }

  if (!_shiftHasEnded(item)) return null;

  if (history == null) {
    // Past/ended shift with no attendance record → missed.
    return _AttendanceOutcome.missed;
  }

  final status = history.status.toLowerCase();
  final finishedPunch =
      history.timeIn != null && history.timeOut != null;
  if (finishedPunch || status == 'complete' || status == 'late') {
    return _AttendanceOutcome.done;
  }
  if (status == 'absent' || status == 'incomplete') {
    return _AttendanceOutcome.missed;
  }
  // Still in_progress after end time without a full punch pair.
  return _AttendanceOutcome.missed;
}

class _ScheduleTopBar extends StatelessWidget {
  const _ScheduleTopBar({
    required this.onBack,
    required this.onCalendar,
  });

  final VoidCallback onBack;
  final VoidCallback onCalendar;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        IconButton(
          onPressed: onBack,
          tooltip: 'Back',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          icon: const Icon(
            Icons.arrow_back_rounded,
            size: 24,
            color: EmployeeColors.textPrimary,
          ),
        ),
        const Expanded(
          child: EmployeePageTitle('My Schedule'),
        ),
        IconButton(
          onPressed: onCalendar,
          tooltip: 'Shift History',
          icon: const Icon(
            Icons.calendar_month_outlined,
            size: 22,
            color: EmployeeColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _DateHero extends StatelessWidget {
  const _DateHero({
    required this.day,
    required this.onToday,
  });

  final DateTime day;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final weekday = DateFormat('EEE').format(day);
    final monthYear = DateFormat('MMM yyyy').format(day);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          DateFormat('d').format(day),
          style: const TextStyle(
            fontSize: 44,
            height: 1,
            fontWeight: FontWeight.w800,
            color: EmployeeColors.textPrimary,
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              weekday,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: EmployeeColors.textMuted,
              ),
            ),
            Text(
              monthYear,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: EmployeeColors.textMuted,
              ),
            ),
          ],
        ),
        const Spacer(),
        Builder(
          builder: (context) {
            final brand = BrandColors.of(context);
            return Material(
              color: brand.iconWell,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: onToday,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Text(
                    'Today',
                    style: TextStyle(
                      color: brand.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _WeekCalendarCard extends StatelessWidget {
  const _WeekCalendarCard({
    required this.days,
    required this.selectedDay,
    required this.onSelect,
  });

  final List<DateTime> days;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onSelect;

  static const _labels = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: EmployeeColors.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < days.length; i++)
            Expanded(
              child: _WeekDayCell(
                label: _labels[i],
                day: days[i],
                selected: _isSameDay(days[i], selectedDay),
                onTap: () => onSelect(days[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _WeekDayCell extends StatelessWidget {
  const _WeekDayCell({
    required this.label,
    required this.day,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final DateTime day;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: EmployeeColors.textMuted,
              ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? BrandColors.of(context).primary
                    : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : EmployeeColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionColumns extends StatelessWidget {
  const _SectionColumns();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          flex: 5,
          child: Text(
            'Date & Time',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: EmployeeColors.textPrimary,
            ),
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          flex: 6,
          child: Text(
            'Shift',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: EmployeeColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.row});

  final _AssignedRowData row;

  static const _cardRadius = 16.0;
  static const _cardPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 12);

  @override
  Widget build(BuildContext context) {
    final item = row.item;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: _DateTimeCard(
              day: _dateOnly(item.workDate),
              timeLabel: '${item.startLabel} - ${item.endLabel}',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: _ShiftCard(
              item: item,
              outcome: row.outcome,
            ),
          ),
        ],
      ),
    );
  }
}

class _DateTimeCard extends StatelessWidget {
  const _DateTimeCard({
    required this.day,
    required this.timeLabel,
  });

  final DateTime day;
  final String timeLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: _ScheduleRow._cardPadding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_ScheduleRow._cardRadius),
        border: Border.all(color: EmployeeColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            DateFormat('MMMM d').format(day),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: EmployeeColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            timeLabel,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: EmployeeColors.textMuted,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShiftCard extends StatelessWidget {
  const _ShiftCard({
    required this.item,
    required this.outcome,
  });

  final EmployeeScheduleItem item;
  final _AttendanceOutcome? outcome;

  Color _tone(BuildContext context) {
    final brand = BrandColors.of(context);
    final key = item.shiftName.toLowerCase();
    if (key.contains('open')) return brand.secondary;
    if (key.contains('clos')) return brand.primary;
    if (key.contains('mid') || key.contains('swing')) {
      return brand.accent;
    }
    final palette = [
      brand.secondary,
      brand.primary,
      brand.accent,
      Color.lerp(brand.primary, brand.secondary, 0.4) ?? brand.primary,
    ];
    return palette[item.shiftName.hashCode.abs() % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _tone(context),
      borderRadius: BorderRadius.circular(_ScheduleRow._cardRadius),
      elevation: 0,
      child: InkWell(
        onTap: () => context.push('/schedule/detail', extra: item),
        borderRadius: BorderRadius.circular(_ScheduleRow._cardRadius),
        child: Container(
          width: double.infinity,
          padding: _ScheduleRow._cardPadding,
          alignment: Alignment.center,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.shiftName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (outcome != null) ...[
                          const SizedBox(width: 6),
                          _OutcomeBadge(outcome: outcome!),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    _ShiftAvatars(coworkers: item.coworkers),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutcomeBadge extends StatelessWidget {
  const _OutcomeBadge({required this.outcome});

  final _AttendanceOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (outcome) {
      _AttendanceOutcome.done => (
          'Done',
          Icons.check_circle_rounded,
          const Color(0xFFBBF7D0),
        ),
      _AttendanceOutcome.onLeave => (
          'On Leave',
          Icons.beach_access_rounded,
          const Color(0xFFBFDBFE),
        ),
      _AttendanceOutcome.missed => (
          'Missed',
          Icons.cancel_rounded,
          const Color(0xFFFECACA),
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white70),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShiftAvatars extends StatelessWidget {
  const _ShiftAvatars({required this.coworkers});

  final List<EmployeeCoworker> coworkers;

  @override
  Widget build(BuildContext context) {
    if (coworkers.isEmpty) {
      return const Text(
        'No assignees',
        style: TextStyle(
          color: Colors.white70,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    final ordered = [
      ...coworkers.where((c) => c.isCurrentEmployee),
      ...coworkers.where((c) => !c.isCurrentEmployee),
    ];
    const maxVisible = 3;
    final visible = ordered.take(maxVisible).toList();
    final remaining = ordered.length - visible.length;

    return SizedBox(
      height: 36,
      child: Row(
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            _AvatarWithLabel(
              coworker: visible[i],
              label: visible[i].isCurrentEmployee
                  ? 'You'
                  : _firstName(visible[i].fullName),
            ),
          ],
          if (remaining > 0) ...[
            const SizedBox(width: 6),
            const _AvatarWithLabel(
              coworker: null,
              label: '+others',
              overflowCount: true,
            ),
          ],
        ],
      ),
    );
  }

  static String _firstName(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return fullName;
    final name = parts.first;
    if (name.length <= 8) return name;
    return '${name.substring(0, 7)}…';
  }
}

class _AvatarWithLabel extends StatelessWidget {
  const _AvatarWithLabel({
    required this.coworker,
    required this.label,
    this.overflowCount = false,
  });

  final EmployeeCoworker? coworker;
  final String label;
  final bool overflowCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (overflowCount)
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white70),
            ),
            child: const Text(
              '+',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        else
          EmployeeAvatar(
            imageUrl: coworker?.profileImageUrl,
            name: coworker?.fullName ?? label,
            size: 22,
          ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
      ],
    );
  }
}
