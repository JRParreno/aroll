import 'package:aroll_mobile/core/face/face_api_errors.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum FaceAttendanceAction { clockIn, clockOut }

/// Shown after blink/smile capture while verifying, then success or error.
class FaceAttendanceResultScreen extends StatefulWidget {
  const FaceAttendanceResultScreen({
    super.key,
    required this.action,
    required this.verify,
  });

  final FaceAttendanceAction action;
  final Future<AttendanceClockResult> Function() verify;

  @override
  State<FaceAttendanceResultScreen> createState() =>
      _FaceAttendanceResultScreenState();
}

class _FaceAttendanceResultScreenState
    extends State<FaceAttendanceResultScreen> {
  bool _loading = true;
  AttendanceClockResult? _result;
  String? _error;

  String get _actionLabel =>
      widget.action == FaceAttendanceAction.clockIn ? 'Clock in' : 'Clock out';

  @override
  void initState() {
    super.initState();
    _runVerify();
  }

  Future<void> _runVerify() async {
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await widget.verify();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _result = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = faceApiErrorMessage(
          e,
          fallback: widget.action == FaceAttendanceAction.clockIn
              ? 'Clock-in didn’t go through. Please try again.'
              : 'Clock-out didn’t go through. Please try again.',
        );
      });
    }
  }

  String _formatTime(DateTime? value) {
    if (value == null) return '--:--';
    return DateFormat.jm().format(value.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_loading,
      child: Scaffold(
        backgroundColor: EmployeeColors.scaffold,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: _loading
                ? _VerifyingBody(actionLabel: _actionLabel)
                : _error != null
                    ? _ErrorBody(
                        actionLabel: _actionLabel,
                        message: _error!,
                        onRetry: () =>
                            Navigator.of(context).pop('retry'),
                        onClose: () => Navigator.of(context).pop(false),
                      )
                    : _SuccessBody(
                        action: widget.action,
                        result: _result!,
                        formatTime: _formatTime,
                        onDone: () => Navigator.of(context).pop(true),
                      ),
          ),
        ),
      ),
    );
  }
}

class _VerifyingBody extends StatelessWidget {
  const _VerifyingBody({required this.actionLabel});

  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(),
        Container(
          width: 96,
          height: 96,
          decoration: const BoxDecoration(
            color: EmployeeColors.iconWell,
            shape: BoxShape.circle,
          ),
          child: const Padding(
            padding: EdgeInsets.all(28),
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: EmployeeColors.primaryDark,
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Checking your face…',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          'Hang tight while we confirm it’s you for $actionLabel.',
          style: const TextStyle(
            color: EmployeeColors.textBody,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
        const Spacer(),
      ],
    );
  }
}

class _SuccessBody extends StatelessWidget {
  const _SuccessBody({
    required this.action,
    required this.result,
    required this.formatTime,
    required this.onDone,
  });

  final FaceAttendanceAction action;
  final AttendanceClockResult result;
  final String Function(DateTime?) formatTime;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final isClockIn = action == FaceAttendanceAction.clockIn;
    final title = isClockIn ? 'You’re clocked in!' : 'You’re clocked out!';
    final timeLabel = isClockIn ? 'Time in' : 'Time out';
    final timeValue =
        isClockIn ? formatTime(result.timeIn) : formatTime(result.timeOut);

    return Column(
      children: [
        const Spacer(),
        Container(
          width: 96,
          height: 96,
          decoration: const BoxDecoration(
            color: Color(0xFFDCFCE7),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            size: 52,
            color: Color(0xFF166534),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF166534),
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          result.message.isNotEmpty
              ? result.message
              : 'Face matched successfully. Have a great shift!',
          style: const TextStyle(
            color: EmployeeColors.textBody,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: EmployeeColors.border),
          ),
          child: Column(
            children: [
              _DetailRow(label: timeLabel, value: timeValue),
              if (result.shiftName != null && result.shiftName!.isNotEmpty) ...[
                const SizedBox(height: 10),
                _DetailRow(label: 'Shift', value: result.shiftName!),
              ],
              const SizedBox(height: 10),
              _DetailRow(
                label: 'Status',
                value: result.status.replaceAll('_', ' '),
              ),
            ],
          ),
        ),
        const Spacer(),
        EmployeePrimaryButton(
          label: 'Done',
          onPressed: onDone,
          icon: Icons.check_circle_outline_rounded,
        ),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({
    required this.actionLabel,
    required this.message,
    required this.onRetry,
    required this.onClose,
  });

  final String actionLabel;
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(),
        Container(
          width: 96,
          height: 96,
          decoration: const BoxDecoration(
            color: Color(0xFFFEE2E2),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.error_outline_rounded,
            size: 52,
            color: Color(0xFFB91C1C),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Face check didn’t work',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFFB91C1C),
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          message.isNotEmpty
              ? message
              : 'We couldn’t confirm your face for $actionLabel. Please try again.',
          style: const TextStyle(
            color: EmployeeColors.textBody,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
        const Spacer(),
        EmployeePrimaryButton(
          label: 'Try again',
          onPressed: onRetry,
          icon: Icons.refresh_rounded,
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: onClose,
            style: OutlinedButton.styleFrom(
              foregroundColor: EmployeeColors.textPrimary,
              side: const BorderSide(color: EmployeeColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Close',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(color: EmployeeColors.textMuted),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: EmployeeColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
