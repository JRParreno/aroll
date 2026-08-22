import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;

import 'package:aroll_mobile/core/face/face_api_errors.dart';
import 'package:aroll_mobile/core/face/face_camera_preview.dart';
import 'package:aroll_mobile/core/face/face_quality.dart';
import 'package:aroll_mobile/core/location/employee_location_service.dart';
import 'package:aroll_mobile/core/theme/business_brand_theme.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/domain/entities/face_liveness.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:aroll_mobile/presentation/employee/face_attendance_result_screen.dart';
import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

/// Seamless attendance: camera + GPS run in parallel. Continuous face detection
/// (no blink/smile). When the face is ready and GPS is inside the geofence,
/// a frame is captured and verified on the server against the logged-in
/// employee's enrolled face only.
class FaceAutoAttendanceScreen extends StatefulWidget {
  const FaceAutoAttendanceScreen({
    super.key,
    required this.action,
    required this.worksite,
    required this.submit,
    this.profile,
    this.shiftAssignmentId,
  });

  final FaceAttendanceAction action;
  final EmployeeWorksite worksite;
  final EmployeeProfile? profile;
  final String? shiftAssignmentId;

  /// Server clock-in/out with the captured still + GPS (identity match on server).
  final Future<AttendanceClockResult> Function({
    required FaceQuickCapture capture,
    required double latitude,
    required double longitude,
  }) submit;

  @override
  State<FaceAutoAttendanceScreen> createState() =>
      _FaceAutoAttendanceScreenState();
}

class _FaceAutoAttendanceScreenState extends State<FaceAutoAttendanceScreen> {
  final _locationService = EmployeeLocationService();

  static List<CameraDescription>? _cachedCameras;

  CameraController? _camera;
  FaceDetector? _detector;

  bool _busy = true;
  bool _streaming = false;
  bool _processingFrame = false;
  bool _submitting = false;
  bool _gpsRunning = false;
  /// True only after multi-sample fresh GPS finishes (never the quick first fix).
  bool _gpsReliable = false;
  bool _faceReady = false;
  int? _trackingId;

  DateTime? _lastProcessedAt;
  DateTime? _lastSubmitAt;
  int _alignedFrames = 0;

  String _guidance = 'Starting camera…';
  String? _error;
  String? _gpsStatus;
  GeofencePreview? _geofence;
  EmployeeLocationSnapshot? _latestGps;

  static const _minFrameInterval = Duration(milliseconds: 100);
  static const _minAlignedFrames = 2;
  static const _submitCooldown = Duration(milliseconds: 350);
  static const _minFaceQuality = 0.55;

  /// Form contract still expects blink|smile; identity is server-side ArcFace.
  static const _contractGesture = 'blink';

  DateTime? _openedAt;
  DateTime? _cameraReadyAt;
  DateTime? _faceDetectedAt;
  DateTime? _gpsReadyAt;
  double _lastFaceQuality = 0;

  String get _actionLabel =>
      widget.action == FaceAttendanceAction.clockIn ? 'Time in' : 'Time out';

  @override
  void initState() {
    super.initState();
    _openedAt = DateTime.now();
    // Camera + GPS start together — never wait on each other.
    unawaited(_bootstrapCamera());
    unawaited(_startGpsParallel());
  }

  Future<void> _bootstrapCamera() async {
    final camStarted = DateTime.now();
    try {
      final permitted = await Permission.camera.request();
      if (!permitted.isGranted) {
        setState(() {
          _busy = false;
          _error = 'Please allow camera access so we can verify it’s you.';
        });
        return;
      }

      // Detector is cheap to construct — start it while the camera initializes.
      final detector = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: false,
          enableLandmarks: true,
          enableTracking: true,
          performanceMode: FaceDetectorMode.fast,
          minFaceSize: 0.10,
        ),
      );

      _cachedCameras ??= await availableCameras();
      final cameras = _cachedCameras!;
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      // medium + full-FOV preview: faster startup; still JPEG is enough for ArcFace.
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await controller.initialize();
      await setCameraZoomOneX(controller);

      final cameraMs = DateTime.now().difference(camStarted).inMilliseconds;
      developer.log(
        'PERF camera_startup_ms=$cameraMs',
        name: 'aroll.perf',
      );

      if (!mounted) {
        await controller.dispose();
        await detector.close();
        return;
      }
      _cameraReadyAt = DateTime.now();
      setState(() {
        _camera = controller;
        _detector = detector;
        _busy = false;
        _guidance = 'Camera ready';
      });
      await _startStream();
      if (mounted && !_faceReady) {
        _updateGuidance('Look at the camera');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = faceApiErrorMessage(
          e,
          fallback: 'We couldn’t start the camera. Please try again.',
        );
      });
    }
  }

  Future<void> _startGpsParallel() async {
    if (_gpsRunning) return;
    _gpsRunning = true;
    if (mounted) {
      setState(() => _gpsStatus = 'Checking work location…');
    }
    final worksite = widget.worksite;

    // UI-only quick status — never used to submit (Phase 1).
    unawaited(() async {
      try {
        final quick = await _locationService.currentPosition();
        if (!mounted || _gpsReliable) return;
        setState(() {
          _gpsStatus = 'Checking work location…';
        });
        developer.log(
          'PERF gps_quick_fix_ms='
          '${DateTime.now().difference(_openedAt!).inMilliseconds} '
          'accuracy_m=${quick.accuracyM}',
          name: 'aroll.perf',
        );
      } catch (_) {}
    }());

    final gpsStarted = DateTime.now();
    try {
      final position = await _locationService.freshPositionForAttendance(
        geofenceRadiusM: worksite.geofenceRadiusM.toDouble(),
        earlyAcceptCenterLatitude: worksite.latitude,
        earlyAcceptCenterLongitude: worksite.longitude,
        earlyAcceptRadiusM: worksite.geofenceRadiusM.toDouble(),
        onUpdate: (snapshot) {
          if (!mounted || _gpsReliable) return;
          final preview = _locationService.preview(
            device: snapshot,
            centerLatitude: worksite.latitude,
            centerLongitude: worksite.longitude,
            radiusM: worksite.geofenceRadiusM.toDouble(),
          );
          // Avoid rebuild storms — only update status text when it changes.
          final next = preview.insideGeofence
              ? 'Checking work location…'
              : 'Checking work location…';
          if (_gpsStatus != next) {
            setState(() => _gpsStatus = next);
          }
        },
        onStatus: (message) {
          if (!mounted || _gpsReliable) return;
          // Map technical GPS strings to friendly progress.
          final friendly = message.contains('Improving') ||
                  message.contains('Getting')
              ? 'Checking work location…'
              : message;
          if (_gpsStatus != friendly) {
            setState(() => _gpsStatus = friendly);
          }
        },
      );
      if (!mounted) return;
      final preview = _locationService.preview(
        device: position,
        centerLatitude: worksite.latitude,
        centerLongitude: worksite.longitude,
        radiusM: worksite.geofenceRadiusM.toDouble(),
      );
      final gpsMs = DateTime.now().difference(gpsStarted).inMilliseconds;
      _gpsReadyAt = DateTime.now();
      developer.log(
        'PERF gps_acquisition_ms=$gpsMs distance_validation=YES '
        'samples=${position.sampleCount} accuracy_m=${position.accuracyM} '
        'distance_m=${preview.distanceM} '
        'result=${preview.insideGeofence ? 'INSIDE' : 'OUTSIDE'}',
        name: 'aroll.perf',
      );
      setState(() {
        _latestGps = position;
        _geofence = preview;
        _gpsReliable = preview.insideGeofence && !preview.needsBetterGps;
        _gpsStatus = preview.insideGeofence
            ? 'Work location confirmed'
            : _outsideMessage(preview);
      });
      if (_faceReady) {
        _updateGuidance('Verifying identity');
      }
      _tryAutoSubmit();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _gpsReliable = false;
        if (e is LocationMockException) {
          _error = e.message;
          _gpsStatus = e.message;
          _guidance = e.message;
        } else {
          _gpsStatus = faceApiErrorMessage(
            e,
            fallback: 'We couldn’t confirm your workplace location yet.',
          );
        }
      });
    } finally {
      _gpsRunning = false;
    }
  }

  String _outsideMessage(GeofencePreview preview) {
    return 'Outside work area '
        '(${preview.distanceM.toStringAsFixed(0)} m / '
        '${preview.allowedRadiusM.toStringAsFixed(0)} m). Move closer.';
  }

  Future<void> _startStream() async {
    final camera = _camera;
    if (camera == null || _streaming) return;
    _streaming = true;
    await camera.startImageStream(_onFrame);
  }

  Future<void> _stopStream() async {
    final camera = _camera;
    if (camera == null || !_streaming) return;
    _streaming = false;
    try {
      await camera.stopImageStream();
    } catch (_) {}
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_submitting || _busy || _processingFrame || _detector == null) {
      return;
    }
    final now = DateTime.now();
    if (_lastProcessedAt != null &&
        now.difference(_lastProcessedAt!) < _minFrameInterval) {
      return;
    }
    final camera = _camera;
    if (camera == null) return;

    _processingFrame = true;
    _lastProcessedAt = now;
    try {
      final detectStarted = DateTime.now();
      final input = _inputImageFromCamera(image, camera);
      if (input == null) return;
      final faces = await _detector!.processImage(input);
      if (!mounted || _submitting) return;

      if (faces.length != 1) {
        _alignedFrames = 0;
        _faceReady = false;
        _trackingId = null;
        _lastFaceQuality = 0;
        _updateGuidance(
          faces.isEmpty
              ? 'Look at the camera. Glasses and makeup are OK.'
              : 'Only one person should be visible during attendance.',
        );
        return;
      }

      final face = faces.first;
      // Passive liveness: require stable tracking across live frames (no challenges).
      final tid = face.trackingId;
      if (_trackingId != null && tid != null && tid != _trackingId) {
        _alignedFrames = 0;
        _faceReady = false;
        _trackingId = tid;
        _updateGuidance('Hold still…');
        return;
      }
      _trackingId ??= tid;

      final imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final assessment = assessFaceQuality(
        face,
        imageSize,
        minScore: _minFaceQuality,
        naturalDistance: true,
      );
      _lastFaceQuality = assessment.score;
      if (!assessment.ok) {
        _alignedFrames = 0;
        _faceReady = false;
        _updateGuidance(assessment.guidance);
        return;
      }

      _alignedFrames += 1;
      if (_alignedFrames == 1) {
        _faceDetectedAt ??= DateTime.now();
        final detectMs = _cameraReadyAt == null
            ? DateTime.now().difference(detectStarted).inMilliseconds
            : _faceDetectedAt!.difference(_cameraReadyAt!).inMilliseconds;
        developer.log(
          'PERF face_detected_ms=$detectMs quality=${assessment.score}',
          name: 'aroll.perf',
        );
      }
      if (_alignedFrames < _minAlignedFrames) {
        _updateGuidance('Face detected');
        return;
      }

      _faceReady = true;

      if (!_gpsReliable || _geofence == null || _latestGps == null) {
        _updateGuidance('Checking work location');
        return;
      }
      if (_geofence!.needsBetterGps) {
        _updateGuidance('Checking work location');
        return;
      }
      if (!_geofence!.insideGeofence) {
        _updateGuidance(_outsideMessage(_geofence!));
        return;
      }

      // Embedding / server match only when face is stable + GPS ready.
      _updateGuidance('Verifying identity');
      await _tryAutoSubmit();
    } catch (_) {
      // Drop frame errors; stream continues.
    } finally {
      _processingFrame = false;
    }
  }

  void _updateGuidance(String value) {
    if (!mounted || value == _guidance) return;
    setState(() => _guidance = value);
  }

  Future<void> _tryAutoSubmit() async {
    if (!mounted || _submitting || _busy) return;
    final geo = _geofence;
    final gps = _latestGps;
    if (!_gpsReliable || geo == null || gps == null) return;
    if (!geo.insideGeofence || geo.needsBetterGps) return;
    if (gps.isMocked) return;
    if (_alignedFrames < _minAlignedFrames) return;
    // Require a short live-stream window before capture (passive anti-spoof).
    if (_cameraReadyAt != null &&
        DateTime.now().difference(_cameraReadyAt!) <
            const Duration(milliseconds: 350)) {
      return;
    }
    final now = DateTime.now();
    if (_lastSubmitAt != null &&
        now.difference(_lastSubmitAt!) < _submitCooldown) {
      return;
    }
    await _captureAndSubmit(gps);
  }

  Future<void> _captureAndSubmit(EmployeeLocationSnapshot gps) async {
    if (_submitting) return;
    _submitting = true;
    _lastSubmitAt = DateTime.now();
    final started = DateTime.now();
    setState(() => _guidance = 'Verifying identity');
    await _stopStream();

    try {
      final captureStarted = DateTime.now();
      final file = await _camera!.takePicture();
      final captureMs =
          DateTime.now().difference(captureStarted).inMilliseconds;
      developer.log(
        'PERF still_capture_ms=$captureMs quality=${_lastFaceQuality.toStringAsFixed(3)}',
        name: 'aroll.perf',
      );

      // Use the camera file directly — skip extra disk copy.
      final capture = FaceQuickCapture(
        imagePath: file.path,
        gesture: _contractGesture,
      );

      if (!mounted) return;
      setState(() => _guidance = 'Recording attendance');

      final apiStarted = DateTime.now();
      final result = await widget.submit(
        capture: capture,
        latitude: gps.latitude,
        longitude: gps.longitude,
      );
      final apiMs = DateTime.now().difference(apiStarted).inMilliseconds;
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      final sinceOpen = _openedAt == null
          ? elapsed
          : DateTime.now().difference(_openedAt!).inMilliseconds;
      final gpsWaitMs = _gpsReadyAt == null || _openedAt == null
          ? -1
          : _gpsReadyAt!.difference(_openedAt!).inMilliseconds;

      developer.log(
        'PERF attendance_api_ms=$apiMs recognition_roundtrip_ms=$elapsed '
        'gps_ready_ms=$gpsWaitMs total_attendance_ms=$sinceOpen '
        'action=${widget.action.name} match=YES',
        name: 'aroll.perf',
      );

      if (!mounted) return;
      setState(() => _guidance = 'Attendance successful');
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => FaceAttendanceResultScreen(
            action: widget.action,
            profile: widget.profile,
            insideWorkArea: true,
            initialResult: result,
          ),
        ),
      );
    } catch (e) {
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      developer.log(
        'PERF attendance_fail_ms=$elapsed err=$e',
        name: 'aroll.perf',
      );
      if (!mounted) return;
      final identityReject = _isIdentityReject(e);
      setState(() {
        _submitting = false;
        _alignedFrames = 0;
        _faceReady = false;
        if (identityReject) {
          // Hard fail: do not keep auto-retrying — Phase 1 anti-FAR.
          _error = faceApiErrorMessage(
            e,
            fallback: 'Face does not match the registered employee.',
          );
          _guidance = _error ?? 'Face does not match the registered employee.';
        } else {
          _guidance = faceApiErrorMessage(
            e,
            fallback: 'Couldn’t complete attendance. Trying again…',
          );
          _error = null;
        }
      });
      if (identityReject) {
        await _stopStream();
        return;
      }
      // Soft fail only for transient capture / network issues.
      await _startStream();
      if (_isHardFailure(e)) {
        setState(() {
          _error = faceApiErrorMessage(
            e,
            fallback: 'Couldn’t complete attendance. Please try again.',
          );
        });
      }
    }
  }

  bool _isIdentityReject(Object error) {
    if (error is! DioException) return false;
    final data = error.response?.data;
    if (data is! Map) return false;
    final detail = data['detail'];
    if (detail is Map) {
      final c = detail['code']?.toString();
      return c == 'face_mismatch' ||
          c == 'multiple_faces' ||
          c == 'face_enrollment_quality';
    }
    return false;
  }

  bool _isHardFailure(Object error) {
    if (error is! DioException) return true;
    final code = error.response?.statusCode ?? 0;
    // Identity rejects are hard-stopped earlier; stop on auth/business rules.
    if (code == 401 || code == 403) {
      final data = error.response?.data;
      if (data is Map) {
        final detail = data['detail'];
        if (detail is Map) {
          final c = detail['code']?.toString();
          if (c == 'no_face' || c == 'outside_geofence') {
            return false;
          }
        }
      }
      return true;
    }
    if (code == 400) {
      final data = error.response?.data;
      if (data is Map) {
        final detail = data['detail'];
        if (detail is Map) {
          final c = detail['code']?.toString();
          if (c == 'not_enrolled' ||
              c == 'face_enrollment_required' ||
              c == 'face_enrollment_quality') {
            return true;
          }
        }
      }
      // Already clocked in / schedule errors — stop looping.
      return true;
    }
    return false;
  }

  InputImage? _inputImageFromCamera(
    CameraImage image,
    CameraController controller,
  ) {
    final rotation = InputImageRotationValue.fromRawValue(
          controller.description.sensorOrientation,
        ) ??
        InputImageRotation.rotation0deg;
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  @override
  void dispose() {
    final camera = _camera;
    final detector = _detector;
    _camera = null;
    _detector = null;
    _streaming = false;
    () async {
      try {
        if (camera != null && camera.value.isStreamingImages) {
          await camera.stopImageStream();
        }
      } catch (_) {}
      try {
        await camera?.dispose();
      } catch (_) {}
      try {
        await detector?.close();
      } catch (_) {}
    }();
    super.dispose();
  }

  bool get _verifiedLook =>
      _submitting ||
      _guidance == 'Verifying your identity…' ||
      _guidance == 'Recording attendance…' ||
      _guidance == 'Recognizing you…';

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_submitting,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _busy && _camera == null
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : _error != null
                ? _ErrorBody(
                    message: _error!,
                    onClose: () => Navigator.of(context).pop(),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_camera != null && _camera!.value.isInitialized)
                        FullFovCameraPreview(controller: _camera!),
                      FaceGuideOverlay(
                        ringColor: _verifiedLook
                            ? EmployeeColors.success
                            : Colors.white,
                        accentColor: _verifiedLook
                            ? const Color(0x554ADE80)
                            : const Color(0x33FFC107),
                      ),
                      SafeArea(
                        bottom: false,
                        child: Column(
                          children: [
                            const SizedBox(height: 6),
                            _ScanHeader(
                              title: _actionLabel,
                              onBack: _submitting
                                  ? null
                                  : () => Navigator.of(context).pop(),
                            ),
                            const Spacer(),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 24),
                              child: Text(
                                _guidance,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  shadows: [
                                    Shadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.45),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const Spacer(),
                            _StatusSheet(
                              faceStatus: _guidance,
                              locationStatus: _gpsStatus ??
                                  'Checking your location…',
                              insideWorkArea: _geofence?.insideGeofence,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              message,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            EmployeePrimaryButton(label: 'Close', onPressed: onClose),
          ],
        ),
      ),
    );
  }
}

class _ScanHeader extends StatelessWidget {
  const _ScanHeader({required this.title, this.onBack});

  final String title;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.white,
        elevation: 1,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                tooltip: 'Back',
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  size: 22,
                  color: EmployeeColors.textPrimary,
                ),
              ),
              Expanded(child: EmployeePageTitle(title)),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusSheet extends StatelessWidget {
  const _StatusSheet({
    required this.faceStatus,
    required this.locationStatus,
    required this.insideWorkArea,
  });

  final String faceStatus;
  final String locationStatus;
  final bool? insideWorkArea;

  @override
  Widget build(BuildContext context) {
    final bottomInset = math.max(MediaQuery.paddingOf(context).bottom, 10.0);
    final locationOk = insideWorkArea == true;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, 10, 20, bottomInset + 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Look naturally at the camera. Face and location check at the same time.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: EmployeeColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 14),
          _LiveStatusRow(
            icon: Icons.face_retouching_natural_rounded,
            title: 'Face',
            subtitle: faceStatus,
          ),
          const Divider(height: 22, color: EmployeeColors.border),
          _LiveStatusRow(
            icon: Icons.location_on_rounded,
            title: 'Location',
            subtitle: locationStatus,
            trailing: Icon(
              locationOk
                  ? Icons.check_circle_rounded
                  : (insideWorkArea == false
                      ? Icons.cancel_rounded
                      : Icons.hourglass_top_rounded),
              size: 18,
              color: locationOk
                  ? EmployeeColors.success
                  : (insideWorkArea == false
                      ? const Color(0xFFB91C1C)
                      : EmployeeColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveStatusRow extends StatelessWidget {
  const _LiveStatusRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: BrandColors.of(context).iconWell,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: BrandColors.of(context).primary,
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: EmployeeColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: EmployeeColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
