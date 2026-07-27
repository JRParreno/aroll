import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/face/face_api_errors.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class AttendanceCorrectionScreen extends StatefulWidget {
  const AttendanceCorrectionScreen({super.key, required this.item});

  final EmployeeShiftHistoryItem item;

  @override
  State<AttendanceCorrectionScreen> createState() =>
      _AttendanceCorrectionScreenState();
}

class _AttendanceCorrectionScreenState
    extends State<AttendanceCorrectionScreen> {
  final _reasonController = TextEditingController();
  TimeOfDay? _timeIn;
  TimeOfDay? _timeOut;
  bool _submitting = false;
  String? _error;

  bool get _needsIn => widget.item.needsClockIn;
  bool get _needsOut => widget.item.needsClockOut;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  DateTime _combine(DateTime day, TimeOfDay tod) {
    return DateTime(day.year, day.month, day.day, tod.hour, tod.minute);
  }

  Future<void> _pickTime({required bool isIn}) async {
    final initial = isIn
        ? (_timeIn ?? const TimeOfDay(hour: 9, minute: 0))
        : (_timeOut ?? const TimeOfDay(hour: 17, minute: 0));
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked == null) return;
    setState(() {
      if (isIn) {
        _timeIn = picked;
      } else {
        _timeOut = picked;
      }
      _error = null;
    });
  }

  Future<void> _submit() async {
    final reason = _reasonController.text.trim();
    if (reason.length < 5) {
      setState(() => _error = 'Please explain what happened (at least 5 characters).');
      return;
    }
    if (_needsIn && _timeIn == null) {
      setState(() => _error = 'Please enter your actual clock-in time.');
      return;
    }
    if (_needsOut && !_needsIn && _timeOut == null) {
      setState(() => _error = 'Please enter your actual clock-out time.');
      return;
    }
    if (_needsIn && _needsOut && _timeIn == null && _timeOut == null) {
      setState(() => _error = 'Enter at least a clock-in or clock-out time.');
      return;
    }

    final day = widget.item.date;
    DateTime? requestedIn =
        _timeIn == null ? null : _combine(day, _timeIn!);
    DateTime? requestedOut =
        _timeOut == null ? null : _combine(day, _timeOut!);

    // Overnight: if out is earlier than in, push out to next day.
    if (requestedIn != null &&
        requestedOut != null &&
        !requestedOut.isAfter(requestedIn)) {
      requestedOut = requestedOut.add(const Duration(days: 1));
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await sl<EmployeeRepository>().submitAttendanceCorrection(
        shiftAssignmentId: widget.item.assignmentId,
        requestedTimeIn: requestedIn,
        requestedTimeOut: requestedOut,
        reason: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Correction submitted. Waiting for manager approval.'),
        ),
      );
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = faceApiErrorMessage(
          e,
          fallback: 'Could not submit correction. Please try again.',
        );
      });
    }
  }

  String _formatTod(TimeOfDay? value) {
    if (value == null) return 'Tap to select';
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, value.hour, value.minute);
    return DateFormat.jm().format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return EmployeeScaffold(
      title: 'Request correction',
      selectedIndex: 1,
      showBack: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          EmployeeCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.shiftName ?? 'Shift',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${shortDate(item.date)} · ${item.shiftStart ?? '--'} - ${item.shiftEnd ?? '--'}',
                  style: const TextStyle(color: EmployeeColors.textMuted),
                ),
                const SizedBox(height: 10),
                Text(
                  item.needsClockIn && item.needsClockOut
                      ? 'You missed both clock-in and clock-out for this shift.'
                      : item.needsClockIn
                          ? 'You missed clock-in for this shift.'
                          : 'You missed clock-out for this shift.',
                  style: const TextStyle(
                    color: EmployeeColors.textBody,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_needsIn) ...[
            EmployeeCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Actual clock-in'),
                subtitle: Text(_formatTod(_timeIn)),
                trailing: const Icon(Icons.access_time_rounded),
                onTap: _submitting ? null : () => _pickTime(isIn: true),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_needsOut) ...[
            EmployeeCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _needsIn ? 'Actual clock-out (optional)' : 'Actual clock-out',
                ),
                subtitle: Text(_formatTod(_timeOut)),
                trailing: const Icon(Icons.access_time_rounded),
                onTap: _submitting ? null : () => _pickTime(isIn: false),
              ),
            ),
            const SizedBox(height: 12),
          ],
          EmployeeCard(
            child: TextField(
              controller: _reasonController,
              maxLines: 4,
              maxLength: 1000,
              enabled: !_submitting,
              decoration: employeeInputDecoration(
                hintText: 'Why did you miss the punch? (required)',
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ],
          const SizedBox(height: 16),
          EmployeePrimaryButton(
            label: _submitting ? 'Submitting…' : 'Submit for approval',
            onPressed: _submitting ? null : _submit,
            loading: _submitting,
            icon: Icons.send_rounded,
          ),
          const SizedBox(height: 8),
          const Text(
            'Your manager will review this request. Attendance and payroll update only after approval.',
            style: TextStyle(
              color: EmployeeColors.textMuted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
