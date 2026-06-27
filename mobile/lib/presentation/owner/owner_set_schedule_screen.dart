import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:aroll_mobile/presentation/owner/owner_mobile.dart';
import 'package:aroll_mobile/presentation/owner/owner_schedule_utils.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

enum _ScheduleMode { assign, viewer }

class OwnerScheduleScreen extends StatefulWidget {
  const OwnerScheduleScreen({super.key});

  @override
  State<OwnerScheduleScreen> createState() => _OwnerScheduleScreenState();
}

class _OwnerScheduleScreenState extends State<OwnerScheduleScreen> {
  final _repo = sl<OwnerRepository>();

  _ScheduleMode _mode = _ScheduleMode.assign;
  late DateTime _selectedDate;
  late DateTime _focusedMonth;
  late DateTime _weekStart;

  String? _expandedShiftId;
  String? _editingAssignmentId;
  final Set<String> _selectedEmployeeIds = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<Map<String, dynamic>> _shifts = const [];
  List<Map<String, dynamic>> _employees = const [];
  List<Map<String, dynamic>> _assignments = const [];
  List<Map<String, dynamic>> _holidays = const [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _focusedMonth = DateTime(now.year, now.month);
    _weekStart = ownerWeekStart(_selectedDate);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repo.shifts(),
        _repo.employees(),
        _repo.holidays(),
        _repo.weeklySchedule(_weekStart),
      ]);
      if (!mounted) return;
      setState(() {
        _shifts = results[0] as List<Map<String, dynamic>>;
        _employees = (results[1] as List<Map<String, dynamic>>)
            .where((employee) => employee['status'] == 'active')
            .toList(growable: false);
        _holidays = results[2] as List<Map<String, dynamic>>;
        _assignments = ((results[3] as Map<String, dynamic>)['assignments']
                as List<dynamic>? ??
            const [])
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load schedule data. Please try again.';
      });
    }
  }

  String get _workDate => ownerDateKey(_selectedDate);

  List<Map<String, dynamic>> get _assignmentsForDate => _assignments
      .where((assignment) => assignment['work_date'] == _workDate)
      .toList(growable: false);

  Map<String, List<Map<String, dynamic>>> get _assignmentsByShift {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final assignment in _assignmentsForDate) {
      final shiftId = '${assignment['shift_id']}';
      map.putIfAbsent(shiftId, () => []).add(assignment);
    }
    return map;
  }

  Map<String, dynamic>? get _selectedHoliday {
    for (final holiday in _holidays) {
      if (holiday['is_active'] == true &&
          holiday['holiday_date'] == _workDate) {
        return holiday;
      }
    }
    return null;
  }

  Map<String, dynamic>? _shiftById(String id) {
    for (final shift in _shifts) {
      if ('${shift['id']}' == id) return shift;
    }
    return null;
  }

  OwnerEmployeeAvailability _availabilityFor(Map<String, dynamic> employee) {
    return ownerAvailabilityFor(
      employee: employee,
      selectedShift: _expandedShiftId == null
          ? null
          : _shiftById(_expandedShiftId!),
      assignmentsForDate: _assignmentsForDate,
      shifts: _shifts,
      editingAssignmentId: _editingAssignmentId,
    );
  }

  void _selectDate(DateTime date) {
    setState(() {
      _selectedDate = DateTime(date.year, date.month, date.day);
      _weekStart = ownerWeekStart(_selectedDate);
      _expandedShiftId = null;
      _selectedEmployeeIds.clear();
      _editingAssignmentId = null;
    });
    _loadData();
  }

  void _toggleShiftExpansion(String shiftId) {
    setState(() {
      if (_expandedShiftId == shiftId) {
        _expandedShiftId = null;
        _selectedEmployeeIds.clear();
      } else {
        _expandedShiftId = shiftId;
        _selectedEmployeeIds.clear();
        _editingAssignmentId = null;
      }
    });
  }

  void _toggleEmployee(String employeeId) {
    final employee = _employees.firstWhere((item) => '${item['id']}' == employeeId);
    if (_availabilityFor(employee) != OwnerEmployeeAvailability.available) {
      return;
    }
    setState(() {
      if (_selectedEmployeeIds.contains(employeeId)) {
        _selectedEmployeeIds.remove(employeeId);
      } else {
        _selectedEmployeeIds.add(employeeId);
      }
    });
  }

  Future<void> _saveSchedule() async {
    if (_expandedShiftId == null || _selectedEmployeeIds.isEmpty) {
      _showMessage('Select a shift and at least one available employee.');
      return;
    }

    setState(() => _saving = true);
    try {
      if (_editingAssignmentId != null) {
        await _repo.updateScheduleAssignment(
          assignmentId: _editingAssignmentId!,
          shiftId: _expandedShiftId!,
          workDate: _workDate,
        );
        _showMessage('Schedule updated');
      } else {
        final result = await _repo.assignSchedule(
          shiftId: _expandedShiftId!,
          workDate: _workDate,
          employeeIds: _selectedEmployeeIds.toList(growable: false),
        );
        final created = result['created'] as int? ?? 0;
        _showMessage(
          created > 0
              ? 'Assigned $created employee(s)'
              : 'No new assignments',
        );
      }
      if (!mounted) return;
      setState(() {
        _selectedEmployeeIds.clear();
        _editingAssignmentId = null;
      });
      await _loadData();
    } on DioException catch (error) {
      _showMessage(_dioMessage(error) ?? 'Failed to assign schedule');
    } catch (_) {
      _showMessage('Failed to assign schedule');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeAssignment(String assignmentId) async {
    setState(() => _saving = true);
    try {
      await _repo.deleteScheduleAssignment(assignmentId);
      _showMessage('Schedule removed');
      await _loadData();
    } on DioException catch (_) {
      _showMessage('Failed to remove schedule');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _startReassignment(String assignmentId, String shiftId) {
    setState(() {
      _editingAssignmentId = assignmentId;
      _expandedShiftId = shiftId;
      _selectedEmployeeIds.clear();
    });
    _showMessage('Choose a new date or shift, then tap Set Schedule.');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String? _dioMessage(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return OwnerShell(
      selectedIndex: 0,
      showBackButton: true,
      title: 'Schedule',
      actions: [
        TextButton(
          onPressed: () => context.push('/owner/setup-wizard?step=0'),
          child: const Text('New Shift'),
        ),
      ],
      child: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _ScheduleError(message: _error!, onRetry: _loadData)
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: _mode == _ScheduleMode.assign
                            ? _buildAssignView()
                            : _buildViewerView(),
                      ),
          ),
          _BottomActions(
            saving: _saving,
            mode: _mode,
            onSetSchedule: _mode == _ScheduleMode.assign ? _saveSchedule : null,
            onViewSchedule: () {
              setState(() {
                _mode = _mode == _ScheduleMode.assign
                    ? _ScheduleMode.viewer
                    : _ScheduleMode.assign;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAssignView() {
    if (_shifts.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 48),
          const Icon(Icons.schedule_outlined, size: 56, color: Color(0xFF6B7280)),
          const SizedBox(height: 16),
          const Text(
            'No shifts have been configured yet.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => context.push('/owner/setup-wizard?step=0'),
            child: const Text('Add Shifts'),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        const Text(
          'Select a date',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 6),
        _ScheduleCalendar(
          selectedDate: _selectedDate,
          focusedMonth: _focusedMonth,
          onDateSelected: _selectDate,
          onMonthChanged: (month) => setState(() => _focusedMonth = month),
        ),
        if (_selectedHoliday != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Text(
              'Holiday Notice: ${DateFormat('MMMM d').format(_selectedDate)} is a '
              'holiday: ${_selectedHoliday!['name']}.',
              style: const TextStyle(color: Color(0xFF92400E), fontSize: 13),
            ),
          ),
        ],
        if (_editingAssignmentId != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Reassigning schedule. Choose a new date or shift, then tap '
                    'Set Schedule.',
                    style: TextStyle(color: Color(0xFF92400E), fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _editingAssignmentId = null),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        ..._shifts.map(_buildShiftCard),
      ],
    );
  }

  Widget _buildShiftCard(Map<String, dynamic> shift) {
    final shiftId = '${shift['id']}';
    final assignments = _assignmentsByShift[shiftId] ?? const [];
    final expanded = _expandedShiftId == shiftId;
    final start = formatOwnerShiftTime('${shift['start_time']}');
    final end = formatOwnerShiftTime('${shift['end_time']}');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _toggleShiftExpansion(shiftId),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${shift['name']}: $start - $end',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _toggleShiftExpansion(shiftId),
                    child: const Text('Select Employee'),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1),
            if (assignments.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No employees assigned to this shift yet.',
                  style: TextStyle(color: Color(0xFF6B7280)),
                ),
              )
            else
              ...assignments.map((assignment) {
                final employee = _employees.cast<Map<String, dynamic>?>().firstWhere(
                      (item) => item?['id'] == assignment['employee_id'],
                      orElse: () => null,
                    );
                return ListTile(
                  leading: EmployeeAvatar(
                    imageUrl: employee?['profile_image_url'] as String?,
                    name: '${assignment['employee_name'] ?? 'Employee'}',
                    size: 40,
                  ),
                  title: Text('${assignment['employee_name'] ?? 'Employee'}'),
                  subtitle: Text(employee?['position_title'] as String? ?? 'Assigned'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: const Text(
                          'Assigned',
                          style: TextStyle(
                            color: Color(0xFF1D4ED8),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Reassign',
                        onPressed: _saving
                            ? null
                            : () => _startReassignment(
                                  '${assignment['id']}',
                                  shiftId,
                                ),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        onPressed: _saving
                            ? null
                            : () => _removeAssignment('${assignment['id']}'),
                        icon: const Icon(Icons.delete_outline, size: 18),
                      ),
                    ],
                  ),
                );
              }),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Available employees',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            ..._employees.map((employee) {
              final availability = _availabilityFor(employee);
              final employeeId = '${employee['id']}';
              final selected = _selectedEmployeeIds.contains(employeeId);
              final enabled =
                  availability == OwnerEmployeeAvailability.available;

              return Opacity(
                opacity: enabled ? 1 : 0.65,
                child: ListTile(
                  onTap: enabled ? () => _toggleEmployee(employeeId) : null,
                  leading: EmployeeAvatar(
                    imageUrl: employee['profile_image_url'] as String?,
                    name: '${employee['full_name'] ?? 'Employee'}',
                    size: 40,
                  ),
                  title: Text('${employee['full_name'] ?? 'Employee'}'),
                  subtitle: Text(_availabilityLabel(availability)),
                  trailing: enabled
                      ? Icon(
                          selected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: selected
                              ? const Color(0xFF1E466E)
                              : const Color(0xFF9CA3AF),
                        )
                      : _AvailabilityChip(availability: availability),
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildViewerView() {
    final rows = ownerBuildScheduleMatrix(
      employees: _employees,
      assignments: _assignments,
      weekStart: _weekStart,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () {
                setState(() {
                  _weekStart = _weekStart.subtract(const Duration(days: 7));
                });
                _loadData();
              },
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                formatOwnerWeekRange(_weekStart),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              onPressed: () {
                setState(() {
                  _weekStart = _weekStart.add(const Duration(days: 7));
                });
                _loadData();
              },
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text(
              'No schedule records found.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _ScheduleViewerTable(
              rows: rows,
              weekStart: _weekStart,
            ),
          ),
      ],
    );
  }

  String _availabilityLabel(OwnerEmployeeAvailability availability) {
    switch (availability) {
      case OwnerEmployeeAvailability.available:
        return 'Available';
      case OwnerEmployeeAvailability.assigned:
        return 'Already assigned';
      case OwnerEmployeeAvailability.conflict:
        return 'Conflict';
    }
  }
}

class _ScheduleCalendar extends StatelessWidget {
  const _ScheduleCalendar({
    required this.selectedDate,
    required this.focusedMonth,
    required this.onDateSelected,
    required this.onMonthChanged,
  });

  final DateTime selectedDate;
  final DateTime focusedMonth;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<DateTime> onMonthChanged;

  @override
  Widget build(BuildContext context) {
    final monthStart = DateTime(focusedMonth.year, focusedMonth.month);
    final daysInMonth = DateUtils.getDaysInMonth(focusedMonth.year, focusedMonth.month);
    final firstWeekday = monthStart.weekday % 7;
    final cells = <Widget>[
      for (final label in ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'])
        Center(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
        ),
      for (var i = 0; i < firstWeekday; i++) const SizedBox.shrink(),
      for (var day = 1; day <= daysInMonth; day++)
        _CalendarDay(
          date: DateTime(focusedMonth.year, focusedMonth.month, day),
          selected: _sameDay(
            DateTime(focusedMonth.year, focusedMonth.month, day),
            selectedDate,
          ),
          onTap: onDateSelected,
        ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => onMonthChanged(
                  DateTime(focusedMonth.year, focusedMonth.month - 1),
                ),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.chevron_left, size: 20),
              ),
              Expanded(
                child: Text(
                  DateFormat.yMMMM().format(focusedMonth),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => onMonthChanged(
                  DateTime(focusedMonth.year, focusedMonth.month + 1),
                ),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.chevron_right, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 2),
          GridView.builder(
            itemCount: cells.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.35,
            ),
            itemBuilder: (context, index) => cells[index],
          ),
        ],
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.date,
    required this.selected,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onTap(date),
      customBorder: const CircleBorder(),
      child: Center(
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF1E466E) : null,
            shape: BoxShape.circle,
          ),
          child: Text(
            '${date.day}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : const Color(0xFF111827),
            ),
          ),
        ),
      ),
    );
  }
}

class _AvailabilityChip extends StatelessWidget {
  const _AvailabilityChip({required this.availability});

  final OwnerEmployeeAvailability availability;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg, border) = switch (availability) {
      OwnerEmployeeAvailability.available => (
          'Available',
          const Color(0xFFECFDF5),
          const Color(0xFF047857),
          const Color(0xFFD1FAE5),
        ),
      OwnerEmployeeAvailability.assigned => (
          'Assigned',
          const Color(0xFFEFF6FF),
          const Color(0xFF1D4ED8),
          const Color(0xFFBFDBFE),
        ),
      OwnerEmployeeAvailability.conflict => (
          'Conflict',
          const Color(0xFFFFFBEB),
          const Color(0xFFB45309),
          const Color(0xFFFDE68A),
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ScheduleViewerTable extends StatelessWidget {
  const _ScheduleViewerTable({
    required this.rows,
    required this.weekStart,
  });

  final List<Map<String, dynamic>> rows;
  final DateTime weekStart;

  @override
  Widget build(BuildContext context) {
    final weekDays = ownerWeekDays(weekStart);
    return DataTable(
      headingRowColor: WidgetStateProperty.all(const Color(0xFF1E466E)),
      columns: [
        const DataColumn(
          label: Text('Employee', style: TextStyle(color: Colors.white)),
        ),
        ...ownerWeekdayLabels.map(
          (label) => DataColumn(
            label: Text(label, style: const TextStyle(color: Colors.white)),
          ),
        ),
      ],
      rows: rows.map((row) {
        final employee = row['employee'] as Map<String, dynamic>;
        final cells = row['cells'] as List<List<Map<String, dynamic>>>;
        return DataRow(
          cells: [
            DataCell(Text('${employee['full_name'] ?? 'Employee'}')),
            ...List.generate(weekDays.length, (index) {
              final dayAssignments = cells[index];
              final label = dayAssignments.isEmpty
                  ? 'OFF'
                  : dayAssignments
                      .map(
                        (assignment) =>
                            '${formatOwnerShiftTime('${assignment['shift_start_time']}')}-'
                            '${formatOwnerShiftTime('${assignment['shift_end_time']}')}',
                      )
                      .join(', ');
              return DataCell(Text(label, style: const TextStyle(fontSize: 11)));
            }),
          ],
        );
      }).toList(),
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.saving,
    required this.mode,
    required this.onViewSchedule,
    this.onSetSchedule,
  });

  final bool saving;
  final _ScheduleMode mode;
  final VoidCallback? onSetSchedule;
  final VoidCallback onViewSchedule;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: saving ? null : onSetSchedule,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Color(0xFF93C5FD)),
                foregroundColor: const Color(0xFF1E466E),
              ),
              child: Text(saving ? 'Saving...' : 'Set Schedule'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: saving ? null : onViewSchedule,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1E466E),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                mode == _ScheduleMode.assign ? 'View Schedule' : 'Assign Schedule',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleError extends StatelessWidget {
  const _ScheduleError({required this.message, required this.onRetry});

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
