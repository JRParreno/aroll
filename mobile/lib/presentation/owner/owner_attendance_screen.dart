import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/theme/business_brand_theme.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/utils/business_time.dart';
import 'package:aroll_mobile/presentation/shared/tenant_mode_banner.dart';
import 'package:aroll_mobile/core/face/face_api_errors.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_ui.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

String _formatTime(String? value, {String? timeZone}) {
  return formatBusinessAttendanceTimeIso(value, timeZone: timeZone);
}

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
  List<Map<String, dynamic>> _pendingCorrections = const [];
  List<Map<String, dynamic>> _pendingOtApprovals = const [];
  Map<String, String?> _profileImages = const {};
  String? _reportTimezone;
  String? _busyCorrectionId;
  String? _busyOtId;
  String? _rejectingCorrectionId;
  final _rejectNoteController = TextEditingController();

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
    _rejectNoteController.dispose();
    super.dispose();
  }

  String? get _attendanceTimeZone =>
      sl<AppState>().session?.timezone ?? _reportTimezone;

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repo.attendance(date: _isoDate(_selectedDate)),
        _repo.employees(),
        _repo.attendanceCorrections(status: 'pending'),
        _repo.overtimeApprovals(status: 'pending'),
      ]);
      if (!mounted) return;

      final attendance = results[0] as Map<String, dynamic>;
      final employees = results[1] as List<Map<String, dynamic>>;
      final corrections = results[2] as List<Map<String, dynamic>>;
      final otApprovals = results[3] as List<Map<String, dynamic>>;

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
        _pendingCorrections = corrections;
        _pendingOtApprovals = otApprovals;
        _profileImages = images;
        _reportTimezone = attendance['timezone'] as String?;
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

  void _showEmployeeDetails(Map<String, dynamic> record) {
    final name = '${record['employee_name'] ?? ''}'.trim();
    final role = '${record['position_title'] ?? ''}'.trim();
    final employment = _employmentLabel(record['employment_type']);
    final rate = _rateLabel(record['daily_rate']);
    final recordImage = '${record['profile_image_url'] ?? ''}'.trim();
    final imageUrl =
        recordImage.isNotEmpty ? recordImage : _profileImages[name];
    final timeIn = _formatTime(
      record['time_in'] as String?,
      timeZone: _attendanceTimeZone,
    );
    final timeOut = _formatTime(
      record['time_out'] as String?,
      timeZone: _attendanceTimeZone,
    );
    final rows = <(String, String)>[
      ('Complete Name', name.isEmpty ? 'Not set' : name),
      ('Role', role.isEmpty ? 'Not set' : role),
      ('Employment', employment),
      ('Rate', rate),
      ('Time In', timeIn),
      ('Time Out', timeOut),
    ];

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  elevation: 1,
                  child: IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SetupSurfaceCard(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        EmployeeAvatar(
                          imageUrl: imageUrl,
                          name: name.isEmpty ? 'Employee' : name,
                          size: 56,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Employee Details',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Information from your employee records.',
                                style:
                                    appMutedStyle().copyWith(fontSize: 11.5),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    for (var i = 0; i < rows.length; i++) ...[
                      if (i > 0) ...[
                        const SizedBox(height: 8),
                        const Divider(height: 1, color: Color(0xFFE8EEF4)),
                        const SizedBox(height: 8),
                      ],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              rows[i].$1,
                              style: appMutedStyle().copyWith(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              rows[i].$2,
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _approveCorrection(String requestId) async {
    setState(() => _busyCorrectionId = requestId);
    try {
      await _repo.approveAttendanceCorrection(requestId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Correction approved. Attendance updated.'),
        ),
      );
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            faceApiErrorMessage(
              error,
              fallback: 'Could not approve this correction.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyCorrectionId = null);
    }
  }

  Future<void> _rejectCorrection(String requestId) async {
    final note = _rejectNoteController.text.trim();
    if (note.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a short rejection reason.')),
      );
      return;
    }
    setState(() => _busyCorrectionId = requestId);
    try {
      await _repo.rejectAttendanceCorrection(
        requestId: requestId,
        reviewNote: note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Correction rejected.')),
      );
      setState(() {
        _rejectingCorrectionId = null;
        _rejectNoteController.clear();
      });
      await _loadData();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not reject this correction.')),
      );
    } finally {
      if (mounted) setState(() => _busyCorrectionId = null);
    }
  }

  Future<void> _approveOt(String recordId) async {
    setState(() => _busyOtId = recordId);
    try {
      await _repo.approveOvertime(recordId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Overtime approved. It will be included as payable OT.'),
        ),
      );
      await _loadData();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not approve overtime.')),
      );
    } finally {
      if (mounted) setState(() => _busyOtId = null);
    }
  }

  Future<void> _rejectOt(String recordId) async {
    setState(() => _busyOtId = recordId);
    try {
      await _repo.rejectOvertime(recordId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Overtime rejected. Worked time is kept; OT is not paid.',
          ),
        ),
      );
      await _loadData();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not reject overtime.')),
      );
    } finally {
      if (mounted) setState(() => _busyOtId = null);
    }
  }

  Future<void> _completeAttendance(Map<String, dynamic> record) async {
    final dateKey = '${record['date'] ?? _selectedIsoDate}';
    TimeOfDay initial = TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: 'Select Time Out',
    );
    if (picked == null || !mounted) return;

    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete Attendance'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Save Time Out at ${picked.format(context)} for '
              '${record['employee_name'] ?? 'employee'}?',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'Employee forgot to time out',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final reason = reasonController.text;
    reasonController.dispose();
    if (confirmed != true || !mounted) return;

    final parts = dateKey.split('-');
    final year =
        int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? _selectedDate.year;
    final month =
        int.tryParse(parts.length > 1 ? parts[1] : '') ?? _selectedDate.month;
    final day =
        int.tryParse(parts.length > 2 ? parts[2] : '') ?? _selectedDate.day;
    final timeOut = DateTime(year, month, day, picked.hour, picked.minute);

    try {
      await _repo.completeAttendance(
        recordId: '${record['id']}',
        timeOut: timeOut,
        reason: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Attendance completed. Payroll will update automatically.'),
        ),
      );
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            faceApiErrorMessage(
              error,
              fallback: 'Could not complete attendance.',
            ),
          ),
        ),
      );
    }
  }

  String get _selectedIsoDate => _isoDate(_selectedDate);

  bool get _isToday => _isoDate(DateTime.now()) == _selectedIsoDate;

  Map<String, int> get _chartMetrics {
    // Same source as the employee list (attendance report for selected date).
    final dayRecords =
        _records.where((record) => record['date'] == _selectedIsoDate);
    var onTime = 0;
    var late = 0;
    var absent = 0;
    for (final record in dayRecords) {
      final status = '${record['status'] ?? ''}';
      if (status == 'absent') {
        absent += 1;
      } else if (status == 'incomplete' ||
          status == 'on_leave' ||
          status == 'holiday_paid') {
        // Match web attendance summary treatment for non-punch statuses.
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
      final status = '${record['status'] ?? ''}';
      final hasPunch = record['time_in'] != null;
      final isListedStatus = status == 'absent' ||
          status == 'on_leave' ||
          status == 'holiday_paid' ||
          status == 'incomplete';
      if (!hasPunch && !isListedStatus) return false;
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
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return OwnerShell(
      selectedIndex: 1,
      title: 'Attendance',
      actions: [
        IconButton(
          tooltip: 'Shift History',
          onPressed: () => context.push('/owner/attendance/shift-history'),
          icon: const Icon(Icons.history_rounded),
        ),
      ],
      child: _loading
          ? appLoadingView(cardCount: 4)
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
                        onToday: () {
                          setState(() => _selectedDate = DateTime.now());
                          _loadData();
                        },
                        correctionsButton: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _PendingCorrectionsButton(
                              items: _pendingCorrections,
                              timeZone: _attendanceTimeZone,
                              busyId: _busyCorrectionId,
                              rejectingId: _rejectingCorrectionId,
                              rejectNoteController: _rejectNoteController,
                              onApprove: _approveCorrection,
                              onOpenReject: (id) {
                                setState(() {
                                  _rejectingCorrectionId = id;
                                  _rejectNoteController.clear();
                                });
                              },
                              onCancelReject: () {
                                setState(() {
                                  _rejectingCorrectionId = null;
                                  _rejectNoteController.clear();
                                });
                              },
                              onConfirmReject: _rejectCorrection,
                            ),
                            const SizedBox(width: 8),
                            _PendingOtApprovalsButton(
                              items: _pendingOtApprovals,
                              timeZone: _attendanceTimeZone,
                              busyId: _busyOtId,
                              onApprove: _approveOt,
                              onReject: _rejectOt,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _searchController,
                        decoration: appInputDecoration(
                          hintText: 'Search employees...',
                          prefixIcon: const Icon(Icons.search_rounded),
                        ).copyWith(fillColor: AppColors.white),
                      ),
                      const SizedBox(height: 16),
                      _AttendanceChart(metrics: _chartMetrics),
                      if (_restDayRecords.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _RestDayWorkSection(
                          records: _restDayRecords,
                          timeZone: _attendanceTimeZone,
                          profileImages: _profileImages,
                          onEmployeeTap: _showEmployeeDetails,
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
                              timeZone: _attendanceTimeZone,
                              profileImageUrl: _profileImages[
                                  '${record['employee_name'] ?? ''}'.trim()],
                              onTap: () => _showEmployeeDetails(record),
                              onComplete: '${record['status']}' == 'incomplete'
                                  ? () => _completeAttendance(record)
                                  : null,
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
    required this.correctionsButton,
  });

  final DateTime selectedDate;
  final bool isToday;
  final VoidCallback onPickDate;
  final VoidCallback onToday;
  final Widget correctionsButton;

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
        correctionsButton,
      ],
    );
  }
}

class _AttendanceChart extends StatelessWidget {
  const _AttendanceChart({required this.metrics});

  final Map<String, int> metrics;

  @override
  Widget build(BuildContext context) {
    return OwnerOverviewBarChart(
      title: 'Attendance Overview',
      onTime: metrics['on_time'] ?? 0,
      late: metrics['late'] ?? 0,
      undertime: metrics['undertime'] ?? 0,
      overtime: metrics['overtime'] ?? 0,
      absent: metrics['absent'] ?? 0,
    );
  }
}

class _RestDayWorkSection extends StatelessWidget {
  const _RestDayWorkSection({
    required this.records,
    required this.profileImages,
    required this.onEmployeeTap,
    this.timeZone,
  });

  final List<Map<String, dynamic>> records;
  final Map<String, String?> profileImages;
  final ValueChanged<Map<String, dynamic>> onEmployeeTap;
  final String? timeZone;

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
            'Employees who timed in or out on the configured rest day.',
            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 12),
          ...records.map((record) {
            final name = '${record['employee_name'] ?? 'Employee'}';
            final timeIn = _formatTime(
              record['time_in'] as String?,
              timeZone: timeZone,
            );
            final timeOut = _formatTime(
              record['time_out'] as String?,
              timeZone: timeZone,
            );
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
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onEmployeeTap(record),
                  borderRadius: BorderRadius.circular(12),
                  child: Ink(
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
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
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
    this.timeZone,
    this.onTap,
    this.onComplete,
  });

  final Map<String, dynamic> record;
  final String? timeZone;
  final String? profileImageUrl;
  final VoidCallback? onTap;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    final name = '${record['employee_name'] ?? 'Employee'}';
    final status = '${record['status'] ?? ''}';
    final shift = record['shift_name'] ?? record['position_title'];
    final timeIn = _formatTime(
      record['time_in'] as String?,
      timeZone: timeZone,
    );
    final timeOut = _formatTime(
      record['time_out'] as String?,
      timeZone: timeZone,
    );
    final late = status == 'late';
    final absent = status == 'absent';
    final holidayPaid = status == 'holiday_paid';
    final onLeave = status == 'on_leave';
    final incomplete = status == 'incomplete';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: _AttendanceCard(
          child: Row(
            children: [
              EmployeeAvatar(
                imageUrl: profileImageUrl ??
                    record['profile_image_url'] as String?,
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
                    if (sl<AppState>().session?.isDemo == true) ...[
                      const SizedBox(height: 4),
                      const SimulatedChip(label: 'SIMULATED'),
                    ],
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
                      style: TextStyle(
                        color: incomplete
                            ? const Color(0xFFB45309)
                            : onLeave || holidayPaid
                                ? const Color(0xFF0369A1)
                                : const Color(0xFF6B7280),
                        fontSize: 12,
                        fontWeight: incomplete || onLeave || holidayPaid
                            ? FontWeight.w700
                            : FontWeight.w400,
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
                    if (onComplete != null) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: onComplete,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFB45309),
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Complete Attendance'),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: incomplete
                      ? const Color(0xFFFEF3C7)
                      : absent
                          ? const Color(0xFFFEE2E2)
                          : holidayPaid || onLeave
                              ? const Color(0xFFE0F2FE)
                              : late
                                  ? const Color(0xFFFFEDD5)
                                  : const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  incomplete
                      ? 'Incomplete'
                      : absent
                          ? 'Absent'
                          : holidayPaid
                              ? 'Holiday'
                              : onLeave
                                  ? 'Leave'
                                  : timeIn,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: incomplete
                        ? const Color(0xFFB45309)
                        : absent
                            ? const Color(0xFFB91C1C)
                            : holidayPaid || onLeave
                                ? const Color(0xFF0369A1)
                                : late
                                    ? const Color(0xFFC2410C)
                                    : const Color(0xFF15803D),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingCorrectionsButton extends StatefulWidget {
  const _PendingCorrectionsButton({
    required this.items,
    required this.busyId,
    required this.rejectingId,
    required this.rejectNoteController,
    required this.onApprove,
    required this.onOpenReject,
    required this.onCancelReject,
    required this.onConfirmReject,
    this.timeZone,
  });

  final List<Map<String, dynamic>> items;
  final String? timeZone;
  final String? busyId;
  final String? rejectingId;
  final TextEditingController rejectNoteController;
  final Future<void> Function(String requestId) onApprove;
  final ValueChanged<String> onOpenReject;
  final VoidCallback onCancelReject;
  final Future<void> Function(String requestId) onConfirmReject;

  @override
  State<_PendingCorrectionsButton> createState() =>
      _PendingCorrectionsButtonState();
}

class _PendingCorrectionsButtonState extends State<_PendingCorrectionsButton> {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  final ValueNotifier<int> _reviewTick = ValueNotifier(0);

  @override
  void didUpdateWidget(covariant _PendingCorrectionsButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reviewTick.value++;
  }

  @override
  void dispose() {
    _reviewTick.dispose();
    super.dispose();
  }

  void _openCorrectionReview(
    BuildContext context,
    Map<String, dynamic> item,
    String id,
  ) {
    final submitted = item['created_at'];
    _showRequestReview(
      context,
      eyebrow: 'Correction request',
      title: '${item['employee_name'] ?? 'Employee'}',
      status: '${item['status'] ?? 'pending'}'.replaceAll('_', ' '),
      sections: [
        _reviewSection(
          'Employee',
          '${item['employee_name'] ?? 'Employee'}',
          emphasis: true,
        ),
        _reviewSection(
          'Request',
          '${_fmtDate(item['work_date'])}'
          '${item['shift_name'] != null ? '\n${item['shift_name']}' : ''}'
          '\nRecorded: In ${_fmtTime(item['recorded_time_in'])} · Out ${_fmtTime(item['recorded_time_out'])}'
          '\nRequested: In ${_fmtTime(item['requested_time_in'])} · Out ${_fmtTime(item['requested_time_out'])}',
        ),
        _reviewSection('Reason', '${item['reason'] ?? ''}'),
        if (submitted != null && '$submitted'.isNotEmpty)
          _reviewSection('Submitted', _fmtDate(submitted)),
      ],
      actions: ValueListenableBuilder<int>(
        valueListenable: _reviewTick,
        builder: (context, _, __) {
          final currentBusy = widget.busyId == id;
          if (widget.rejectingId == id) {
            return _correctionRejectEditor(
              controller: widget.rejectNoteController,
              busy: currentBusy,
              onConfirm: () {
                widget.onConfirmReject(id);
              },
              onCancel: widget.onCancelReject,
            );
          }
          return _reviewDecisionRow(
            busy: currentBusy,
            approveLabel: currentBusy ? 'Approving…' : 'Approve',
            rejectLabel: 'Reject',
            onApprove: () {
              widget.onApprove(id);
            },
            onReject: () {
              widget.onOpenReject(id);
            },
          );
        },
      ),
    );
  }

  void _toggle() {
    if (_portal.isShowing) {
      _portal.hide();
    } else {
      _portal.show();
    }
    setState(() {});
  }

  void _close() {
    if (_portal.isShowing) {
      _portal.hide();
      setState(() {});
    }
  }

  String _fmtTime(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) return '--';
    return formatBusinessAttendanceTimeIso(
      raw,
      timeZone: widget.timeZone,
      fallback: '--',
    );
  }

  String _fmtDate(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) return '--';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return DateFormat.MMMd().format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final open = _portal.isShowing;
    final count = widget.items.length;
    final width = MediaQuery.sizeOf(context).width;

    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: const ColoredBox(color: Color(0x33000000)),
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 10),
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: (width - 32).clamp(280.0, 360.0),
                    maxHeight: MediaQuery.sizeOf(context).height * 0.65,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.rate_review_outlined,
                                  color: Color(0xFF4B5563),
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Pending corrections',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      count == 0
                                          ? 'No requests right now'
                                          : '$count awaiting review',
                                      style: appMutedStyle()
                                          .copyWith(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 360),
                          child: count == 0
                              ? const _QueueEmpty(
                                  message:
                                      'No pending correction requests right now.',
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    10,
                                    12,
                                    12,
                                  ),
                                  itemCount: widget.items.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final item = widget.items[index];
                                    final id = '${item['id'] ?? ''}';
                                    final busy = widget.busyId == id;
                                    final rejecting =
                                        widget.rejectingId == id;
                                    final name =
                                        '${item['employee_name'] ?? 'Employee'}';
                                    final when =
                                        '${_fmtDate(item['work_date'])}'
                                        '${item['shift_name'] != null ? ' · ${item['shift_name']}' : ''}';
                                    final requested =
                                        'In ${_fmtTime(item['requested_time_in'])} · Out ${_fmtTime(item['requested_time_out'])}';
                                    return Material(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () => _openCorrectionReview(
                                          context,
                                          item,
                                          id,
                                        ),
                                        child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color: const Color(0xFFE5E7EB),
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 14,
                                                  height: 1.3,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                when,
                                                style: const TextStyle(
                                                  color: Color(0xFF6B7280),
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                requested,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF374151),
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              const Text(
                                                'Pending',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF4B5563),
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              if (rejecting)
                                                _correctionRejectEditor(
                                                  controller: widget
                                                      .rejectNoteController,
                                                  busy: busy,
                                                  onConfirm: () {
                                                    widget.onConfirmReject(id);
                                                  },
                                                  onCancel:
                                                      widget.onCancelReject,
                                                )
                                              else
                                                _reviewDecisionRow(
                                                  busy: busy,
                                                  approveLabel: busy
                                                      ? 'Approving…'
                                                      : 'Approve',
                                                  rejectLabel: 'Reject',
                                                  onApprove: () =>
                                                      widget.onApprove(id),
                                                  onReject: () =>
                                                      widget.onOpenReject(id),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: CompositedTransformTarget(
        link: _link,
        child: Tooltip(
          message: 'Pending corrections',
          child: Material(
            color: open
                ? BrandColors.of(context).toneButton
                : BrandColors.of(context).toneWell,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _toggle,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.rate_review_outlined,
                      size: 20,
                      color: open ? Colors.white : BrandColors.of(context).tonePrimary,
                    ),
                    if (count > 0)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          height: 16,
                          constraints: const BoxConstraints(minWidth: 16),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: BrandColors.of(context).toneButton,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: open ? BrandColors.of(context).toneButton : Colors.white,
                              width: 1.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            count > 9 ? '9+' : '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingOtApprovalsButton extends StatefulWidget {
  const _PendingOtApprovalsButton({
    required this.items,
    required this.timeZone,
    required this.busyId,
    required this.onApprove,
    required this.onReject,
  });

  final List<Map<String, dynamic>> items;
  final String? timeZone;
  final String? busyId;
  final Future<void> Function(String recordId) onApprove;
  final Future<void> Function(String recordId) onReject;

  @override
  State<_PendingOtApprovalsButton> createState() =>
      _PendingOtApprovalsButtonState();
}

class _PendingOtApprovalsButtonState extends State<_PendingOtApprovalsButton> {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  final ValueNotifier<int> _reviewTick = ValueNotifier(0);

  @override
  void didUpdateWidget(covariant _PendingOtApprovalsButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reviewTick.value++;
  }

  @override
  void dispose() {
    _reviewTick.dispose();
    super.dispose();
  }

  void _openOtReview(
    BuildContext context,
    Map<String, dynamic> item,
    String id,
  ) {
    final otMins = item['worked_ot_minutes'];
    _showRequestReview(
      context,
      eyebrow: 'Overtime approval',
      title: '${item['employee_name'] ?? 'Employee'}',
      status: '${item['ot_approval_status'] ?? 'pending'}'.replaceAll('_', ' '),
      sections: [
        _reviewSection(
          'Employee',
          '${item['employee_name'] ?? 'Employee'}',
          emphasis: true,
        ),
        _reviewSection(
          'Request',
          '${_fmtDate(item['work_date'])}'
          '${item['shift_name'] != null ? '\n${item['shift_name']}' : ''}'
          '\nIn ${_fmtTime(item['time_in'])} · Out ${_fmtTime(item['time_out'])}'
          '${otMins != null ? '\nWorked OT $otMins min' : ''}',
        ),
      ],
      actions: ValueListenableBuilder<int>(
        valueListenable: _reviewTick,
        builder: (context, _, __) {
          final currentBusy = widget.busyId == id;
          return _reviewDecisionRow(
            busy: currentBusy,
            approveLabel: currentBusy ? 'Approving…' : 'Approve',
            rejectLabel: currentBusy ? 'Rejecting…' : 'Reject',
            onApprove: () {
              widget.onApprove(id);
            },
            onReject: () {
              widget.onReject(id);
            },
          );
        },
      ),
    );
  }

  void _toggle() {
    if (_portal.isShowing) {
      _portal.hide();
    } else {
      _portal.show();
    }
    setState(() {});
  }

  void _close() {
    if (_portal.isShowing) {
      _portal.hide();
      setState(() {});
    }
  }

  String _fmtTime(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) return '--';
    return formatBusinessAttendanceTimeIso(
      raw,
      timeZone: widget.timeZone,
      fallback: '--',
    );
  }

  String _fmtDate(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) return '--';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return DateFormat.MMMd().format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final open = _portal.isShowing;
    final count = widget.items.length;
    final width = MediaQuery.sizeOf(context).width;

    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: const ColoredBox(color: Color(0x33000000)),
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 10),
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: (width - 32).clamp(280.0, 360.0),
                    maxHeight: MediaQuery.sizeOf(context).height * 0.65,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                          child: Text(
                            'Pending overtime approvals',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Flexible(
                          child: widget.items.isEmpty
                              ? const _QueueEmpty(
                                  message:
                                      'No overtime awaiting approval right now.',
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  padding:
                                      const EdgeInsets.fromLTRB(14, 0, 14, 14),
                                  itemCount: widget.items.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final item = widget.items[index];
                                    final id =
                                        '${item['attendance_record_id'] ?? ''}';
                                    final busy = widget.busyId == id;
                                    final otMins = item['worked_ot_minutes'];
                                    final name =
                                        '${item['employee_name'] ?? 'Employee'}';
                                    return Material(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () => _openOtReview(
                                          context,
                                          item,
                                          id,
                                        ),
                                        child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color: const Color(0xFFE5E7EB),
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 14,
                                                  height: 1.3,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${_fmtDate(item['work_date'])}'
                                                '${item['shift_name'] != null ? ' · ${item['shift_name']}' : ''}',
                                                style: const TextStyle(
                                                  color: Color(0xFF6B7280),
                                                  fontSize: 12,
                                                ),
                                              ),
                                              if (otMins != null) ...[
                                                const SizedBox(height: 6),
                                                Text(
                                                  'Worked OT $otMins min',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: BrandColors.of(
                                                      context,
                                                    ).tonePrimary,
                                                  ),
                                                ),
                                              ],
                                              const SizedBox(height: 8),
                                              Text(
                                                '${item['ot_approval_status'] ?? 'pending'}'
                                                    .replaceAll('_', ' '),
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF4B5563),
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              _reviewDecisionRow(
                                                busy: busy,
                                                approveLabel: busy
                                                    ? 'Approving…'
                                                    : 'Approve',
                                                rejectLabel: busy
                                                    ? 'Rejecting…'
                                                    : 'Reject',
                                                onApprove: () {
                                                  widget.onApprove(id);
                                                },
                                                onReject: () {
                                                  widget.onReject(id);
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: CompositedTransformTarget(
        link: _link,
        child: Tooltip(
          message: 'Pending overtime approvals',
          child: Material(
            color: open ? BrandColors.of(context).toneButton : BrandColors.of(context).toneWell,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _toggle,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.more_time_rounded,
                      size: 20,
                      color: open ? Colors.white : BrandColors.of(context).tonePrimary,
                    ),
                    if (count > 0)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          height: 16,
                          constraints: const BoxConstraints(minWidth: 16),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: BrandColors.of(context).toneButton,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: open ? BrandColors.of(context).toneButton : Colors.white,
                              width: 1.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            count > 9 ? '9+' : '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

ButtonStyle _softApproveButtonStyle() {
  return OutlinedButton.styleFrom(
    foregroundColor: const Color(0xFF166534),
    backgroundColor: const Color(0xFFF0FDF4),
    side: const BorderSide(color: Color(0xFFBBF7D0)),
    minimumSize: const Size(48, 44),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );
}

ButtonStyle _softRejectButtonStyle() {
  return OutlinedButton.styleFrom(
    foregroundColor: const Color(0xFF9F1239),
    backgroundColor: const Color(0xFFFFF1F2),
    side: const BorderSide(color: Color(0xFFFECDD3)),
    minimumSize: const Size(48, 44),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );
}

Widget _reviewSection(String label, String value, {bool emphasis = false}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w600,
            color: Color(0xFF9CA3AF),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            height: 1.4,
            color: emphasis ? const Color(0xFF1F2937) : AppColors.textPrimary,
            fontWeight: emphasis ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    ),
  );
}

Future<void> _showRequestReview(
  BuildContext context, {
  required String eyebrow,
  required String title,
  required String status,
  required List<Widget> sections,
  required Widget actions,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final inset = MediaQuery.sizeOf(dialogContext).width < 400 ? 16.0 : 24.0;
      return Dialog(
        insetPadding: EdgeInsets.fromLTRB(inset, 24, inset, 24),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              18,
              20,
              16 + MediaQuery.paddingOf(dialogContext).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        eyebrow.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    status,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                ...sections,
                const Divider(height: 28),
                actions,
              ],
            ),
          ),
        ),
      );
    },
  );
}

Widget _reviewDecisionRow({
  required bool busy,
  required String approveLabel,
  required String rejectLabel,
  required VoidCallback onApprove,
  required VoidCallback onReject,
}) {
  return Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      OutlinedButton.icon(
        onPressed: busy ? null : onReject,
        style: _softRejectButtonStyle(),
        icon: const Icon(Icons.close_rounded, size: 16),
        label: Text(rejectLabel),
      ),
      OutlinedButton.icon(
        onPressed: busy ? null : onApprove,
        style: _softApproveButtonStyle(),
        icon: const Icon(Icons.check_rounded, size: 16),
        label: Text(approveLabel),
      ),
    ],
  );
}

Widget _correctionRejectEditor({
  required TextEditingController controller,
  required bool busy,
  required VoidCallback onConfirm,
  required VoidCallback onCancel,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: controller,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'Rejection reason (required)',
          isDense: true,
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          TextButton(
            onPressed: busy ? null : onCancel,
            child: const Text('Cancel'),
          ),
          OutlinedButton.icon(
            onPressed: busy ? null : onConfirm,
            style: _softRejectButtonStyle(),
            icon: const Icon(Icons.close_rounded, size: 16),
            label: Text(busy ? 'Rejecting…' : 'Confirm reject'),
          ),
        ],
      ),
    ],
  );
}

class _QueueEmpty extends StatelessWidget {
  const _QueueEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.inbox_outlined,
            size: 18,
            color: Color(0xFF9CA3AF),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 13,
                height: 1.4,
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
    return OwnerEmptyState(
      isToday
          ? 'No attendance records yet'
          : 'No attendance for this day',
      description: isToday
          ? 'Time Ins will appear here as your team starts their shifts.'
          : 'Try another date, or check back after shifts are completed.',
      icon: Icons.event_available_outlined,
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
    return OwnerCard(child: child);
  }
}

String _isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

int _number(Object? value) =>
    value is num ? value.round() : int.tryParse('$value') ?? 0;

String _employmentLabel(Object? value) {
  switch ('$value') {
    case 'full_time':
      return 'Full Timer';
    case 'part_time':
      return 'Part Timer';
    default:
      final text = '$value'.trim();
      if (text.isEmpty || text == 'null') return 'Not set';
      return ownerFormatKey(text);
  }
}

String _rateLabel(Object? value) {
  if (value == null) return 'Not set';
  final amount = value is num ? value.toDouble() : double.tryParse('$value');
  if (amount == null) return 'Not set';
  final formatted = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: amount % 1 == 0 ? 0 : 2,
  ).format(amount);
  return '$formatted/day';
}

String _statusCopy(String status) {
  switch (status) {
    case 'late':
      return 'Arrived late';
    case 'absent':
      return 'Marked absent';
    case 'in_progress':
      return 'Timed in';
    case 'complete':
      return 'Arrived on time';
    case 'on_leave':
      return 'On Leave';
    case 'holiday_paid':
      return 'Paid holiday (not worked)';
    case 'incomplete':
      return 'Incomplete Attendance · Waiting for Attendance Correction';
    default:
      return status.replaceAll('_', ' ');
  }
}
