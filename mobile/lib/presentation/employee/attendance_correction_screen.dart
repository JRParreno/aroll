import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/face/face_api_errors.dart';
import 'package:aroll_mobile/core/theme/business_brand_theme.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
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
  late TimeOfDay _timeIn;
  late TimeOfDay _timeOut;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _timeIn = _todFrom(widget.item.timeIn) ??
        _todFromLabel(widget.item.shiftStart) ??
        const TimeOfDay(hour: 9, minute: 0);
    _timeOut = _todFrom(widget.item.timeOut) ??
        _todFromLabel(widget.item.shiftEnd) ??
        const TimeOfDay(hour: 17, minute: 0);
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  TimeOfDay? _todFrom(DateTime? value) {
    if (value == null) return null;
    final local = value.toLocal();
    return TimeOfDay(hour: local.hour, minute: local.minute);
  }

  TimeOfDay? _todFromLabel(String? label) {
    if (label == null || label.trim().isEmpty) return null;
    try {
      final parsed = DateFormat.jm().parse(label.trim());
      return TimeOfDay(hour: parsed.hour, minute: parsed.minute);
    } catch (_) {
      return null;
    }
  }

  DateTime _combine(DateTime day, TimeOfDay tod) {
    return DateTime(day.year, day.month, day.day, tod.hour, tod.minute);
  }

  bool get _isIncomplete =>
      widget.item.status.toLowerCase() == 'incomplete';

  Future<void> _pickTime({required bool isIn}) async {
    // Incomplete attendance: clock-in is the official recorded punch and
    // cannot be changed via employee correction.
    if (isIn && _isIncomplete) return;
    final initial = isIn ? _timeIn : _timeOut;
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
      setState(
        () => _error =
            'Please explain the reason for correction (at least 5 characters).',
      );
      return;
    }

    final day = widget.item.date;
    var requestedIn = _combine(day, _timeIn);
    var requestedOut = _combine(day, _timeOut);

    // Overnight: if out is earlier than/equal to in, push out to next day.
    if (!requestedOut.isAfter(requestedIn)) {
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
      await showAppFeedback(
        context,
        title: 'Correction Submitted',
        message: 'Your request was sent. Waiting for manager approval.',
        success: true,
        actionLabel: 'Done',
      );
      if (!mounted) return;
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

  String _formatTod(TimeOfDay value) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, value.hour, value.minute);
    return DateFormat.jm().format(dt);
  }

  String _recordedTime(DateTime? value) {
    if (value == null) return 'Not recorded';
    return DateFormat.jm().format(value.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final brand = BrandColors.of(context);
    final isIncomplete = _isIncomplete;
    final shiftLabel = item.shiftName?.trim().isNotEmpty == true
        ? item.shiftName!
        : 'Shift';
    final shiftRange =
        '${item.shiftStart ?? '--'} – ${item.shiftEnd ?? '--'}';

    return EmployeeScaffold(
      title: 'Request Correction',
      selectedIndex: 1,
      showBack: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        children: [
          EmployeeCard(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: brand.iconWell,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.edit_calendar_outlined,
                        color: brand.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shiftLabel,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: EmployeeColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${shortDate(item.date)} · $shiftRange',
                            style: const TextStyle(
                              color: EmployeeColors.textMuted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isIncomplete)
                      const EmployeeStatusChip(
                        label: 'Incomplete',
                        color: Color(0xFFD97706),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE8EEF4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Recorded attendance',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: EmployeeColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _RecordedTimeRow(
                        label: 'Time In',
                        value: _recordedTime(item.timeIn),
                        missing: item.timeIn == null,
                      ),
                      const SizedBox(height: 8),
                      _RecordedTimeRow(
                        label: 'Time Out',
                        value: _recordedTime(item.timeOut),
                        missing: item.timeOut == null,
                      ),
                    ],
                  ),
                ),
                if (isIncomplete) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: const Text(
                      'Edit Time Out and remarks only. Time In is locked.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          EmployeeSectionTitle(
            isIncomplete ? 'Corrected Time Out' : 'Corrected times',
          ),
          const SizedBox(height: 4),
          Text(
            isIncomplete
                ? 'Tap time-out to update it.'
                : 'Tap a time to update it.',
            style: appMutedStyle().copyWith(fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _TimePickerCard(
                  label: isIncomplete ? 'Time In (locked)' : 'Time In',
                  value: _formatTod(_timeIn),
                  icon: Icons.login_rounded,
                  enabled: !_submitting && !isIncomplete,
                  readOnly: isIncomplete,
                  onTap: () => _pickTime(isIn: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TimePickerCard(
                  label: 'Time Out',
                  value: _formatTod(_timeOut),
                  icon: Icons.logout_rounded,
                  enabled: !_submitting,
                  onTap: () => _pickTime(isIn: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const EmployeeSectionTitle('Reason'),
          const SizedBox(height: 4),
          Text(
            'Tell your manager what happened.',
            style: appMutedStyle().copyWith(fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          EmployeeCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: TextField(
              controller: _reasonController,
              maxLines: 4,
              maxLength: 1000,
              enabled: !_submitting,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: EmployeeColors.textPrimary,
              ),
              decoration: employeeInputDecoration(
                context,
                hintText: 'Example: I forgot to time out after my shift.',
              ).copyWith(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                counterStyle: appMutedStyle().copyWith(fontSize: 11),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFB91C1C),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          EmployeePrimaryButton(
            label: _submitting ? 'Submitting…' : 'Submit for approval',
            onPressed: _submitting ? null : _submit,
            loading: _submitting,
            icon: Icons.send_rounded,
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F6FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE8EEF4)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: EmployeeColors.textMuted,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your manager will review this request. Attendance and payroll update only after approval.',
                    style: TextStyle(
                      color: EmployeeColors.textMuted,
                      fontSize: 12,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordedTimeRow extends StatelessWidget {
  const _RecordedTimeRow({
    required this.label,
    required this.value,
    required this.missing,
  });

  final String label;
  final String value;
  final bool missing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: EmployeeColors.textMuted,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: missing
                ? const Color(0xFFD97706)
                : EmployeeColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _TimePickerCard extends StatelessWidget {
  const _TimePickerCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.readOnly = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final brand = BrandColors.of(context);
    final muted = readOnly || !enabled;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: readOnly ? const Color(0xFFF8FAFC) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: EmployeeColors.border),
            boxShadow: readOnly
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: brand.iconWell,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      readOnly ? Icons.lock_outline_rounded : icon,
                      size: 16,
                      color: brand.primary,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    readOnly
                        ? Icons.lock_outline_rounded
                        : Icons.access_time_rounded,
                    size: 18,
                    color: brand.primary.withValues(alpha: muted ? 0.45 : 0.8),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: EmployeeColors.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: muted
                      ? EmployeeColors.textMuted
                      : EmployeeColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
