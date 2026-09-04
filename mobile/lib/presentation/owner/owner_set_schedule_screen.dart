import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:aroll_mobile/presentation/owner/owner_schedule_pdf.dart';
import 'package:aroll_mobile/presentation/owner/owner_schedule_reuse.dart';
import 'package:aroll_mobile/presentation/owner/owner_schedule_table_style.dart';
import 'package:aroll_mobile/presentation/owner/owner_schedule_utils.dart';
import 'package:aroll_mobile/presentation/owner/owner_schedule_viewer_table.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

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
  bool _isRestDayWork = false;
  bool _loading = true;
  bool _saving = false;
  bool _downloading = false;
  String? _error;
  StateSetter? _assignSheetSetState;
  bool _assignSheetOpen = false;

  OwnerScheduleTableColors _tableColors = OwnerScheduleTableColors.defaults;
  List<String> _visibleDays = List<String>.from(ownerWeekdayLabels);
  String _defaultStart = '09:00';
  String _defaultEnd = '17:00';

  List<Map<String, dynamic>> _shifts = const [];
  List<Map<String, dynamic>> _employees = const [];
  List<Map<String, dynamic>> _assignments = const [];
  List<Map<String, dynamic>> _holidays = const [];
  final Map<String, Map<String, bool>> _leaveByEmployee = {};

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
        _repo.leaveAvailability(ownerDateKey(_selectedDate)),
      ]);
      if (!mounted) return;
      final leavePayload = results[4] as Map<String, dynamic>;
      final leaveRows = (leavePayload['employees'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>();
      _leaveByEmployee
        ..clear()
        ..addEntries(
          leaveRows.map(
            (row) => MapEntry('${row['employee_id']}', {
              'on_leave': row['on_leave'] == true,
              'leave_pending': row['leave_pending'] == true,
            }),
          ),
        );
      _refreshAssignUi(() {
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
      _refreshAssignUi(() {
        _loading = false;
        _error = 'Unable to load schedule data. Please try again.';
      });
    }
  }

  void _refreshAssignUi([VoidCallback? update]) {
    if (!mounted) return;
    setState(update ?? () {});
    _assignSheetSetState?.call(() {});
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
    final leave = _leaveByEmployee['${employee['id']}'] ?? const {};
    return ownerAvailabilityFor(
      employee: employee,
      selectedShift: _expandedShiftId == null
          ? null
          : _shiftById(_expandedShiftId!),
      assignmentsForDate: _assignmentsForDate,
      shifts: _shifts,
      editingAssignmentId: _editingAssignmentId,
      onLeave: leave['on_leave'] == true,
      leavePending: leave['leave_pending'] == true,
    );
  }

  bool _canSelect(OwnerEmployeeAvailability availability) {
    return availability == OwnerEmployeeAvailability.available ||
        availability == OwnerEmployeeAvailability.leavePending ||
        availability == OwnerEmployeeAvailability.onLeave;
  }

  void _selectDate(DateTime date) {
    setState(() {
      _selectedDate = DateTime(date.year, date.month, date.day);
      _weekStart = ownerWeekStart(_selectedDate);
    });
    if (_assignSheetOpen) {
      Navigator.of(context).maybePop();
    } else {
      setState(() {
        _expandedShiftId = null;
        _selectedEmployeeIds.clear();
        _editingAssignmentId = null;
        _isRestDayWork = false;
      });
    }
    // Reloads assignments + leave-availability for the selected date.
    _loadData();
  }

  Future<void> _openShiftAssignSheet(String shiftId) async {
    if (_assignSheetOpen) return;

    setState(() {
      _expandedShiftId = shiftId;
      _selectedEmployeeIds.clear();
      _editingAssignmentId = null;
      _isRestDayWork = false;
      _assignSheetOpen = true;
    });

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close shift assignment',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return SafeArea(
          child: StatefulBuilder(
            builder: (context, setModalState) {
              _assignSheetSetState = setModalState;
              return Center(
                child: Material(
                  color: Colors.transparent,
                  child: _buildShiftAssignModal(shiftId),
                ),
              );
            },
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );

    _assignSheetSetState = null;
    if (!mounted) return;
    setState(() {
      _assignSheetOpen = false;
      _expandedShiftId = null;
      _selectedEmployeeIds.clear();
      _editingAssignmentId = null;
      _isRestDayWork = false;
    });
  }

  Future<void> _toggleEmployee(String employeeId) async {
    final employee = _employees.firstWhere((item) => '${item['id']}' == employeeId);
    final availability = _availabilityFor(employee);
    if (!_canSelect(availability)) return;

    if (availability == OwnerEmployeeAvailability.onLeave &&
        !_selectedEmployeeIds.contains(employeeId)) {
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Employee on approved leave'),
          content: const Text(
            'This employee is currently on approved leave for the selected date(s).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'override'),
              child: const Text('Override Assignment'),
            ),
          ],
        ),
      );
      if (action != 'override' || !mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm override'),
          content: const Text(
            'Assign this employee during approved leave? The leave request will be kept and marked as assigned during leave.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    _refreshAssignUi(() {
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

    final needsOverride = _selectedEmployeeIds.any((id) {
      return _leaveByEmployee[id]?['on_leave'] == true;
    });

    _refreshAssignUi(() {
      _saving = true;
    });
    try {
      if (_editingAssignmentId != null) {
        await _repo.updateScheduleAssignment(
          assignmentId: _editingAssignmentId!,
          shiftId: _expandedShiftId!,
          workDate: _workDate,
          isRestDayWork: _isRestDayWork,
          overrideLeave: needsOverride,
        );
        _showMessage('Schedule updated');
      } else {
        final result = await _repo.assignSchedule(
          shiftId: _expandedShiftId!,
          workDate: _workDate,
          employeeIds: _selectedEmployeeIds.toList(growable: false),
          isRestDayWork: _isRestDayWork,
          overrideLeave: needsOverride,
        );
        final created = result['created'] as int? ?? 0;
        _showMessage(
          created > 0
              ? 'Assigned $created employee(s)'
              : 'No new assignments',
        );
      }
      if (!mounted) return;
      _refreshAssignUi(() {
        _selectedEmployeeIds.clear();
        _editingAssignmentId = null;
        _isRestDayWork = false;
      });
      await _loadData();
    } on DioException catch (error) {
      final detail = error.response?.data;
      if (detail is Map && detail['detail'] is Map) {
        final code = '${(detail['detail'] as Map)['code']}';
        if (code == 'approved_leave') {
          _showMessage(
            'This employee is currently on approved leave for the selected date(s).',
          );
          return;
        }
      }
      _showMessage(_dioMessage(error) ?? 'Failed to assign schedule');
    } catch (_) {
      _showMessage('Failed to assign schedule');
    } finally {
      if (mounted) {
        _refreshAssignUi(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _removeAssignment(String assignmentId) async {
    _refreshAssignUi(() {
      _saving = true;
    });
    try {
      await _repo.deleteScheduleAssignment(assignmentId);
      _showMessage('Schedule removed');
      await _loadData();
    } on DioException catch (_) {
      _showMessage('Failed to remove schedule');
    } finally {
      if (mounted) {
        _refreshAssignUi(() {
          _saving = false;
        });
      }
    }
  }

  void _startReassignment(String assignmentId, String shiftId) {
    final assignment = _assignments.cast<Map<String, dynamic>?>().firstWhere(
          (item) => '${item?['id']}' == assignmentId,
          orElse: () => null,
        );
    _refreshAssignUi(() {
      _editingAssignmentId = assignmentId;
      _expandedShiftId = shiftId;
      _selectedEmployeeIds.clear();
      _isRestDayWork = assignment?['is_rest_day_work'] == true;
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
        TextButton.icon(
          onPressed: () => context.push('/owner/setup-wizard?step=0'),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('New Shift'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primaryDark,
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
      child: Column(
        children: [
          Expanded(
            child: _loading
                ? appLoadingView(cardCount: 3)
                : _error != null
                    ? _ScheduleError(message: _error!, onRetry: _loadData)
                    : RefreshIndicator(
                        color: AppColors.primaryDark,
                        onRefresh: _loadData,
                        child: _mode == _ScheduleMode.assign
                            ? _buildAssignView()
                            : _buildViewerView(),
                      ),
          ),
          _ViewScheduleBar(
            saving: _saving,
            mode: _mode,
            onPressed: () {
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
          const SizedBox(height: 32),
          const OwnerEmptyState(
            'No shifts scheduled yet',
            description:
                'Create shifts in setup, then assign employees for the week.',
            icon: Icons.event_available_outlined,
          ),
          const SizedBox(height: 8),
          AppPrimaryButton(
            label: 'Add Shifts',
            onPressed: () => context.push('/owner/setup-wizard?step=0'),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        OwnerScheduleDateBanner(
          date: _selectedDate,
          weekStart: _weekStart,
          repo: _repo,
          assignmentCount: _assignments.length,
          onApplied: _loadData,
        ),
        const SizedBox(height: 14),
        Text('Select a date', style: appSectionTitleStyle()),
        const SizedBox(height: 4),
        Text(
          'Tap a day, then choose a shift and employees to assign.',
          style: appMutedStyle().copyWith(fontSize: 12),
        ),
        const SizedBox(height: 10),
        _ScheduleCalendar(
          selectedDate: _selectedDate,
          focusedMonth: _focusedMonth,
          onDateSelected: _selectDate,
          onMonthChanged: (month) => setState(() => _focusedMonth = month),
        ),
        if (_selectedHoliday != null) ...[
          const SizedBox(height: 12),
          _InfoBanner(
            icon: Icons.celebration_outlined,
            message:
                '${DateFormat('MMMM d').format(_selectedDate)} is a holiday: '
                '${_selectedHoliday!['name']}.',
          ),
        ],
        if (_editingAssignmentId != null) ...[
          const SizedBox(height: 12),
          _InfoBanner(
            icon: Icons.swap_horiz_rounded,
            message:
                'Reassigning schedule. Choose a new date or shift, then tap '
                'Set Schedule.',
            actionLabel: 'Cancel',
            onAction: () => _refreshAssignUi(() {
              _editingAssignmentId = null;
            }),
          ),
        ],
        const SizedBox(height: 18),
        Text('Work shifts', style: appSectionTitleStyle()),
        const SizedBox(height: 4),
        Text(
          'Tap a shift to assign or manage employees.',
          style: appMutedStyle().copyWith(fontSize: 12),
        ),
        const SizedBox(height: 10),
        ..._shifts.map(_buildShiftCard),
      ],
    );
  }

  Widget _buildShiftCard(Map<String, dynamic> shift) {
    final shiftId = '${shift['id']}';
    final assignments = _assignmentsByShift[shiftId] ?? const [];
    final start = formatOwnerShiftTime('${shift['start_time']}');
    final end = formatOwnerShiftTime('${shift['end_time']}');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _openShiftAssignSheet(shiftId),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.iconWell,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.schedule_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${shift['name']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$start – $end',
                        style: appMutedStyle().copyWith(fontSize: 12),
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
                    color: AppColors.chipFill,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${assignments.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShiftAssignModal(String shiftId) {
    final shift = _shiftById(shiftId);
    final assignments = _assignmentsByShift[shiftId] ?? const [];
    final start = formatOwnerShiftTime('${shift?['start_time'] ?? ''}');
    final end = formatOwnerShiftTime('${shift?['end_time'] ?? ''}');
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: 520),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.schedule_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${shift?['name'] ?? 'Shift'}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$start – $end · ${DateFormat.MMMd().format(_selectedDate)}',
                        style: appMutedStyle().copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (assignments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        'No employees assigned to this shift yet.',
                        style: appMutedStyle(),
                      ),
                    )
                  else
                    ...assignments.map((assignment) {
                      final employee = _employees
                          .cast<Map<String, dynamic>?>()
                          .firstWhere(
                            (item) => item?['id'] == assignment['employee_id'],
                            orElse: () => null,
                          );
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
                        child: _AssignedEmployeeRow(
                          name:
                              '${assignment['employee_name'] ?? 'Employee'}',
                          position: employee?['position_title'] as String?,
                          imageUrl:
                              employee?['profile_image_url'] as String?,
                          isRestDayWork:
                              assignment['is_rest_day_work'] == true,
                          onLeave: assignment['on_leave'] == true,
                          assignedDuringLeave:
                              assignment['assigned_during_leave'] == true,
                          leavePending: assignment['leave_pending'] == true,
                          saving: _saving,
                          onReassign: () => _startReassignment(
                            '${assignment['id']}',
                            shiftId,
                          ),
                          onRemove: () => _removeAssignment(
                            '${assignment['id']}',
                          ),
                        ),
                      );
                    }),
                  ..._buildEmployeePickerSections(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.fieldFill,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            activeThumbColor: AppColors.primary,
                            title: const Text(
                              'Approved rest day work',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              'Premium applies when the employee times in',
                              style: appMutedStyle().copyWith(fontSize: 11),
                            ),
                            value: _isRestDayWork,
                            onChanged: _saving
                                ? null
                                : (value) => _refreshAssignUi(() {
                                      _isRestDayWork = value;
                                    }),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _saving ||
                                    (_selectedEmployeeIds.isEmpty &&
                                        _editingAssignmentId == null)
                                ? null
                                : _saveSchedule,
                            style: appPrimaryButtonStyle().copyWith(
                              minimumSize: const WidgetStatePropertyAll(
                                Size(0, 44),
                              ),
                            ),
                            child: Text(
                              _saving
                                  ? 'Saving...'
                                  : _editingAssignmentId != null
                                      ? 'Update Schedule'
                                      : 'Set Schedule',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadSchedulePdf(List<Map<String, dynamic>> rows) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final businessName =
          sl<AppState>().session?.businessName.trim().isNotEmpty == true
              ? sl<AppState>().session!.businessName
              : 'Business';
      final path = await generateOwnerSchedulePdf(
        businessName: businessName,
        weekStart: _weekStart,
        rows: rows,
        colors: _tableColors,
        visibleDays: _visibleDays,
        defaultStart: _defaultStart,
        defaultEnd: _defaultEnd,
      );
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: 'application/pdf')],
          subject: 'Weekly Schedule',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _showMessage('Unable to download schedule PDF.');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _openCustomizeTable(List<Map<String, dynamic>> rows) {
    return showOwnerScheduleCustomizeSheet(
      context: context,
      colors: _tableColors,
      visibleDays: _visibleDays,
      defaultStart: _defaultStart,
      defaultEnd: _defaultEnd,
      previewRows: rows,
      weekStart: _weekStart,
      onApply: ({
        required OwnerScheduleTableColors colors,
        required List<String> visibleDays,
        required String defaultStart,
        required String defaultEnd,
      }) {
        setState(() {
          _tableColors = colors;
          _visibleDays = visibleDays;
          _defaultStart = defaultStart;
          _defaultEnd = defaultEnd;
        });
      },
    );
  }

  Widget _buildViewerView() {
    final rows = ownerBuildScheduleMatrix(
      employees: _employees,
      assignments: _assignments,
      weekStart: _weekStart,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Week view', style: appSectionTitleStyle()),
                  const SizedBox(height: 4),
                  Text(
                    'Review who is scheduled across the week.',
                    style: appMutedStyle().copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Download schedule',
              onPressed: _downloading ? null : () => _downloadSchedulePdf(rows),
              icon: _downloading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded),
              color: AppColors.primaryDark,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
            boxShadow: appCardShadow,
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () {
                  setState(() {
                    _weekStart = _weekStart.subtract(const Duration(days: 7));
                  });
                  _loadData();
                },
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  formatOwnerWeekRange(_weekStart),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _weekStart = _weekStart.add(const Duration(days: 7));
                  });
                  _loadData();
                },
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => _openCustomizeTable(rows),
            child: const Text('Edit Table'),
          ),
        ),
        const SizedBox(height: 4),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: OwnerEmptyState(
              'No schedule records yet',
              description:
                  'Assigned shifts for this week will show up in the viewer.',
              icon: Icons.calendar_month_outlined,
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
              boxShadow: appCardShadow,
            ),
            clipBehavior: Clip.antiAlias,
            child: OwnerColorScheduleTable(
              rows: rows,
              weekStart: _weekStart,
              colors: _tableColors,
              visibleDays: _visibleDays,
              defaultStart: _defaultStart,
              defaultEnd: _defaultEnd,
            ),
          ),
      ],
    );
  }

  String _availabilityLabel(OwnerEmployeeAvailability availability) {
    switch (availability) {
      case OwnerEmployeeAvailability.available:
        return 'Available';
      case OwnerEmployeeAvailability.leavePending:
        return 'Leave Pending';
      case OwnerEmployeeAvailability.onLeave:
        return 'On Leave';
      case OwnerEmployeeAvailability.assigned:
        return 'Already assigned';
      case OwnerEmployeeAvailability.conflict:
        return 'Conflict';
      case OwnerEmployeeAvailability.activationRequired:
        return 'Activation required';
    }
  }

  List<Widget> _buildEmployeePickerSections() {
    final available = <Map<String, dynamic>>[];
    final onLeave = <Map<String, dynamic>>[];
    final activationRequired = <Map<String, dynamic>>[];
    for (final employee in _employees) {
      final availability = _availabilityFor(employee);
      if (availability == OwnerEmployeeAvailability.onLeave) {
        onLeave.add(employee);
      } else if (availability == OwnerEmployeeAvailability.activationRequired) {
        activationRequired.add(employee);
      } else {
        available.add(employee);
      }
    }

    Widget section(String title, List<Map<String, dynamic>> employees) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text(
              title,
              style: appSectionTitleStyle().copyWith(fontSize: 14),
            ),
          ),
          if (employees.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('None', style: appMutedStyle().copyWith(fontSize: 12)),
            ),
          ...employees.map((employee) {
            final availability = _availabilityFor(employee);
            final employeeId = '${employee['id']}';
            final selected = _selectedEmployeeIds.contains(employeeId);
            final enabled = _canSelect(availability);
            return Opacity(
              opacity: enabled ? 1 : 0.62,
              child: Container(
                margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withValues(alpha: 0.06)
                      : AppColors.fieldFill,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected
                        ? AppColors.primary.withValues(alpha: 0.35)
                        : AppColors.border,
                  ),
                ),
                child: ListTile(
                  onTap: enabled ? () => _toggleEmployee(employeeId) : null,
                  leading: EmployeeAvatar(
                    imageUrl: employee['profile_image_url'] as String?,
                    name: '${employee['full_name'] ?? 'Employee'}',
                    size: 40,
                  ),
                  title: Text(
                    '${employee['full_name'] ?? 'Employee'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _availabilityLabel(availability),
                          style: appMutedStyle().copyWith(fontSize: 12),
                        ),
                      ),
                      if (availability == OwnerEmployeeAvailability.leavePending)
                        const _SoftChip(
                          label: 'Leave Pending',
                          background: Color(0xFFFFFBEB),
                          foreground: Color(0xFFB45309),
                          border: Color(0xFFFDE68A),
                        ),
                    ],
                  ),
                  trailing: enabled
                      ? Icon(
                          selected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: selected
                              ? AppColors.primary
                              : const Color(0xFF9CA3AF),
                        )
                      : _AvailabilityChip(availability: availability),
                ),
              ),
            );
          }),
        ],
      );
    }

    return [
      section('Available Employees', available),
      if (activationRequired.isNotEmpty)
        section('Activation required', activationRequired),
      section('Employees On Leave', onLeave),
    ];
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
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
              height: 1,
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
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: appCardShadow,
      ),
      child: Column(
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                IconButton(
                  onPressed: () => onMonthChanged(
                    DateTime(focusedMonth.year, focusedMonth.month - 1),
                  ),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.chevron_left_rounded, size: 18),
                ),
                Expanded(
                  child: Text(
                    DateFormat.yMMMM().format(focusedMonth),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => onMonthChanged(
                    DateTime(focusedMonth.year, focusedMonth.month + 1),
                  ),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.chevron_right_rounded, size: 18),
                ),
              ],
            ),
          ),
          GridView.builder(
            itemCount: cells.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: 28,
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
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;

    return InkWell(
      onTap: () => onTap(date),
      customBorder: const CircleBorder(),
      child: Center(
        child: Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : null,
            shape: BoxShape.circle,
            border: !selected && isToday
                ? Border.all(color: AppColors.primary.withValues(alpha: 0.45))
                : null,
          ),
          child: Text(
            '${date.day}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1,
              color: selected
                  ? Colors.white
                  : isToday
                      ? AppColors.primaryDark
                      : AppColors.textPrimary,
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
      OwnerEmployeeAvailability.leavePending => (
          'Leave Pending',
          const Color(0xFFFFFBEB),
          const Color(0xFFB45309),
          const Color(0xFFFDE68A),
        ),
      OwnerEmployeeAvailability.onLeave => (
          'On Leave',
          const Color(0xFFDBEAFE),
          const Color(0xFF1D4ED8),
          const Color(0xFFBFDBFE),
        ),
      OwnerEmployeeAvailability.assigned => (
          'Assigned',
          const Color(0xFFF3E8FF),
          const Color(0xFF7E22CE),
          const Color(0xFFE9D5FF),
        ),
      OwnerEmployeeAvailability.conflict => (
          'Conflict',
          const Color(0xFFFEF2F2),
          const Color(0xFFB91C1C),
          const Color(0xFFFECACA),
        ),
      OwnerEmployeeAvailability.activationRequired => (
          'Activation required',
          const Color(0xFFF1F5F9),
          const Color(0xFF475569),
          const Color(0xFFE2E8F0),
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

class _ViewScheduleBar extends StatelessWidget {
  const _ViewScheduleBar({
    required this.saving,
    required this.mode,
    required this.onPressed,
  });

  final bool saving;
  final _ScheduleMode mode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isAssign = mode == _ScheduleMode.assign;
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        decoration: BoxDecoration(
          color: AppColors.white.withValues(alpha: 0.96),
          border: const Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 40,
          child: OutlinedButton(
            onPressed: saving ? null : onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryDark,
              backgroundColor: const Color(0xFFF3F6FA),
              side: const BorderSide(color: Color(0xFFD7E0EA)),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            child: Text(isAssign ? 'View Schedule' : 'Assign Schedule'),
          ),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF92400E)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF92400E),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

class _AssignedEmployeeRow extends StatelessWidget {
  const _AssignedEmployeeRow({
    required this.name,
    required this.position,
    required this.imageUrl,
    required this.isRestDayWork,
    required this.onLeave,
    required this.assignedDuringLeave,
    required this.leavePending,
    required this.saving,
    required this.onReassign,
    required this.onRemove,
  });

  final String name;
  final String? position;
  final String? imageUrl;
  final bool isRestDayWork;
  final bool onLeave;
  final bool assignedDuringLeave;
  final bool leavePending;
  final bool saving;
  final VoidCallback onReassign;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          EmployeeAvatar(imageUrl: imageUrl, name: name, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  softWrap: true,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    height: 1.3,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  position ?? 'Assigned',
                  style: appMutedStyle().copyWith(fontSize: 12),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (isRestDayWork)
                      const _SoftChip(
                        label: 'Rest day',
                        background: Color(0xFFF0F9FF),
                        foreground: Color(0xFF075985),
                        border: Color(0xFFBAE6FD),
                      ),
                    _SoftChip(
                      label: onLeave ? 'On Leave' : 'Assigned',
                      background: onLeave
                          ? const Color(0xFFDBEAFE)
                          : const Color(0xFFEFF6FF),
                      foreground: const Color(0xFF1D4ED8),
                      border: const Color(0xFFBFDBFE),
                    ),
                    if (assignedDuringLeave)
                      const _SoftChip(
                        label: 'Assigned During Leave',
                        background: Color(0xFFFFF7ED),
                        foreground: Color(0xFFC2410C),
                        border: Color(0xFFFDBA74),
                      ),
                    if (leavePending)
                      const _SoftChip(
                        label: 'Leave Pending',
                        background: Color(0xFFFFFBEB),
                        foreground: Color(0xFFB45309),
                        border: Color(0xFFFDE68A),
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Reassign',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            padding: EdgeInsets.zero,
            onPressed: saving ? null : onReassign,
            icon: const Icon(Icons.edit_outlined, size: 18),
          ),
          IconButton(
            tooltip: 'Remove',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            padding: EdgeInsets.zero,
            onPressed: saving ? null : onRemove,
            icon: const Icon(Icons.delete_outline, size: 18),
          ),
        ],
      ),
    );
  }
}

class _SoftChip extends StatelessWidget {
  const _SoftChip({
    required this.label,
    required this.background,
    required this.foreground,
    required this.border,
  });

  final String label;
  final Color background;
  final Color foreground;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
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
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.iconWell,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.event_busy_outlined,
                color: AppColors.primary,
                size: 28,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: appBodyStyle(),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
