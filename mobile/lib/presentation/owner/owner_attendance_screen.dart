import 'dart:math' as math;

import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class OwnerAttendanceScreen extends StatefulWidget {
  const OwnerAttendanceScreen({super.key});

  @override
  State<OwnerAttendanceScreen> createState() => _OwnerAttendanceScreenState();
}

class _OwnerAttendanceScreenState extends State<OwnerAttendanceScreen> {
  final _repo = sl<OwnerRepository>();
  final _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  String _query = '';
  DateTime _selectedDate = DateTime.now();

  List<Map<String, dynamic>> _records = const [];
  List<Map<String, dynamic>> _trend = const [];
  Map<String, String?> _profileImages = const {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repo.attendance(),
        _repo.performance(days: 30),
        _repo.employees(),
      ]);
      if (!mounted) return;

      final attendance = results[0] as Map<String, dynamic>;
      final performance = results[1] as Map<String, dynamic>;
      final employees = results[2] as List<Map<String, dynamic>>;

      final images = <String, String?>{};
      for (final employee in employees) {
        final name = '${employee['full_name'] ?? ''}'.trim();
        if (name.isNotEmpty) {
          images[name] = employee['profile_image_url'] as String?;
        }
      }

      setState(() {
        _records = (attendance['records'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList();
        _trend = (performance['trend'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList();
        _profileImages = images;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load attendance data. Please try again.';
        _loading = false;
      });
    }
  }

  String get _selectedIsoDate => _isoDate(_selectedDate);

  bool get _isToday => _isoDate(DateTime.now()) == _selectedIsoDate;

  Map<String, int> get _chartMetrics {
    final label = DateFormat('MMM dd').format(_selectedDate);
    final trendItem = _trend.cast<Map<String, dynamic>?>().firstWhere(
          (item) => item?['label'] == label,
          orElse: () => null,
        );

    if (trendItem != null) {
      return {
        'on_time': _number(trendItem['on_time']),
        'late': _number(trendItem['late']),
        'undertime': _number(trendItem['undertime']),
        'overtime': _number(trendItem['overtime']),
        'absent': _number(trendItem['absent']),
      };
    }

    final dayRecords =
        _records.where((record) => record['date'] == _selectedIsoDate);
    var onTime = 0;
    var late = 0;
    var absent = 0;
    for (final record in dayRecords) {
      final status = '${record['status'] ?? ''}';
      if (status == 'absent') {
        absent += 1;
      } else if (status == 'late') {
        late += 1;
      } else if (record['time_in'] != null) {
        onTime += 1;
      }
    }
    return {
      'on_time': onTime,
      'late': late,
      'undertime': 0,
      'overtime': 0,
      'absent': absent,
    };
  }

  List<Map<String, dynamic>> get _visibleRecords {
    return _records.where((record) {
      if (record['date'] != _selectedIsoDate) return false;
      if (record['time_in'] == null) return false;
      final name = '${record['employee_name'] ?? ''}'.toLowerCase();
      if (_query.isNotEmpty && !name.contains(_query)) return false;
      return true;
    }).toList();
  }

  List<Map<String, dynamic>> get _restDayRecords {
    return _visibleRecords
        .where((record) => record['is_rest_day'] == true)
        .toList();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OwnerShell(
      selectedIndex: 1,
      title: 'Attendance',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _AttendanceErrorState(
                  message: _error!,
                  onRetry: _loadData,
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      _DateHeader(
                        selectedDate: _selectedDate,
                        isToday: _isToday,
                        onPickDate: _pickDate,
                        onToday: () =>
                            setState(() => _selectedDate = DateTime.now()),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search employees...',
                          prefixIcon: const Icon(Icons.search_rounded),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: Color(0xFFE5E7EB)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: Color(0xFFE5E7EB)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _AttendanceChart(metrics: _chartMetrics),
                      if (_restDayRecords.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _RestDayWorkSection(
                          records: _restDayRecords,
                          profileImages: _profileImages,
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (_visibleRecords.isEmpty)
                        _AttendanceEmptyState(isToday: _isToday)
                      else
                        ..._visibleRecords.map(
                          (record) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _AttendanceEmployeeCard(
                              record: record,
                              profileImageUrl: _profileImages[
                                  '${record['employee_name'] ?? ''}'.trim()],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({
    required this.selectedDate,
    required this.isToday,
    required this.onPickDate,
    required this.onToday,
  });

  final DateTime selectedDate;
  final bool isToday;
  final VoidCallback onPickDate;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPickDate,
          child: Row(
            children: [
              Text(
                DateFormat('d').format(selectedDate),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('EEE').format(selectedDate),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF374151),
                    ),
                  ),
                  Text(
                    DateFormat('MMM yyyy').format(selectedDate),
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Spacer(),
        if (!isToday)
          TextButton(
            onPressed: onToday,
            child: const Text('Today'),
          ),
      ],
    );
  }
}

class _AttendanceChart extends StatelessWidget {
  const _AttendanceChart({required this.metrics});

  final Map<String, int> metrics;

  @override
  Widget build(BuildContext context) {
    final values = [
      ('On time', metrics['on_time'] ?? 0, const Color(0xFF22C55E)),
      ('Late', metrics['late'] ?? 0, const Color(0xFFF59E0B)),
      ('Under', metrics['undertime'] ?? 0, const Color(0xFFF97316)),
      ('Over', metrics['overtime'] ?? 0, const Color(0xFF3B82F6)),
      ('Absent', metrics['absent'] ?? 0, const Color(0xFFEF4444)),
    ];
    final maxValue =
        math.max(1, values.map((entry) => entry.$2).fold(0, math.max));

    return _AttendanceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attendance Overview',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 132,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: values
                  .map(
                    (entry) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              '${entry.$2}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height: math.max(8, 88 * entry.$2 / maxValue),
                              decoration: BoxDecoration(
                                color: entry.$3,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              entry.$1,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 9),
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

class _RestDayWorkSection extends StatelessWidget {
  const _RestDayWorkSection({
    required this.records,
    required this.profileImages,
  });

  final List<Map<String, dynamic>> records;
  final Map<String, String?> profileImages;

  @override
  Widget build(BuildContext context) {
    return _AttendanceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Rest Day Work',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${records.length}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF075985),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Employees who clocked in or out on the configured rest day.',
            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 12),
          ...records.map((record) {
            final name = '${record['employee_name'] ?? 'Employee'}';
            final timeIn = _formatTime(record['time_in'] as String?);
            final timeOut = _formatTime(record['time_out'] as String?);
            final shift = record['shift_name'] ?? record['position_title'];
            final unauthorized = record['rest_day_authorized'] == false;
            final accent = unauthorized
                ? const Color(0xFFFEF3C7)
                : const Color(0xFFE0F2FE);
            final accentBorder = unauthorized
                ? const Color(0xFFFDE68A)
                : const Color(0xFFBAE6FD);
            final accentText = unauthorized
                ? const Color(0xFF92400E)
                : const Color(0xFF075985);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: unauthorized
                      ? const Color(0xFFFFFBEB)
                      : const Color(0xFFF0F9FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accentBorder),
                ),
                child: Row(
                  children: [
                    EmployeeAvatar(
                      imageUrl: profileImages[name.trim()],
                      name: name,
                      size: 42,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${shift ?? 'Attendance'} · In $timeIn · Out $timeOut',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        unauthorized ? 'Not permitted' : 'Rest day',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: accentText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _AttendanceEmployeeCard extends StatelessWidget {
  const _AttendanceEmployeeCard({
    required this.record,
    required this.profileImageUrl,
  });

  final Map<String, dynamic> record;
  final String? profileImageUrl;

  @override
  Widget build(BuildContext context) {
    final name = '${record['employee_name'] ?? 'Employee'}';
    final status = '${record['status'] ?? ''}';
    final shift = record['shift_name'] ?? record['position_title'];
    final timeIn = _formatTime(record['time_in'] as String?);
    final timeOut = _formatTime(record['time_out'] as String?);
    final late = status == 'late';
    final absent = status == 'absent';

    return _AttendanceCard(
      child: Row(
        children: [
          EmployeeAvatar(
            imageUrl: profileImageUrl,
            name: name,
            size: 52,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                if (shift != null)
                  Text(
                    '$shift',
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                    ),
                  ),
                Text(
                  _statusCopy(status),
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                  ),
                ),
                if (record['time_out'] != null)
                  Text(
                    '$timeIn – $timeOut',
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: absent
                  ? const Color(0xFFFEE2E2)
                  : late
                      ? const Color(0xFFFFEDD5)
                      : const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              absent ? 'Absent' : timeIn,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: absent
                    ? const Color(0xFFB91C1C)
                    : late
                        ? const Color(0xFFC2410C)
                        : const Color(0xFF15803D),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceEmptyState extends StatelessWidget {
  const _AttendanceEmptyState({required this.isToday});

  final bool isToday;

  @override
  Widget build(BuildContext context) {
    return _AttendanceCard(
      child: Column(
        children: [
          const Icon(Icons.event_busy_outlined,
              size: 40, color: Color(0xFF9CA3AF)),
          const SizedBox(height: 10),
          Text(
            isToday
                ? 'No attendance records for today yet.'
                : 'No attendance records for this day yet.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}

class _AttendanceErrorState extends StatelessWidget {
  const _AttendanceErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  const _AttendanceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
}

String _isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

int _number(Object? value) =>
    value is num ? value.round() : int.tryParse('$value') ?? 0;

String _formatTime(String? value) {
  if (value == null || value.isEmpty) return '--:--';
  return DateFormat.jm().format(DateTime.parse(value).toLocal());
}

String _statusCopy(String status) {
  switch (status) {
    case 'late':
      return 'Arrived late';
    case 'absent':
      return 'Marked absent';
    case 'in_progress':
      return 'Clocked in';
    case 'complete':
      return 'Arrived on time';
    default:
      return status.replaceAll('_', ' ');
  }
}
