import 'dart:async';

import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/face/face_api_errors.dart';
import 'package:aroll_mobile/core/location/employee_location_service.dart';
import 'package:aroll_mobile/core/theme/business_brand_theme.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/domain/entities/face_liveness.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:aroll_mobile/presentation/employee/face_attendance_result_screen.dart';
import 'package:aroll_mobile/presentation/employee/face_auto_attendance_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class ScanAttendanceScreen extends StatefulWidget {
  const ScanAttendanceScreen({
    super.key,
    this.shiftAssignmentId,
  });

  final String? shiftAssignmentId;

  @override
  State<ScanAttendanceScreen> createState() => _ScanAttendanceScreenState();
}

class _ScanAttendanceScreenState extends State<ScanAttendanceScreen> {
  final _locationService = EmployeeLocationService();
  final _repo = sl<EmployeeRepository>();

  EmployeeProfile? _profile;
  EmployeeWorksite? _worksite;
  EmployeeAttendanceStatus? _attendanceStatus;
  EmployeeScheduleItem? _todaySchedule;
  String? _loadError;
  String? _actionError;
  bool _loading = true;
  bool _submitting = false;
  bool _autoStarted = false;
  Timer? _clockTicker;

  @override
  void initState() {
    super.initState();
    _load();
    _clockTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _loading) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTicker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _actionError = null;
    });
    try {
      final results = await Future.wait([
        _repo.getWorksite(),
        _repo.getDashboard(),
      ]);
      final worksite = results[0] as EmployeeWorksite;
      final dashboard = results[1] as EmployeeDashboard;
      final appState = sl<AppState>();
      appState.updateEmployeeProfileImage(dashboard.profile.profileImageUrl);
      appState.updateBusinessBranding(dashboard.profile.branding);
      setState(() {
        _worksite = worksite;
        _profile = dashboard.profile;
        _attendanceStatus = dashboard.attendanceStatus;
        _todaySchedule = dashboard.todaySchedule;
        _loading = false;
      });
      // Start GPS immediately — do not wait for the camera / face path.
      unawaited(_warmupGps());
      final completed = dashboard.attendanceStatus.timeOut != null;
      final clockedIn = dashboard.attendanceStatus.timeIn != null &&
          dashboard.attendanceStatus.timeOut == null;
      if (!completed && !_autoStarted) {
        _autoStarted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _submitting) return;
          if (clockedIn) {
            unawaited(_clockOut());
          } else {
            unawaited(_clockIn());
          }
        });
      }
    } catch (error) {
      setState(() {
        _loading = false;
        _loadError = _messageFromError(
          error,
          fallback: 'Unable to load attendance.',
        );
      });
    }
  }

  Future<void> _warmupGps() async {
    // Light warmup only — do not run a full multi-sample collect here
    // (that races/competes with attendance and wastes time).
    try {
      final worksite = _worksite ?? await _repo.getWorksite();
      if (!mounted) return;
      setState(() => _worksite = worksite);
      unawaited(
        _locationService.currentPosition().then<void>((_) {}).catchError((_) {}),
      );
    } catch (_) {}
  }

  bool get _isClockedIn {
    final status = _attendanceStatus;
    if (status == null) return false;
    // Prefer punch timestamps so UI matches backend open-session detection.
    if (status.timeIn != null && status.timeOut == null) return true;
    return (status.status == 'in_progress' || status.status == 'late') &&
        status.timeOut == null;
  }

  bool get _isCompleted {
    final status = _attendanceStatus;
    if (status == null) return false;
    return status.timeOut != null;
  }

  String? get _resolvedShiftAssignmentId {
    return widget.shiftAssignmentId ?? _todaySchedule?.assignmentId;
  }

  String get _statusHeadline {
    if (_isCompleted) return 'Already Completed';
    if (_isClockedIn) return 'Ready to Clock Out';
    return 'Ready to Clock In';
  }

  String get _statusDetail {
    if (_isCompleted) return 'Time Out';
    if (_isClockedIn) return 'Time In';
    return 'Not clocked in yet';
  }

  String get _primaryButtonLabel {
    if (_submitting) return 'Opening camera…';
    if (_isCompleted) return 'Attendance already completed';
    if (_isClockedIn) return 'Look at camera to Clock Out';
    return 'Look at camera to Clock In';
  }

  String get _primaryButtonHelper {
    if (_submitting) return 'Preparing face check and location…';
    if (_isCompleted) return 'You already finished today’s attendance.';
    if (_isClockedIn) return 'Stay in the work area, then look at the camera.';
    return 'Stay in the work area, then look at the camera.';
  }

  Color _statusAccent(BuildContext context) {
    if (_isCompleted) return EmployeeColors.success;
    if (_isClockedIn) return BrandColors.of(context).accent;
    return brandPrimary(context);
  }

  Future<void> _clockIn() async {
    await _startAutoAttendance(FaceAttendanceAction.clockIn);
  }

  Future<void> _clockOut() async {
    await _startAutoAttendance(FaceAttendanceAction.clockOut);
  }

  Future<void> _onPrimaryTap() async {
    if (_isCompleted || _submitting) return;
    if (_isClockedIn) {
      await _clockOut();
    } else {
      await _clockIn();
    }
  }

  /// Camera + GPS start together. No blink/smile. Server matches the
  /// logged-in employee's enrolled face when a good frame is captured.
  Future<void> _startAutoAttendance(FaceAttendanceAction action) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _actionError = null;
    });

    try {
      // Reuse cached worksite when valid — avoid a duplicate API round-trip.
      var worksite = _worksite;
      if (worksite == null || !_isValidWorksite(worksite)) {
        worksite = await _repo.getWorksite();
      }
      if (!mounted) return;
      if (!_isValidWorksite(worksite)) {
        setState(() {
          _submitting = false;
          _actionError =
              'Work site isn’t set up yet. Please ask your employer to save the business location.';
        });
        return;
      }
      setState(() => _worksite = worksite);

      final outcome = await Navigator.of(context).push<Object?>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => FaceAutoAttendanceScreen(
            action: action,
            worksite: worksite!,
            profile: _profile,
            shiftAssignmentId: action == FaceAttendanceAction.clockIn
                ? _resolvedShiftAssignmentId
                : null,
            submit: ({
              required FaceQuickCapture capture,
              required double latitude,
              required double longitude,
            }) async {
              if (action == FaceAttendanceAction.clockIn) {
                return _repo.clockInWithFace(
                  latitude: latitude,
                  longitude: longitude,
                  capture: capture,
                  shiftAssignmentId: _resolvedShiftAssignmentId,
                );
              }
              return _repo.clockOutWithFace(
                latitude: latitude,
                longitude: longitude,
                capture: capture,
              );
            },
          ),
        ),
      );

      if (!mounted) return;
      if (outcome == true || outcome == 'clock_out') {
        await _load();
        if (!mounted) return;
        if (outcome == 'clock_out') {
          await _clockOut();
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _actionError = _messageFromError(
          error,
          fallback: 'We couldn’t complete attendance. Please try again.',
        );
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  bool _isValidWorksite(EmployeeWorksite worksite) {
    return worksite.latitude.abs() > 0.0001 &&
        worksite.longitude.abs() > 0.0001 &&
        worksite.geofenceRadiusM >= 5;
  }

  String _messageFromError(Object error, {required String fallback}) {
    if (error is LocationMockException) {
      return error.message;
    }
    if (error is LocationAccuracyException) {
      return error.message;
    }
    if (error is LocationServiceException) {
      return error.message;
    }
    if (error is LocationPermissionException) {
      return error.message;
    }
    return faceApiErrorMessage(error, fallback: fallback);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final profile = _profile;
    final appState = sl<AppState>();
    final brand = BrandColors.of(context);
    final primary = employeePrimary(profile?.branding, context);
    final statusAccent = _statusAccent(context);
    final schedule = _todaySchedule;

    return Scaffold(
      backgroundColor: EmployeeColors.scaffold,
      body: SafeArea(
        child: _loading
            ? loadingView()
            : _loadError != null
                ? errorView(_loadError, onRetry: _load)
                : RefreshIndicator(
                    color: primary,
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                      children: [
                        _AttendanceHeader(
                          onBack: () => employeeNavigateBack(context),
                          businessName: profile?.businessName ?? 'Attendance',
                          logoUrl: profile?.branding?.logoUrl,
                        ),
                        const SizedBox(height: 16),
                        if (_actionError != null) ...[
                          _SoftBanner(message: _actionError!),
                          const SizedBox(height: 12),
                        ],
                        ListenableBuilder(
                          listenable: appState,
                          builder: (context, _) {
                            final avatarUrl = appState.resolveEmployeeAvatarUrl(
                              profile?.profileImageUrl,
                            );
                            return _ProfileCard(
                              name: profile?.fullName ?? 'Employee',
                              position: profile?.position ?? 'Team member',
                              imageUrl: avatarUrl,
                              statusLabel: _statusHeadline,
                              statusColor: statusAccent,
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        _LiveClockCard(
                          dateLabel: DateFormat('EEEE, MMMM d').format(now),
                          timeLabel: DateFormat.jm().format(now),
                          accent: primary,
                        ),
                        const SizedBox(height: 12),
                        _DetailsCard(
                          statusValue: _statusDetail,
                          statusHint: _statusHeadline,
                          statusColor: statusAccent,
                          timeIn: _attendanceStatus?.timeIn,
                          timeOut: _attendanceStatus?.timeOut,
                          shiftLabel: schedule == null
                              ? 'No assigned shift today'
                              : '${schedule.shiftName} · ${schedule.startLabel} – ${schedule.endLabel}',
                        ),
                        const SizedBox(height: 20),
                        _ScanFaceButton(
                          label: _primaryButtonLabel,
                          helper: _primaryButtonHelper,
                          enabled: !_isCompleted && !_submitting,
                          submitting: _submitting,
                          accent: _isClockedIn ? brand.accent : primary,
                          onPressed: _onPrimaryTap,
                        ),
                        const SizedBox(height: 14),
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _NavShortcutButton(
                                  icon: Icons.home_rounded,
                                  label: 'Home',
                                  onTap: () => context.go('/home'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _NavShortcutButton(
                                  icon: Icons.assignment_rounded,
                                  label: 'Shift History',
                                  onTap: () => context.go('/shift-history'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _AttendanceHeader extends StatelessWidget {
  const _AttendanceHeader({
    required this.onBack,
    required this.businessName,
    this.logoUrl,
  });

  final VoidCallback onBack;
  final String businessName;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onBack,
            borderRadius: BorderRadius.circular(12),
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                Icons.arrow_back_rounded,
                size: 22,
                color: EmployeeColors.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Clock Attendance',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: EmployeeColors.textPrimary,
                ),
              ),
              Text(
                businessName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: EmployeeColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: EmployeeColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: BusinessLogo(
            logoUrl: logoUrl,
            height: 42,
            width: 42,
          ),
        ),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.name,
    required this.position,
    required this.imageUrl,
    required this.statusLabel,
    required this.statusColor,
  });

  final String name;
  final String position;
  final String? imageUrl;
  final String statusLabel;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EmployeeColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: statusColor.withValues(alpha: 0.35),
                width: 2.5,
              ),
            ),
            child: EmployeeAvatar(imageUrl: imageUrl, name: name, size: 64),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: EmployeeColors.textPrimary,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  position,
                  style: const TextStyle(
                    fontSize: 13,
                    color: EmployeeColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
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

class _LiveClockCard extends StatelessWidget {
  const _LiveClockCard({
    required this.dateLabel,
    required this.timeLabel,
    required this.accent,
  });

  final String dateLabel;
  final String timeLabel;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final brand = BrandColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent,
            Color.lerp(accent, brand.secondary, 0.45) ?? brand.secondary,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.schedule_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateLabel,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  timeLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    letterSpacing: -0.4,
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

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({
    required this.statusValue,
    required this.statusHint,
    required this.statusColor,
    required this.shiftLabel,
    this.timeIn,
    this.timeOut,
  });

  final String statusValue;
  final String statusHint;
  final Color statusColor;
  final String shiftLabel;
  final DateTime? timeIn;
  final DateTime? timeOut;

  @override
  Widget build(BuildContext context) {
    final brand = BrandColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EmployeeColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _DetailTile(
            icon: Icons.event_available_outlined,
            label: 'Today’s shift',
            primary: shiftLabel,
            accent: brand.primary,
          ),
          const Divider(height: 1, color: EmployeeColors.border),
          _DetailTile(
            icon: Icons.fact_check_rounded,
            label: 'Current status',
            primary: statusValue,
            secondary: statusHint,
            accent: statusColor,
          ),
          if (timeIn != null) ...[
            const Divider(height: 1, color: EmployeeColors.border),
            _DetailTile(
              icon: Icons.login_rounded,
              label: 'Time in',
              primary: timeOnly(timeIn),
              accent: EmployeeColors.success,
            ),
          ],
          if (timeOut != null) ...[
            const Divider(height: 1, color: EmployeeColors.border),
            _DetailTile(
              icon: Icons.logout_rounded,
              label: 'Time out',
              primary: timeOnly(timeOut),
              accent: const Color(0xFF2563EB),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({
    required this.icon,
    required this.label,
    required this.primary,
    required this.accent,
    this.secondary,
  });

  final IconData icon;
  final String label;
  final String primary;
  final String? secondary;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: EmployeeColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  primary,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: EmployeeColors.textPrimary,
                    height: 1.25,
                  ),
                ),
                if (secondary != null && secondary!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    secondary!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: EmployeeColors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanFaceButton extends StatelessWidget {
  const _ScanFaceButton({
    required this.label,
    required this.helper,
    required this.enabled,
    required this.submitting,
    required this.accent,
    required this.onPressed,
  });

  final String label;
  final String helper;
  final bool enabled;
  final bool submitting;
  final Color accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          height: 72,
          child: ElevatedButton(
            onPressed: enabled ? onPressed : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              disabledBackgroundColor: accent.withValues(alpha: 0.42),
              foregroundColor: Colors.white,
              elevation: enabled ? 2 : 0,
              shadowColor: accent.withValues(alpha: 0.35),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              padding: const EdgeInsets.fromLTRB(18, 12, 16, 12),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: submitting
                      ? const Padding(
                          padding: EdgeInsets.all(11),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.face_retouching_natural_rounded,
                          size: 26,
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 26),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          helper,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            color: EmployeeColors.textMuted,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _NavShortcutButton extends StatelessWidget {
  const _NavShortcutButton({
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
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: EmployeeColors.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: brand.iconWell,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: brand.primary, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
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

class _SoftBanner extends StatelessWidget {
  const _SoftBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFB91C1C),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFB91C1C),
                height: 1.35,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
