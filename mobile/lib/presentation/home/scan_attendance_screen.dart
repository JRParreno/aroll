import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/face/face_api_errors.dart';
import 'package:aroll_mobile/core/location/employee_location_service.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/domain/entities/face_liveness.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:aroll_mobile/presentation/employee/face_attendance_result_screen.dart';
import 'package:aroll_mobile/presentation/employee/face_liveness_capture_screen.dart';
import 'package:flutter/material.dart';

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

  EmployeeWorksite? _worksite;
  EmployeeAttendanceStatus? _attendanceStatus;
  EmployeeScheduleItem? _todaySchedule;
  EmployeeLocationSnapshot? _deviceLocation;
  GeofencePreview? _geofencePreview;
  String? _loadError;
  String? _actionError;
  String? _successMessage;
  bool _loading = true;
  bool _refreshingLocation = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
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
      setState(() {
        _worksite = worksite;
        _attendanceStatus = dashboard.attendanceStatus;
        _todaySchedule = dashboard.todaySchedule;
        _loading = false;
      });
      await _refreshLocation(showSpinner: false);
    } catch (error) {
      setState(() {
        _loading = false;
        _loadError = _messageFromError(error, fallback: 'Unable to load attendance.');
      });
    }
  }

  Future<void> _refreshLocation({bool showSpinner = true}) async {
    if (_worksite == null) return;
    if (showSpinner) {
      setState(() {
        _refreshingLocation = true;
        _actionError = null;
      });
    }
    try {
      final position = await _locationService.currentPosition();
      final preview = _locationService.preview(
        device: position,
        centerLatitude: _worksite!.latitude,
        centerLongitude: _worksite!.longitude,
        radiusM: _worksite!.geofenceRadiusM.toDouble(),
      );
      if (!mounted) return;
      setState(() {
        _deviceLocation = position;
        _geofencePreview = preview;
        _refreshingLocation = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _refreshingLocation = false;
        _actionError = _messageFromError(
          error,
          fallback: 'Unable to read your GPS location.',
        );
      });
    }
  }

  bool get _isClockedIn {
    final status = _attendanceStatus?.status;
    return status == 'in_progress' || status == 'late';
  }

  String? get _resolvedShiftAssignmentId {
    return widget.shiftAssignmentId ?? _todaySchedule?.assignmentId;
  }

  Future<EmployeeLocationSnapshot?> _captureFreshLocation() async {
    if (_worksite == null) return null;
    try {
      final position = await _locationService.freshPositionForAttendance(
        geofenceRadiusM: _worksite!.geofenceRadiusM.toDouble(),
      );
      final preview = _locationService.preview(
        device: position,
        centerLatitude: _worksite!.latitude,
        centerLongitude: _worksite!.longitude,
        radiusM: _worksite!.geofenceRadiusM.toDouble(),
      );
      if (!mounted) return null;
      setState(() {
        _deviceLocation = position;
        _geofencePreview = preview;
        _actionError = null;
      });
      return position;
    } catch (error) {
      if (!mounted) return null;
      setState(() {
        _actionError = _messageFromError(
          error,
          fallback: 'Unable to read your GPS location.',
        );
      });
      return null;
    }
  }

  Future<void> _clockIn() async {
    setState(() {
      _submitting = true;
      _actionError = null;
      _successMessage = null;
    });
    final location = await _captureFreshLocation();
    if (location == null) {
      if (mounted) setState(() => _submitting = false);
      return;
    }
    if (_geofencePreview?.insideGeofence != true) {
      setState(() {
        _submitting = false;
        _actionError =
            'Please move inside the work-site area before clocking in.';
      });
      return;
    }
    await _runFaceAttendanceFlow(
      action: FaceAttendanceAction.clockIn,
      verify: (capture) => _repo.clockInWithFace(
        latitude: location.latitude,
        longitude: location.longitude,
        capture: capture,
        shiftAssignmentId: _resolvedShiftAssignmentId,
      ),
    );
  }

  Future<void> _clockOut() async {
    setState(() {
      _submitting = true;
      _actionError = null;
      _successMessage = null;
    });
    final location = await _captureFreshLocation();
    if (location == null) {
      if (mounted) setState(() => _submitting = false);
      return;
    }
    if (_geofencePreview?.insideGeofence != true) {
      setState(() {
        _submitting = false;
        _actionError =
            'Please move inside the work-site area before clocking out.';
      });
      return;
    }
    await _runFaceAttendanceFlow(
      action: FaceAttendanceAction.clockOut,
      verify: (capture) => _repo.clockOutWithFace(
        latitude: location.latitude,
        longitude: location.longitude,
        capture: capture,
      ),
    );
  }

  Future<void> _runFaceAttendanceFlow({
    required FaceAttendanceAction action,
    required Future<AttendanceClockResult> Function(FaceQuickCapture capture)
        verify,
  }) async {
    while (mounted) {
      final capture = await _captureFace();
      if (capture == null) {
        if (mounted) setState(() => _submitting = false);
        return;
      }
      if (!mounted) return;
      final outcome = await Navigator.of(context).push<Object?>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => FaceAttendanceResultScreen(
            action: action,
            verify: () => verify(capture),
          ),
        ),
      );
      if (!mounted) return;
      if (outcome == true) {
        setState(() => _submitting = false);
        await _load();
        return;
      }
      if (outcome == 'retry') {
        // Capture again with a fresh blink/smile.
        continue;
      }
      setState(() => _submitting = false);
      return;
    }
  }

  Future<FaceQuickCapture?> _captureFace() async {
    return Navigator.of(context).push<FaceQuickCapture>(
      MaterialPageRoute(
        builder: (_) => const FaceLivenessCaptureScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  String _messageFromError(Object error, {required String fallback}) {
    if (error is LocationServiceException ||
        error is LocationPermissionException ||
        error is LocationAccuracyException) {
      return error.toString();
    }
    return faceApiErrorMessage(error, fallback: fallback);
  }

  @override
  Widget build(BuildContext context) {
    return EmployeeScaffold(
      title: 'Clock Attendance',
      selectedIndex: 2,
      showBack: true,
      child: _loading
          ? loadingView()
          : _loadError != null
              ? errorView(_loadError)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      if (_successMessage != null) ...[
                        _StatusBanner(
                          message: _successMessage!,
                          tone: _BannerTone.success,
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_actionError != null) ...[
                        _StatusBanner(
                          message: _actionError!,
                          tone: _BannerTone.error,
                        ),
                        const SizedBox(height: 12),
                      ],
                      EmployeeCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  height: 44,
                                  width: 44,
                                  decoration: BoxDecoration(
                                    color: EmployeeColors.iconWell,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.location_on_rounded,
                                    color: EmployeeColors.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _worksite!.label,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      if (_worksite!.address.isNotEmpty)
                                        Text(
                                          _worksite!.address,
                                          style: const TextStyle(
                                            color: EmployeeColors.textMuted,
                                            height: 1.35,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _InfoRow(
                              label: 'Allowed radius',
                              value: '${_worksite!.geofenceRadiusM} m',
                            ),
                            if (_todaySchedule != null) ...[
                              const SizedBox(height: 8),
                              _InfoRow(
                                label: 'Today\'s shift',
                                value:
                                    '${_todaySchedule!.shiftName} · ${_todaySchedule!.startLabel} – ${_todaySchedule!.endLabel}',
                              ),
                            ],
                            if (_attendanceStatus != null) ...[
                              const SizedBox(height: 8),
                              _InfoRow(
                                label: 'Status',
                                value: titleCase(_attendanceStatus!.status),
                              ),
                              const SizedBox(height: 8),
                              _InfoRow(
                                label: 'Time in',
                                value: timeOnly(_attendanceStatus!.timeIn),
                              ),
                              const SizedBox(height: 8),
                              _InfoRow(
                                label: 'Time out',
                                value: timeOnly(_attendanceStatus!.timeOut),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      EmployeeCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Your location',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const Spacer(),
                                TextButton.icon(
                                  onPressed: _refreshingLocation || _submitting
                                      ? null
                                      : () => _refreshLocation(),
                                  icon: _refreshingLocation
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.my_location_rounded,
                                          size: 18),
                                  label: const Text('Refresh'),
                                ),
                              ],
                            ),
                            if (_deviceLocation == null)
                              const Text(
                                'Waiting for GPS fix…',
                                style: TextStyle(color: EmployeeColors.textMuted),
                              )
                            else ...[
                              _InfoRow(
                                label: 'Latitude',
                                value:
                                    _deviceLocation!.latitude.toStringAsFixed(6),
                              ),
                              const SizedBox(height: 8),
                              _InfoRow(
                                label: 'Longitude',
                                value: _deviceLocation!.longitude
                                    .toStringAsFixed(6),
                              ),
                              const SizedBox(height: 8),
                              _InfoRow(
                                label: 'Accuracy',
                                value:
                                    '± ${_deviceLocation!.accuracyM.toStringAsFixed(0)} m',
                              ),
                            ],
                            if (_geofencePreview != null) ...[
                              const SizedBox(height: 16),
                              _GeofenceStatusChip(preview: _geofencePreview!),
                              const SizedBox(height: 8),
                              Text(
                                'You are ${_geofencePreview!.distanceM.toStringAsFixed(0)} m from the work site. '
                                'Attendance is allowed within ${_geofencePreview!.allowedRadiusM.toStringAsFixed(0)} m.',
                                style: const TextStyle(
                                  color: EmployeeColors.textMuted,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      EmployeeCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Container(
                              height: 72,
                              width: 72,
                              decoration: BoxDecoration(
                                color: EmployeeColors.iconWell,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Icon(
                                Icons.gps_fixed_rounded,
                                size: 36,
                                color: EmployeeColors.primary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Clock in and out with face verification and GPS. You must be inside the work-site radius.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: EmployeeColors.textMuted,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_isClockedIn)
                        EmployeePrimaryButton(
                          label: _submitting ? 'Clocking out…' : 'Clock Out',
                          onPressed: _submitting ||
                                  _geofencePreview?.insideGeofence != true
                              ? null
                              : _clockOut,
                        )
                      else
                        EmployeePrimaryButton(
                          label: _submitting ? 'Clocking in…' : 'Clock In',
                          onPressed: _submitting ||
                                  _geofencePreview?.insideGeofence != true
                              ? null
                              : _clockIn,
                        ),
                      const SizedBox(height: 10),
                      EmployeeOutlinedButton(
                        label: 'Back to Dashboard',
                        onPressed: () => employeeNavigateBack(context),
                      ),
                    ],
                  ),
                ),
    );
  }
}

enum _BannerTone { success, error }

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.message,
    required this.tone,
  });

  final String message;
  final _BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final isSuccess = tone == _BannerTone.success;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSuccess ? const Color(0xFFECFDF3) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSuccess ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA),
        ),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: isSuccess ? const Color(0xFF166534) : const Color(0xFFB91C1C),
          height: 1.35,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(color: EmployeeColors.textMuted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _GeofenceStatusChip extends StatelessWidget {
  const _GeofenceStatusChip({required this.preview});

  final GeofencePreview preview;

  @override
  Widget build(BuildContext context) {
    final inside = preview.insideGeofence;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: inside ? const Color(0xFFECFDF3) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            inside ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 18,
            color: inside ? EmployeeColors.success : const Color(0xFFB91C1C),
          ),
          const SizedBox(width: 8),
          Text(
            inside ? 'Inside geofence' : 'Outside geofence',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: inside ? EmployeeColors.success : const Color(0xFFB91C1C),
            ),
          ),
        ],
      ),
    );
  }
}
