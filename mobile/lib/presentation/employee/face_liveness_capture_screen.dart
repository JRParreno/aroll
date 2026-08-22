import 'dart:io';
import 'dart:math' as math;

import 'package:aroll_mobile/core/face/face_api_errors.dart';
import 'package:aroll_mobile/core/face/gesture_liveness_detector.dart';
import 'package:aroll_mobile/core/theme/business_brand_theme.dart';
import 'package:aroll_mobile/domain/entities/face_liveness.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Quick capture: blink or smile on-device, then return a single face photo.
class FaceLivenessCaptureScreen extends StatefulWidget {
  const FaceLivenessCaptureScreen({
    super.key,
    this.worksiteLabel,
    this.insideWorkArea,
    this.hasSchedule,
  });

  /// Optional display-only label from the clock-attendance screen.
  final String? worksiteLabel;

  /// Optional display-only geofence result from the clock-attendance screen.
  final bool? insideWorkArea;

  /// Optional display-only schedule presence from the clock-attendance screen.
  final bool? hasSchedule;

  @override
  State<FaceLivenessCaptureScreen> createState() =>
      _FaceLivenessCaptureScreenState();
}

class _FaceLivenessCaptureScreenState extends State<FaceLivenessCaptureScreen> {
  final _gesture = GestureLivenessDetector();
  CameraController? _camera;
  FaceDetector? _detector;
  bool _busy = true;
  bool _capturing = false;
  bool _streaming = false;
  bool _processingFrame = false;
  DateTime? _lastProcessedAt;
  DateTime? _pendingSince;
  FaceGesture? _pendingGesture;
  int _alignedFrames = 0;
  String? _error;
  String _guidance = 'Looking for your face...';

  /// Match enrollment camera quality; low-res probes caused false mismatches.
  static const _minFrameInterval = Duration(milliseconds: 90);
  static const _maxPendingCapture = Duration(milliseconds: 450);
  static const _minAlignedFramesBeforeLiveness = 3;
  static const _guideYellow = Color(0xFFFFC107);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final permitted = await Permission.camera.request();
      if (!permitted.isGranted) {
        setState(() {
          _busy = false;
          _error =
              'Please allow camera access so we can verify it’s you.';
        });
        return;
      }
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        // Same preset as face registration for compatible embeddings.
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      final detector = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,
          enableTracking: true,
          performanceMode: FaceDetectorMode.fast,
          minFaceSize: 0.15,
        ),
      );
      if (!mounted) return;
      setState(() {
        _camera = controller;
        _detector = detector;
        _busy = false;
        _guidance = 'Looking for your face...';
      });
      await _startStream();
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

  bool _eyesOpenEnough(Face face) {
    final left = face.leftEyeOpenProbability;
    final right = face.rightEyeOpenProbability;
    if (left == null || right == null) return true;
    return left > 0.55 && right > 0.55;
  }

  bool _isWellAligned(Face face, Size imageSize) {
    final box = face.boundingBox;
    if (imageSize.width <= 0 || imageSize.height <= 0) return false;
    final fill =
        (box.width * box.height) / (imageSize.width * imageSize.height);
    // Too far / too close for a reliable attendance probe.
    if (fill < 0.04 || fill > 0.75) return false;

    final yaw = face.headEulerAngleY?.abs() ?? 0;
    final roll = face.headEulerAngleZ?.abs() ?? 0;
    // Allow mild pose variation (glasses/smile/angle) without failing.
    if (yaw > 35 || roll > 35) return false;
    return true;
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_capturing || _busy || _processingFrame || _detector == null) {
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
      final input = _inputImageFromCamera(image, camera);
      if (input == null) return;
      final faces = await _detector!.processImage(input);
      if (!mounted || _capturing) return;

      if (faces.length != 1) {
        _alignedFrames = 0;
        _pendingGesture = null;
        _pendingSince = null;
        _gesture.reset();
        _updateGuidance(
          faces.isEmpty
              ? 'Looking for your face...'
              : 'Only one face should be visible',
        );
        return;
      }

      final face = faces.first;
      final imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final aligned = _isWellAligned(face, imageSize);
      if (!aligned) {
        _alignedFrames = 0;
        _pendingGesture = null;
        _pendingSince = null;
        _updateGuidance('Looking for your face...');
        return;
      }
      _alignedFrames += 1;

      // Liveness already passed — grab the next open-eye aligned frame quickly.
      // Identity matching happens on the server after this capture.
      if (_pendingGesture != null) {
        final waited = _pendingSince == null
            ? Duration.zero
            : now.difference(_pendingSince!);
        if (_eyesOpenEnough(face) || waited >= _maxPendingCapture) {
          await _finish(_pendingGesture!);
          return;
        }
        _updateGuidance('Capturing for identity check...');
        return;
      }

      if (_alignedFrames < _minAlignedFramesBeforeLiveness) {
        _updateGuidance('Hold still...');
        return;
      }

      _updateGuidance('Blink or smile to continue');
      final gesture = _gesture.observe(
        leftEyeOpen: face.leftEyeOpenProbability,
        rightEyeOpen: face.rightEyeOpenProbability,
        smiling: face.smilingProbability,
      );
      if (gesture != null) {
        _pendingGesture = gesture;
        _pendingSince = now;
        _updateGuidance('Liveness passed — capturing...');
        if (_eyesOpenEnough(face)) {
          await _finish(gesture);
        }
      }
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

  Future<void> _finish(FaceGesture gesture) async {
    if (_capturing) return;
    _capturing = true;
    _pendingGesture = null;
    _pendingSince = null;
    setState(() => _guidance = 'Sending for identity verification...');
    await _stopStream();
    try {
      final file = await _camera!.takePicture();
      final dir = await getTemporaryDirectory();
      final dest = p.join(
        dir.path,
        'face_${gesture.name}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await File(file.path).copy(dest);
      if (!mounted) return;
      Navigator.of(context).pop(
        FaceQuickCapture(
          imagePath: dest,
          gesture: gesture.name,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _capturing = false;
        _alignedFrames = 0;
        _error = faceApiErrorMessage(
          e,
          fallback: 'Photo didn’t save. Please try again.',
        );
      });
      _gesture.reset();
      await _startStream();
    }
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

  // --- UI-only helpers derived from existing recognition / guidance state ---

  bool get _faceMissing =>
      _guidance == 'Looking for your face...' ||
      _guidance == 'Only one face should be visible';

  bool get _aligning =>
      _guidance == 'Looking for your face...' || _guidance == 'Hold still...';

  bool get _livenessPassed =>
      _capturing ||
      _pendingGesture != null ||
      _guidance == 'Capturing for identity check...' ||
      _guidance == 'Liveness passed — capturing...' ||
      _guidance == 'Sending for identity verification...';

  bool get _faceReady =>
      !_busy &&
      (_guidance == 'Blink or smile to continue' ||
          _guidance == 'Hold still...' ||
          _livenessPassed);

  String get _overlayStatusLabel {
    if (_busy) return 'Looking for your face...';
    if (_guidance == 'Sending for identity verification...') {
      return 'Sending for identity verification...';
    }
    if (_livenessPassed) return 'Liveness passed — checking identity next';
    if (_guidance == 'Only one face should be visible') {
      return 'Only one face should be visible';
    }
    if (_faceMissing) return 'Looking for your face...';
    if (_guidance == 'Hold still...') return 'Hold still...';
    if (_guidance == 'Blink or smile to continue') {
      return 'Blink or smile to continue';
    }
    return 'Looking for your face...';
  }

  bool get _showOverlaySpinner =>
      !_livenessPassed && _guidance != 'Only one face should be visible';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _busy && _camera == null
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _error != null
              ? _ErrorBody(
                  message: _error!,
                  onClose: () => Navigator.of(context).pop(),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_camera != null && _camera!.value.isInitialized)
                      _CameraCoverPreview(controller: _camera!),
                    SafeArea(
                      bottom: false,
                      child: Column(
                        children: [
                          const SizedBox(height: 6),
                          _ScanHeader(
                            onBack: () => Navigator.of(context).pop(),
                          ),
                          const Spacer(flex: 3),
                          _FaceGuideOverlay(
                            guideColor: _guideYellow,
                            statusLabel: _overlayStatusLabel,
                            showSpinner: _showOverlaySpinner,
                            verified: _livenessPassed,
                          ),
                          const Spacer(flex: 2),
                          _ScanBottomSheet(
                            statusLabel: _overlayStatusLabel,
                            insideWorkArea: widget.insideWorkArea,
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
    required this.message,
    required this.onClose,
  });

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
            EmployeePrimaryButton(
              label: 'Close',
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanHeader extends StatelessWidget {
  const _ScanHeader({required this.onBack});

  final VoidCallback onBack;

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
              const Expanded(
                child: EmployeePageTitle('Scan Your Face'),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _FaceGuideOverlay extends StatelessWidget {
  const _FaceGuideOverlay({
    required this.guideColor,
    required this.statusLabel,
    required this.showSpinner,
    required this.verified,
  });

  final Color guideColor;
  final String statusLabel;
  final bool showSpinner;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final guideSize =
        (MediaQuery.sizeOf(context).shortestSide * 0.62).clamp(260.0, 320.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: guideSize,
          height: guideSize,
          child: CustomPaint(
            painter: _FaceGuidePainter(
              color: verified ? EmployeeColors.success : guideColor,
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (showSpinner) ...[
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
        ] else if (verified) ...[
          const Icon(
            Icons.check_circle_rounded,
            color: Colors.white,
            size: 24,
          ),
          const SizedBox(height: 6),
        ],
        Text(
          statusLabel,
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 8,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FaceGuidePainter extends CustomPainter {
  const _FaceGuidePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    const corner = 36.0;
    const radius = 22.0;
    final w = size.width;
    final h = size.height;

    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(0, corner)
        ..lineTo(0, radius)
        ..arcToPoint(
          const Offset(radius, 0),
          radius: const Radius.circular(radius),
        )
        ..lineTo(corner, 0),
      paint,
    );
    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(w - corner, 0)
        ..lineTo(w - radius, 0)
        ..arcToPoint(
          Offset(w, radius),
          radius: const Radius.circular(radius),
        )
        ..lineTo(w, corner),
      paint,
    );
    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(w, h - corner)
        ..lineTo(w, h - radius)
        ..arcToPoint(
          Offset(w - radius, h),
          radius: const Radius.circular(radius),
        )
        ..lineTo(w - corner, h),
      paint,
    );
    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(corner, h)
        ..lineTo(radius, h)
        ..arcToPoint(
          Offset(0, h - radius),
          radius: const Radius.circular(radius),
        )
        ..lineTo(0, h - corner),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _FaceGuidePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _ScanBottomSheet extends StatelessWidget {
  const _ScanBottomSheet({
    required this.statusLabel,
    required this.insideWorkArea,
  });

  final String statusLabel;
  final bool? insideWorkArea;

  String get _locationCopy {
    if (insideWorkArea == null) {
      return 'Checking you’re at your workplace…';
    }
    if (insideWorkArea!) {
      return 'You’re inside the allowed work area';
    }
    return 'You’re outside the allowed work area';
  }

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
            'Blink or smile to prove you’re present. Your identity is checked against your registered face after capture.',
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
            icon: Icons.schedule_rounded,
            title: 'Real-time Status',
            subtitle: statusLabel,
          ),
          const Divider(height: 22, color: EmployeeColors.border),
          _LiveStatusRow(
            icon: Icons.location_on_rounded,
            title: 'Location',
            subtitle: _locationCopy,
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

class _CameraCoverPreview extends StatelessWidget {
  const _CameraCoverPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    final preview = controller.value.previewSize;
    final previewW = preview?.height ?? 480;
    final previewH = preview?.width ?? 640;

    return ColoredBox(
      color: Colors.black,
      child: ClipRect(
        child: OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          alignment: const Alignment(0, -0.2),
          child: FittedBox(
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.2),
            child: SizedBox(
              width: previewW,
              height: previewH,
              child: CameraPreview(controller),
            ),
          ),
        ),
      ),
    );
  }
}
