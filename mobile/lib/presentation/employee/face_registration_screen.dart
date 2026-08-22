import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/face/face_api_errors.dart';
import 'package:aroll_mobile/core/face/face_camera_preview.dart';
import 'package:aroll_mobile/core/face/face_quality.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Burst enrollment: capture many frames, keep the best open-eye stills.
const _burstDuration = Duration(milliseconds: 2600);
const _burstTargetFrames = 16;
const _minAcceptedFrames = 3;
const _maxUploadFrames = 5;
const _minFrameQuality = 0.55;
const _stableBeforeBurst = Duration(milliseconds: 700);

class _ScoredFrame {
  const _ScoredFrame({required this.path, required this.score});
  final String path;
  final double score;
}

class FaceRegistrationScreen extends StatefulWidget {
  const FaceRegistrationScreen({super.key});

  @override
  State<FaceRegistrationScreen> createState() => _FaceRegistrationScreenState();
}

class _FaceRegistrationScreenState extends State<FaceRegistrationScreen> {
  final _repo = sl<EmployeeRepository>();

  CameraController? _camera;
  FaceDetector? _detector;
  final List<_ScoredFrame> _selected = [];

  bool _loading = true;
  bool _enrolling = false;
  bool _cameraStarting = false;
  bool _bursting = false;
  bool _streaming = false;
  bool _processingFrame = false;
  bool _lastFrameOk = false;
  bool _finished = false;
  DateTime? _lastProcessedAt;
  DateTime? _stableSince;
  String? _error;
  String? _banner;
  String _guidance = 'Look naturally at the camera';
  int _framesCaptured = 0;
  int _framesAccepted = 0;
  double _progress = 0;

  static const _minFrameInterval = Duration(milliseconds: 140);

  bool get _cameraReady => _camera != null && _camera!.value.isInitialized;

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
        if (status.sampleCount > 0 && !status.hasCompatibleModel) {
          _banner =
              'Your face setup needs a quick update. Look at the camera to continue.';
        } else if (status.sampleCount > 0) {
          _banner = 'Let’s finish with a clearer scan.';
        }
      });
      await _startCamera();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = faceApiErrorMessage(
          e,
          fallback: 'We couldn’t check your face setup. Please try again.',
        );
      });
    }
  }

  Future<void> _startCamera() async {
    if (_cameraStarting || _cameraReady) return;
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
          _error = 'Please allow camera access to set up your face.';
        });
        return;
      }

      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final previous = _camera;
      final controller = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      await setCameraZoomOneX(controller);

      _detector ??= FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: false,
          enableLandmarks: true,
          enableTracking: true,
          performanceMode: FaceDetectorMode.fast,
          minFaceSize: 0.10,
        ),
      );

      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _cameraStarting = false;
        _guidance = 'Center your face inside the guide.';
      });
      if (previous != null) {
        unawaited(previous.dispose());
      }
      await _ensureStream();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cameraStarting = false;
        _error =
            'We couldn’t open the camera. Close other camera apps and try again.';
      });
    }
  }

  Future<void> _ensureStream() async {
    final camera = _camera;
    if (camera == null || _streaming || !camera.value.isInitialized) return;
    try {
      _streaming = true;
      await camera.startImageStream(_onPreviewFrame);
    } catch (_) {
      _streaming = false;
    }
  }

  Future<void> _stopStream() async {
    final camera = _camera;
    if (camera == null || !_streaming) return;
    _streaming = false;
    try {
      await camera.stopImageStream();
    } catch (_) {}
  }

  Future<void> _onPreviewFrame(CameraImage image) async {
    if (_bursting ||
        _enrolling ||
        _finished ||
        _processingFrame ||
        _detector == null) {
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
      if (!mounted || _bursting || _enrolling) return;

      if (faces.length != 1) {
        _lastFrameOk = false;
        _stableSince = null;
        _updateGuidance(
          faces.isEmpty
              ? 'Look naturally at the camera'
              : 'Only one person should be visible.',
        );
        return;
      }

      final assessment = assessFaceQuality(
        faces.first,
        Size(image.width.toDouble(), image.height.toDouble()),
        minScore: _minFrameQuality,
        naturalDistance: true,
      );
      _lastFrameOk = assessment.ok;
      if (!assessment.ok) {
        _stableSince = null;
        _updateGuidance(assessment.guidance);
        return;
      }

      _stableSince ??= now;
      final stableFor = now.difference(_stableSince!);
      _updateGuidance(
        stableFor < _stableBeforeBurst
            ? 'Hold still…'
            : 'Scanning… keep looking at the camera',
      );

      if (stableFor >= _stableBeforeBurst) {
        unawaited(_runBurstCapture());
      }
    } catch (_) {
      // Drop frame errors.
    } finally {
      _processingFrame = false;
    }
  }

  void _updateGuidance(String value) {
    if (!mounted || value == _guidance) return;
    setState(() => _guidance = value);
  }

  Future<void> _runBurstCapture() async {
    if (_bursting || _enrolling || _finished) return;
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;

    setState(() {
      _bursting = true;
      _error = null;
      _framesCaptured = 0;
      _framesAccepted = 0;
      _progress = 0;
      _guidance = 'Scanning… keep looking at the camera';
      _selected.clear();
    });

    final candidates = <_ScoredFrame>[];
    final tempDir = await getTemporaryDirectory();
    final started = DateTime.now();
    final employeeId = sl<AppState>().session?.userId ?? 'unknown';

    try {
      await _stopStream();

      while (DateTime.now().difference(started) < _burstDuration &&
          _framesCaptured < _burstTargetFrames) {
        if (!mounted) return;
        await Future<void>.delayed(const Duration(milliseconds: 130));

        late final XFile shot;
        try {
          shot = await camera.takePicture();
        } catch (_) {
          continue;
        }
        _framesCaptured += 1;

        final score = await _scoreStill(shot.path);
        if (score >= _minFrameQuality) {
          final dest = p.join(
            tempDir.path,
            'enroll_${DateTime.now().millisecondsSinceEpoch}_$_framesCaptured.jpg',
          );
          await File(shot.path).copy(dest);
          candidates.add(_ScoredFrame(path: dest, score: score));
          _framesAccepted = candidates.length;
        } else {
          try {
            await File(shot.path).delete();
          } catch (_) {}
        }

        if (mounted) {
          setState(() {
            _progress =
                DateTime.now().difference(started).inMilliseconds /
                    _burstDuration.inMilliseconds;
            _guidance = 'Scanning… $_framesAccepted clear frame(s)';
          });
        }
      }

      candidates.sort((a, b) => b.score.compareTo(a.score));
      final picked = candidates.take(_maxUploadFrames).toList();

      developer.log(
        'FACE_ENROLL_CLIENT employee_id=$employeeId '
        'captured=$_framesCaptured accepted=${candidates.length} '
        'selected=${picked.length}',
        name: 'aroll.face',
      );

      if (picked.length < _minAcceptedFrames) {
        if (!mounted) return;
        setState(() {
          _bursting = false;
          _progress = 0;
          _stableSince = null;
          _error =
              'We need a clearer view. Hold the phone a bit farther away with good lighting.';
          _guidance = 'Center your face inside the guide.';
        });
        await _ensureStream();
        return;
      }

      final keep = picked.map((e) => e.path).toSet();
      for (final c in candidates) {
        if (!keep.contains(c.path)) {
          try {
            await File(c.path).delete();
          } catch (_) {}
        }
      }

      if (!mounted) return;
      setState(() {
        _selected
          ..clear()
          ..addAll(picked);
        _bursting = false;
        _progress = 1;
      });
      await _enroll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bursting = false;
        _stableSince = null;
        _error = faceApiErrorMessage(
          e,
          fallback: 'Scan failed. Please try again.',
        );
      });
      await _ensureStream();
    }
  }

  Future<double> _scoreStill(String path) async {
    final detector = _detector;
    if (detector == null) return 0;
    try {
      final input = InputImage.fromFilePath(path);
      final faces = await detector.processImage(input);
      if (faces.length != 1) return 0;
      final face = faces.first;
      final box = face.boundingBox;
      final width = (box.right + 48).clamp(320.0, 2000.0);
      final height = (box.bottom + 48).clamp(320.0, 2000.0);
      return assessFaceQuality(
        face,
        Size(width, height),
        minScore: 0,
        naturalDistance: true,
      ).score;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _enroll() async {
    if (_selected.length < _minAcceptedFrames || _enrolling) return;
    setState(() {
      _enrolling = true;
      _error = null;
      _guidance = 'Saving your face…';
    });
    final employeeId = sl<AppState>().session?.userId ?? 'unknown';
    try {
      await _stopStream();
      final files = _selected.map((e) => File(e.path)).toList();
      developer.log(
        'FACE_ENROLL_CLIENT employee_id=$employeeId upload=${files.length}',
        name: 'aroll.face',
      );

      final status = await _repo.enrollFaceSamples(files);
      if (!status.isCompleted) {
        final refreshed = await _repo.getFaceStatus();
        if (!refreshed.isCompleted) {
          throw Exception('Enrollment did not complete.');
        }
      }

      developer.log(
        'FACE_ENROLL_CLIENT employee_id=$employeeId embedding_stored=YES '
        'samples=${status.sampleCount} model=${status.modelVersion}',
        name: 'aroll.face',
      );

      sl<AppState>().setFaceEnrolled(true);
      if (!mounted) return;
      setState(() {
        _finished = true;
        _enrolling = false;
        _guidance = 'You’re all set';
      });
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enrolling = false;
        _stableSince = null;
        _selected.clear();
        _error = faceApiErrorMessage(
          e,
          fallback: 'We couldn’t finish setup. Please try again.',
        );
        _guidance = 'Center your face inside the guide.';
      });
      await _ensureStream();
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

    if (Platform.isAndroid) {
      final bytes = image.planes.first.bytes;
      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    }

    final WriteBuffer buffer = WriteBuffer();
    for (final plane in image.planes) {
      buffer.putUint8List(plane.bytes);
    }
    return InputImage.fromBytes(
      bytes: buffer.done().buffer.asUint8List(),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.bgra8888,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white70),
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                if (_cameraReady)
                  FullFovCameraPreview(controller: _camera!)
                else
                  const ColoredBox(color: Colors.black),
                const FaceGuideOverlay(),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Back',
                              onPressed: _enrolling || _bursting
                                  ? null
                                  : () {
                                      if (context.canPop()) {
                                        context.pop();
                                      } else {
                                        context.go('/home');
                                      }
                                    },
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                              ),
                            ),
                            const Expanded(
                              child: Text(
                                'Set up your face',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 48),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _banner ??
                              'Register as you usually look at work — glasses and makeup are OK. Use them the same way when you clock in.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 14,
                            height: 1.35,
                          ),
                        ),
                        const Spacer(),
                        if (_bursting || _enrolling)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: _enrolling
                                    ? null
                                    : _progress.clamp(0.05, 1.0),
                                minHeight: 4,
                                backgroundColor: Colors.white24,
                                color: const Color(0xFF4ADE80),
                              ),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Column(
                            children: [
                              Text(
                                _guidance,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                ),
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFFFCA5A5),
                                    fontSize: 13,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                              if (!_bursting &&
                                  !_enrolling &&
                                  !_cameraReady &&
                                  !_cameraStarting) ...[
                                const SizedBox(height: 14),
                                EmployeePrimaryButton(
                                  label: 'Turn on camera',
                                  onPressed: _startCamera,
                                  icon: Icons.photo_camera_rounded,
                                ),
                              ],
                              if (_cameraStarting) ...[
                                const SizedBox(height: 12),
                                const Text(
                                  'Opening camera…',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                              if (_lastFrameOk &&
                                  !_bursting &&
                                  !_enrolling) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Stay still — scanning starts automatically',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.65),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
