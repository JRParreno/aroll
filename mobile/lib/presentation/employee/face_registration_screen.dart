import 'dart:async';
import 'dart:io';

import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/face/blink_detector.dart';
import 'package:aroll_mobile/core/face/face_api_errors.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:showcaseview/showcaseview.dart';

/// Open-eye samples + one blink sample.
const _openSamples = 2;
const _targetSamples = 3; // 2 open + 1 blink

enum _EnrollStep { camera, capture, review }

class FaceRegistrationScreen extends StatefulWidget {
  const FaceRegistrationScreen({super.key});

  @override
  State<FaceRegistrationScreen> createState() => _FaceRegistrationScreenState();
}

class _FaceRegistrationScreenState extends State<FaceRegistrationScreen> {
  final _repo = sl<EmployeeRepository>();
  final _blinkDetector = BlinkDetector();

  final _stepActionKey = GlobalKey();

  BuildContext? _showcaseContext;

  CameraController? _camera;
  FaceDetector? _detector;
  final List<String> _samplePaths = [];

  /// Indices in [_samplePaths] that were captured during a blink.
  final Set<int> _blinkSampleIndexes = {};
  _EnrollStep _step = _EnrollStep.camera;
  bool _loading = true;
  bool _enrolling = false;
  bool _cameraStarting = false;
  bool _capturing = false;
  bool _tourStarted = false;
  bool _blinkWatching = false;
  bool _processingFrame = false;
  bool _streaming = false;
  DateTime? _lastProcessedAt;
  String? _error;
  String? _statusLabel;
  String _captureGuidance = 'Fit your face in the oval, then take a photo';

  static const _minFrameInterval = Duration(milliseconds: 400);
  static const _stepLabels = ['Camera', 'Photos', 'Done'];

  int get _stepIndex => _EnrollStep.values.indexOf(_step);

  bool get _cameraReady => _camera != null && _camera!.value.isInitialized;

  bool get _needsBlinkSample =>
      _samplePaths.length >= _openSamples &&
      _samplePaths.length < _targetSamples;

  bool get _hasBlinkSample => _blinkSampleIndexes.isNotEmpty;

  bool get _captureComplete =>
      _samplePaths.length >= _targetSamples && _hasBlinkSample;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final status = await _repo.getFaceStatus();
      if (!mounted) return;
      if (status.isCompleted) {
        sl<AppState>().setFaceEnrolled(true);
        context.go('/home');
        return;
      }
      setState(() {
        _loading = false;
        _statusLabel = _friendlyStatusLabel(status.sampleCount);
      });
      _scheduleTour();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = faceApiErrorMessage(
          e,
          fallback: 'We couldn’t check your face setup. Please try again.',
        );
      });
      _scheduleTour();
    }
  }

  void _scheduleTour({bool force = false}) {
    if (_loading && !force) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        _startTour(force: force);
      });
    });
  }

  Future<void> _startTour({bool force = false}) async {
    if (!mounted) return;
    if (_tourStarted && !force) return;
    _tourStarted = true;
    final ctx = _showcaseContext;
    if (ctx == null || !ctx.mounted) {
      _tourStarted = false;
      return;
    }
    try {
      ShowCaseWidget.of(ctx).startShowCase([_stepActionKey]);
    } catch (_) {
      _tourStarted = false;
    }
  }

  void _goToStep(_EnrollStep step) {
    setState(() {
      _step = step;
      _error = null;
    });
    if (step == _EnrollStep.capture) {
      _syncCaptureMode();
    } else {
      unawaited(_stopBlinkWatch());
    }
  }

  void _syncCaptureMode() {
    if (!_cameraReady || _captureComplete) {
      unawaited(_stopBlinkWatch());
      return;
    }
    if (_needsBlinkSample) {
      setState(() {
        _captureGuidance = 'Almost done — blink once, like a normal blink';
      });
      unawaited(_startBlinkWatch());
    } else {
      unawaited(_stopBlinkWatch());
      setState(() {
        _captureGuidance =
            'Photo ${_samplePaths.length + 1} of $_targetSamples — look at the camera';
      });
    }
  }

  String _friendlyStatusLabel(int sampleCount) {
    if (sampleCount <= 0) {
      return 'This only takes about a minute.';
    }
    return 'You already have $sampleCount photo(s) saved. Let’s finish setup.';
  }

  Future<void> _startCamera() async {
    if (_cameraStarting) return;
    setState(() {
      _cameraStarting = true;
      _error = null;
    });
    try {
      final permitted = await Permission.camera.request();
      if (!permitted.isGranted) {
        if (!mounted) return;
        setState(() {
          _cameraStarting = false;
          _error =
              'Please allow camera access so we can set up your face for attendance.';
        });
        return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final previous = _camera;
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();

      _detector ??= FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,
          enableTracking: true,
          performanceMode: FaceDetectorMode.fast,
        ),
      );

      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _cameraStarting = false;
      });
      if (previous != null) {
        unawaited(previous.dispose());
      }
      _goToStep(_EnrollStep.capture);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cameraStarting = false;
        _error =
            'We couldn’t open the camera. Close other camera apps and try again.';
      });
    }
  }

  Future<void> _captureOpenSample() async {
    if (_needsBlinkSample || _captureComplete || _capturing) return;
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      setState(() => _error = 'Please turn on the camera first.');
      return;
    }
    setState(() {
      _capturing = true;
      _error = null;
    });
    try {
      await _stopBlinkWatch();
      final file = await camera.takePicture();
      if (!mounted) return;
      setState(() {
        _samplePaths.add(file.path);
        _capturing = false;
      });
      if (_captureComplete) {
        _goToStep(_EnrollStep.review);
      } else {
        _syncCaptureMode();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _capturing = false;
        _error = 'That photo didn’t save. Please try again.';
      });
    }
  }

  Future<void> _captureBlinkSample() async {
    if (_capturing || _captureComplete) return;
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;

    setState(() {
      _capturing = true;
      _captureGuidance = 'Nice! Saving your blink photo…';
    });
    try {
      await _stopBlinkWatch();
      final file = await camera.takePicture();
      if (!mounted) return;
      setState(() {
        _blinkSampleIndexes.add(_samplePaths.length);
        _samplePaths.add(file.path);
        _capturing = false;
        _error = null;
      });
      if (_captureComplete) {
        _goToStep(_EnrollStep.review);
      } else {
        _syncCaptureMode();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _capturing = false;
        _error = 'We missed that blink. Please blink once more.';
      });
      _syncCaptureMode();
    }
  }

  Future<void> _startBlinkWatch() async {
    final camera = _camera;
    final detector = _detector;
    if (camera == null ||
        detector == null ||
        !camera.value.isInitialized ||
        _streaming ||
        _capturing ||
        !_needsBlinkSample) {
      return;
    }
    _blinkDetector.reset();
    setState(() {
      _blinkWatching = true;
      _captureGuidance = 'Almost done — blink once, like a normal blink';
    });
    _streaming = true;
    try {
      await camera.startImageStream(_onCaptureFrame);
    } catch (_) {
      _streaming = false;
      if (mounted) {
        setState(() {
          _blinkWatching = false;
          _error =
              'We couldn’t detect a blink. Go back, then open the camera again.';
        });
      }
    }
  }

  Future<void> _stopBlinkWatch() async {
    final camera = _camera;
    if (!_streaming || camera == null) return;
    _streaming = false;
    try {
      await camera.stopImageStream();
    } catch (_) {}
    if (mounted) {
      setState(() => _blinkWatching = false);
    }
  }

  Future<void> _onCaptureFrame(CameraImage image) async {
    if (_processingFrame ||
        _capturing ||
        _detector == null ||
        _camera == null ||
        _step != _EnrollStep.capture ||
        !_needsBlinkSample) {
      return;
    }
    final now = DateTime.now();
    if (_lastProcessedAt != null &&
        now.difference(_lastProcessedAt!) < _minFrameInterval) {
      return;
    }
    _processingFrame = true;
    _lastProcessedAt = now;
    try {
      final input = _inputImageFromCamera(image, _camera!);
      if (input == null) return;
      final faces = await _detector!.processImage(input);
      if (!mounted ||
          _capturing ||
          _step != _EnrollStep.capture ||
          !_needsBlinkSample) {
        return;
      }
      if (faces.length != 1) {
        _updateCaptureGuidance(
          faces.isEmpty
              ? 'Move a little closer so your face fills the oval'
              : 'Make sure only you are in the photo',
        );
        return;
      }
      final face = faces.first;
      final blinked = _blinkDetector.observe(
        leftEyeOpen: face.leftEyeOpenProbability,
        rightEyeOpen: face.rightEyeOpenProbability,
      );
      if (blinked) {
        await _captureBlinkSample();
        return;
      }
      _updateCaptureGuidance('Almost done — blink once, like a normal blink');
    } catch (_) {
      // drop frame
    } finally {
      _processingFrame = false;
    }
  }

  void _updateCaptureGuidance(String value) {
    if (!mounted || value == _captureGuidance) return;
    setState(() => _captureGuidance = value);
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

  Future<void> _retakeCaptures() async {
    await _stopBlinkWatch();
    _blinkDetector.reset();
    setState(() {
      _samplePaths.clear();
      _blinkSampleIndexes.clear();
      _error = null;
      _captureGuidance = 'Fit your face in the oval, then take a photo';
    });
    _goToStep(_EnrollStep.capture);
  }

  Future<void> _enroll() async {
    if (!_captureComplete) {
      setState(
        () => _error =
            'Please finish all $_targetSamples photos (including one blink) first.',
      );
      return;
    }
    setState(() {
      _enrolling = true;
      _error = null;
    });
    try {
      await _stopBlinkWatch();
      final cam = _camera;
      _camera = null;
      if (mounted) setState(() {});
      if (cam != null) {
        await cam.dispose();
      }

      final status = await _repo.enrollFaceSamples(
        _samplePaths.map(File.new).toList(),
      );
      if (!status.isCompleted) {
        final refreshed = await _repo.getFaceStatus();
        if (!refreshed.isCompleted) {
          throw Exception('Enrollment did not complete.');
        }
      }
      sl<AppState>().setFaceEnrolled(true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You’re all set! Face setup complete.')),
      );
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enrolling = false;
        _error = faceApiErrorMessage(
          e,
          fallback: 'We couldn’t finish setup. Please try again.',
        );
      });
    }
  }

  @override
  void dispose() {
    final cam = _camera;
    final detector = _detector;
    _camera = null;
    _detector = null;
    _streaming = false;
    unawaited(() async {
      try {
        if (cam != null && cam.value.isStreamingImages) {
          await cam.stopImageStream();
        }
      } catch (_) {}
      await cam?.dispose();
      await detector?.close();
    }());
    super.dispose();
  }

  String get _stepTitle {
    switch (_step) {
      case _EnrollStep.camera:
        return 'Let’s get started';
      case _EnrollStep.capture:
        return _needsBlinkSample ? 'One quick blink' : 'Take your photos';
      case _EnrollStep.review:
        return 'Looking good!';
    }
  }

  String get _showcaseTitle {
    switch (_step) {
      case _EnrollStep.camera:
        return 'Turn on your camera';
      case _EnrollStep.capture:
        return _needsBlinkSample ? 'Blink naturally' : 'Take clear photos';
      case _EnrollStep.review:
        return 'Save your face';
    }
  }

  String get _showcaseDescription {
    switch (_step) {
      case _EnrollStep.camera:
        return 'Tap the button below to turn on your camera.';
      case _EnrollStep.capture:
        return _needsBlinkSample
            ? 'Blink once the way you normally would. We’ll take the photo for you.'
            : 'Take $_openSamples clear photos of your face, then we’ll ask you to blink.';
      case _EnrollStep.review:
        return 'If the photos look clear, tap Save to finish.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final useDarkChrome = _step == _EnrollStep.capture;

    return PopScope(
      canPop: false,
      child: ShowCaseWidget(
        onFinish: () => _tourStarted = true,
        builder: (showcaseContext) {
          _showcaseContext = showcaseContext;
          return Scaffold(
            backgroundColor:
                useDarkChrome ? Colors.black : EmployeeColors.scaffold,
            appBar: AppBar(
              backgroundColor:
                  useDarkChrome ? Colors.black : EmployeeColors.scaffold,
              foregroundColor:
                  useDarkChrome ? Colors.white : EmployeeColors.textPrimary,
              elevation: 0,
              automaticallyImplyLeading: false,
              title: Text(
                'Set up your face',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color:
                      useDarkChrome ? Colors.white : EmployeeColors.textPrimary,
                ),
              ),
              actions: [
                if (_stepIndex > 0 && !_enrolling)
                  IconButton(
                    tooltip: 'Go back',
                    onPressed: () =>
                        _goToStep(_EnrollStep.values[_stepIndex - 1]),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                IconButton(
                  tooltip: 'Need a tip?',
                  onPressed: () {
                    _tourStarted = false;
                    unawaited(_startTour(force: true));
                  },
                  icon: const Icon(Icons.help_outline_rounded),
                ),
              ],
            ),
            body: _loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      _EnrollmentStepper(
                        currentIndex: _stepIndex,
                        labels: _stepLabels,
                        dark: useDarkChrome,
                      ),
                      Expanded(child: _buildStepBody()),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _buildStepBody() {
    switch (_step) {
      case _EnrollStep.camera:
        return _buildCameraIntroStep();
      case _EnrollStep.capture:
        return _buildCaptureStep();
      case _EnrollStep.review:
        return _buildReviewStep();
    }
  }

  Widget _buildCameraIntroStep() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _stepTitle,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              'We’ll take 2 clear photos of your face, then ask you to blink once. This helps keep your attendance secure.',
              style: TextStyle(
                color: EmployeeColors.textBody,
                height: 1.4,
              ),
            ),
            if (_statusLabel != null) ...[
              const SizedBox(height: 8),
              Text(
                _statusLabel!,
                style: const TextStyle(color: EmployeeColors.textMuted),
              ),
            ],
            const SizedBox(height: 20),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: ColoredBox(
                  color: Colors.black,
                  child: _cameraReady
                      ? _CameraCoverPreview(controller: _camera!)
                      : const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.face_retouching_natural_rounded,
                                color: Colors.white54,
                                size: 64,
                              ),
                              SizedBox(height: 12),
                              Text(
                                'Your camera will show here',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
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
            Showcase(
              key: _stepActionKey,
              title: _showcaseTitle,
              description: _showcaseDescription,
              child: EmployeePrimaryButton(
                label: _cameraStarting
                    ? 'Opening camera…'
                    : _cameraReady
                        ? 'Next'
                        : 'Turn on camera',
                onPressed: _cameraStarting
                    ? null
                    : _cameraReady
                        ? () => _goToStep(_EnrollStep.capture)
                        : _startCamera,
                icon: Icons.videocam_rounded,
                loading: _cameraStarting,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCaptureStep() {
    final waitingBlink = _needsBlinkSample;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Keep controls compact so the face guide stays clear.
        const bottomPanelHeight = 148.0;
        final previewHeight = constraints.maxHeight - bottomPanelHeight;
        final ovalWidth = (constraints.maxWidth * 0.72).clamp(200.0, 280.0);
        final ovalHeight = ovalWidth * 1.25;

        return Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_cameraReady)
                    _CameraCoverPreview(controller: _camera!)
                  else
                    const ColoredBox(color: Colors.black),
                  // Face guide sits in the upper preview, not under the bottom bar.
                  Positioned(
                    top: (previewHeight - ovalHeight) * 0.35,
                    left: (constraints.maxWidth - ovalWidth) / 2,
                    width: ovalWidth,
                    height: ovalHeight,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(ovalWidth),
                          border: Border.all(
                            color: waitingBlink
                                ? const Color(0xFF4ADE80)
                                : Colors.white70,
                            width: 2.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Compact top guidance — stays above the oval.
                  Positioned(
                    top: 12,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _stepTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _captureGuidance,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              height: 1.3,
                              fontSize: 13,
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFFCA5A5),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: bottomPanelHeight,
              width: double.infinity,
              color: Colors.black,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    _sampleThumbStrip(dark: true, compact: true),
                    const SizedBox(height: 10),
                    Showcase(
                      key: _stepActionKey,
                      title: _showcaseTitle,
                      description: _showcaseDescription,
                      child: waitingBlink
                          ? Container(
                              width: double.infinity,
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFF4ADE80),
                                ),
                              ),
                              child: Text(
                                _capturing
                                    ? 'Saving your blink…'
                                    : _blinkWatching
                                        ? 'Go ahead — blink now'
                                        : 'Blink when you’re ready',
                                style: const TextStyle(
                                  color: Color(0xFF4ADE80),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                          : EmployeePrimaryButton(
                              label: _capturing
                                  ? 'Taking photo…'
                                  : 'Take photo (${_samplePaths.length + 1}/$_targetSamples)',
                              onPressed: _capturing || _enrolling
                                  ? null
                                  : _captureOpenSample,
                              icon: Icons.camera_alt_rounded,
                              loading: _capturing,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _sampleThumbStrip({required bool dark, bool compact = false}) {
    final size = compact ? 52.0 : null;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_targetSamples, (i) {
        final path = i < _samplePaths.length ? _samplePaths[i] : null;
        final isBlinkSlot = i == _openSamples;
        final isBlinkSample = _blinkSampleIndexes.contains(i);
        final slot = DecoratedBox(
          decoration: BoxDecoration(
            color: dark ? Colors.white12 : EmployeeColors.iconWell,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: path != null
                  ? (isBlinkSample
                      ? const Color(0xFF4ADE80)
                      : (dark
                          ? const Color(0xFF4ADE80)
                          : EmployeeColors.success))
                  : (isBlinkSlot
                      ? (dark
                          ? const Color(0xFF4ADE80).withValues(alpha: 0.5)
                          : EmployeeColors.success.withValues(alpha: 0.5))
                      : (dark ? Colors.white24 : EmployeeColors.border)),
            ),
          ),
          child: path == null
              ? Center(
                  child: Text(
                    isBlinkSlot ? 'Blink' : '${i + 1}',
                    style: TextStyle(
                      fontSize: compact ? 11 : 14,
                      fontWeight: FontWeight.w600,
                      color: dark ? Colors.white54 : EmployeeColors.textMuted,
                    ),
                  ),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(
                        File(path),
                        fit: BoxFit.cover,
                        cacheWidth: 160,
                      ),
                      if (isBlinkSample)
                        const Align(
                          alignment: Alignment.bottomCenter,
                          child: ColoredBox(
                            color: Color(0x99000000),
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                'Blink',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF4ADE80),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        );

        if (size != null) {
          return Padding(
            padding: EdgeInsets.only(right: i < _targetSamples - 1 ? 8 : 0),
            child: SizedBox(width: size, height: size, child: slot),
          );
        }
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < _targetSamples - 1 ? 8 : 0),
            child: AspectRatio(aspectRatio: 1, child: slot),
          ),
        );
      }),
    );
  }

  Widget _buildReviewStep() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _stepTitle,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Take a quick look. If anything is blurry, you can retake them.',
              style: TextStyle(
                color: EmployeeColors.textBody,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            _sampleThumbStrip(dark: false),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: EmployeeColors.success),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Color(0xFF166534)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'All set — your blink photo is included. Ready to save.',
                      style: TextStyle(
                        color: Color(0xFF166534),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (_error != null) ...[
              Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
              const SizedBox(height: 12),
            ],
            TextButton(
              onPressed: _enrolling ? null : _retakeCaptures,
              child: const Text('Retake photos'),
            ),
            const SizedBox(height: 8),
            Showcase(
              key: _stepActionKey,
              title: _showcaseTitle,
              description: _showcaseDescription,
              child: EmployeePrimaryButton(
                label: _enrolling ? 'Saving…' : 'Save my face',
                onPressed: _enrolling || !_captureComplete ? null : _enroll,
                icon: Icons.verified_user_rounded,
                loading: _enrolling,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-bleed camera preview that covers its parent without stretching.
class _CameraCoverPreview extends StatelessWidget {
  const _CameraCoverPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    final preview = controller.value.previewSize;
    // previewSize is landscape (width > height) even in portrait orientation.
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

class _EnrollmentStepper extends StatelessWidget {
  const _EnrollmentStepper({
    required this.currentIndex,
    required this.labels,
    required this.dark,
  });

  final int currentIndex;
  final List<String> labels;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final active = dark ? Colors.white : EmployeeColors.primary;
    final inactive = dark ? Colors.white38 : EmployeeColors.border;
    final done = dark ? const Color(0xFF4ADE80) : EmployeeColors.success;
    final labelColor = dark ? Colors.white70 : EmployeeColors.textMuted;
    final activeLabel = dark ? Colors.white : EmployeeColors.textPrimary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 18),
                  color: i <= currentIndex ? done : inactive,
                ),
              ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < currentIndex
                        ? done
                        : i == currentIndex
                            ? active
                            : Colors.transparent,
                    border: Border.all(
                      color: i <= currentIndex
                          ? (i < currentIndex ? done : active)
                          : inactive,
                      width: 2,
                    ),
                  ),
                  child: i < currentIndex
                      ? Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: dark ? Colors.black : Colors.white,
                        )
                      : Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: i == currentIndex
                                ? (dark ? Colors.black : Colors.white)
                                : labelColor,
                          ),
                        ),
                ),
                const SizedBox(height: 4),
                Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        i == currentIndex ? FontWeight.w700 : FontWeight.w500,
                    color: i == currentIndex ? activeLabel : labelColor,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
