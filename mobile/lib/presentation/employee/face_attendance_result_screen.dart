import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/face/face_api_errors.dart';
import 'package:aroll_mobile/core/theme/business_brand_theme.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

enum FaceAttendanceAction { clockIn, clockOut }

/// Shown after face capture while verifying, or immediately with [initialResult].
class FaceAttendanceResultScreen extends StatefulWidget {
  const FaceAttendanceResultScreen({
    super.key,
    required this.action,
    this.verify,
    this.initialResult,
    this.profile,
    this.insideWorkArea = true,
  }) : assert(
          verify != null || initialResult != null,
          'Provide verify or initialResult',
        );

  final FaceAttendanceAction action;
  final Future<AttendanceClockResult> Function()? verify;
  final AttendanceClockResult? initialResult;
  final EmployeeProfile? profile;
  final bool insideWorkArea;

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
    final ready = widget.initialResult;
    if (ready != null) {
      _loading = false;
      _result = ready;
    } else {
      _runVerify();
    }
  }

  Future<void> _runVerify() async {
    final verify = widget.verify;
    if (verify == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await verify();
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
              ? 'We couldn’t verify your face. Please look directly at the camera and try again.'
              : 'We couldn’t verify your face. Please look directly at the camera and try again.',
        );
      });
    }
  }

  String _formatTime(DateTime? value) {
    if (value == null) return '--:--';
    return DateFormat.jm().format(value.toLocal());
  }

  String _formatDate(DateTime? value) {
    final date = (value ?? DateTime.now()).toLocal();
    return DateFormat('MMMM d, yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_loading,
      child: Scaffold(
        backgroundColor: EmployeeColors.scaffold,
        body: SafeArea(
          child: _loading
              ? _VerifyingBody(actionLabel: _actionLabel)
              : _error != null
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                      child: _ErrorBody(
                        actionLabel: _actionLabel,
                        message: _error!,
                        onRetry: () => Navigator.of(context).pop('retry'),
                        onClose: () => Navigator.of(context).pop(false),
                      ),
                    )
                  : _SuccessBody(
                      action: widget.action,
                      result: _result!,
                      profile: widget.profile,
                      insideWorkArea:
                          widget.insideWorkArea || _result!.insideGeofence,
                      formatTime: _formatTime,
                      formatDate: _formatDate,
                      onBackToAttendance: () => Navigator.of(context).pop(true),
                      onHome: () {
                        Navigator.of(context).pop(true);
                        context.go('/home');
                      },
                      onShiftHistory: () {
                        Navigator.of(context).pop(true);
                        context.go('/shift-history');
                      },
                      onClockOut: widget.action == FaceAttendanceAction.clockIn
                          ? () => Navigator.of(context).pop('clock_out')
                          : null,
                    ),
        ),
        bottomNavigationBar: _loading || _error != null
            ? null
            : const EmployeeBottomNav(selectedIndex: 2),
      ),
    );
  }
}

class _VerifyingBody extends StatelessWidget {
  const _VerifyingBody({required this.actionLabel});

  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        children: [
          const Spacer(),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: BrandColors.of(context).iconWell,
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: BrandColors.of(context).primary,
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Verifying your identity…',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          const Text(
            'Matching this face to your registered employee profile…',
            style: TextStyle(
              color: EmployeeColors.textBody,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _SuccessBody extends StatelessWidget {
  const _SuccessBody({
    required this.action,
    required this.result,
    required this.profile,
    required this.insideWorkArea,
    required this.formatTime,
    required this.formatDate,
    required this.onBackToAttendance,
    required this.onHome,
    required this.onShiftHistory,
    this.onClockOut,
  });

  final FaceAttendanceAction action;
  final AttendanceClockResult result;
  final EmployeeProfile? profile;
  final bool insideWorkArea;
  final String Function(DateTime?) formatTime;
  final String Function(DateTime?) formatDate;
  final VoidCallback onBackToAttendance;
  final VoidCallback onHome;
  final VoidCallback onShiftHistory;
  final VoidCallback? onClockOut;

  @override
  Widget build(BuildContext context) {
    final isClockIn = action == FaceAttendanceAction.clockIn;
    final stamp = isClockIn ? result.timeIn : result.timeOut;
    final timeValue = formatTime(stamp);
    final dateValue = formatDate(stamp);
    final statusTitle =
        isClockIn ? 'Clock In Successful' : 'Clock Out Successful';
    final clockedLabel =
        isClockIn ? 'Clocked In: $timeValue' : 'Clocked Out: $timeValue';
    final appState = sl<AppState>();
    final name = profile?.fullName ?? 'Employee';
    final position = profile?.position ?? 'Team member';
    final logoUrl = profile?.branding?.logoUrl;
    final avatarUrl =
        appState.resolveEmployeeAvatarUrl(profile?.profileImageUrl);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: onBackToAttendance,
              icon: const Icon(
                Icons.arrow_back_rounded,
                size: 18,
                color: EmployeeColors.textPrimary,
              ),
            ),
            const EmployeePageTitle('Attendance'),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: EmployeeColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: logoUrl != null && logoUrl.trim().isNotEmpty
                    ? BusinessLogo(logoUrl: logoUrl, height: 96, width: 96)
                    : Center(
                        child: Text(
                          (profile?.businessName.isNotEmpty ?? false)
                              ? profile!.businessName[0].toUpperCase()
                              : 'B',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: BrandColors.of(context).primary,
                          ),
                        ),
                      ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: EmployeeColors.success,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Attendance Recorded Successfully!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: EmployeeColors.textPrimary,
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: EmployeeColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 14,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  EmployeeAvatar(imageUrl: avatarUrl, name: name, size: 52),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: EmployeeColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          position,
                          style: const TextStyle(
                            fontSize: 13,
                            color: EmployeeColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(color: EmployeeColors.border),
              _SuccessDetailRow(
                icon: Icons.schedule_rounded,
                title: clockedLabel,
                subtitle: dateValue,
              ),
              const Divider(color: EmployeeColors.border),
              _SuccessDetailRow(
                icon: Icons.check_circle_rounded,
                title: 'Attendance Status',
                subtitle: statusTitle,
                success: true,
              ),
              const Divider(color: EmployeeColors.border),
              _SuccessDetailRow(
                icon: Icons.location_on_rounded,
                title: 'Location',
                subtitle: insideWorkArea
                    ? 'Verified inside the allowed work area'
                    : 'Outside the allowed work area',
                success: insideWorkArea,
              ),
              const SizedBox(height: 4),
              Text(
                insideWorkArea
                    ? 'Attendance recorded at your workplace.'
                    : 'Please make sure you are at your workplace next time.',
                style: const TextStyle(
                  fontSize: 12,
                  color: EmployeeColors.textMuted,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (onClockOut != null) ...[
          EmployeePrimaryButton(
            label: 'Clock Out',
            onPressed: onClockOut,
            icon: Icons.logout_rounded,
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: _SuccessNavButton(
                icon: Icons.home_rounded,
                label: 'Home',
                onTap: onHome,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SuccessNavButton(
                icon: Icons.assignment_rounded,
                label: 'Shift History',
                onTap: onShiftHistory,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SuccessNavButton extends StatelessWidget {
  const _SuccessNavButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = BrandColors.of(context);
    return Material(
      color: brand.iconWell,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(icon, color: brand.primary, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: EmployeeColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuccessDetailRow extends StatelessWidget {
  const _SuccessDetailRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.success = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool success;

  @override
  Widget build(BuildContext context) {
    final brand = BrandColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: brand.iconWell,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: brand.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: EmployeeColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (success) ...[
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 14,
                        color: EmployeeColors.success,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          color: EmployeeColors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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
