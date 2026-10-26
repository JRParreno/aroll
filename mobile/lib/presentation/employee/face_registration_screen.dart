import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/face/face_api_errors.dart';
import 'package:aroll_mobile/core/face/face_camera_diagnostics.dart';
import 'package:aroll_mobile/core/face/face_camera_preview.dart';
import 'package:aroll_mobile/core/face/face_input_image.dart';
import 'package:aroll_mobile/core/face/face_quality.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/auth/sign_out_dialog.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
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

/// Close control while face enrollment is still required.
///
/// An in-flight upload is left alone because its completion navigates.
/// A local burst can be cancelled, then the screen pops or signs out.
enum FaceRegistrationDismiss { blocked, pop, signOut }

FaceRegistrationDismiss faceRegistrationDismiss({
  required bool canPop,
  required bool enrolling,
}) {
  if (enrolling) return FaceRegistrationDismiss.blocked;
  if (canPop) return FaceRegistrationDismiss.pop;
  return FaceRegistrationDismiss.signOut;
}

bool faceRegistrationBurstShouldStop({
  required bool closing,
  required bool elapsed,
  required bool frameLimitReached,
}) {
  return closing || elapsed || frameLimitReached;
}

/// Stored JPEG pixel size, before any EXIF display rotation.
///
/// [InputImage.fromFilePath] decodes this bitmap and uses EXIF only so the
/// detector knows which edge is up. [Face.boundingBox] stays in this bitmap:
/// (0, 0) is its upper-left pixel. This is not the live camera analysis size,
/// which swaps width and height for rotations of 90 and 270.
Size? _jpegStoredPixelSize(List<int> bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
  var offset = 2;
  while (offset + 1 < bytes.length) {
    if (bytes[offset] != 0xFF) return null;
    offset++;
    while (offset < bytes.length && bytes[offset] == 0xFF) {
      offset++;
    }
    if (offset >= bytes.length) return null;
    final marker = bytes[offset];
    offset++;
    // Markers with no length. Start-of-scan follows the frame header, so a
    // missing SOF by then means the file has no readable pixel size.
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD9)) {
      if (marker == 0xD8) continue;
      return null;
    }
    if (offset + 1 >= bytes.length) return null;
    final segmentLength = (bytes[offset] << 8) | bytes[offset + 1];
    if (segmentLength < 2 || offset + segmentLength > bytes.length) return null;
    final isStartOfFrame = marker == 0xC0 ||
        marker == 0xC1 ||
        marker == 0xC2 ||
        marker == 0xC3 ||
        marker == 0xC5 ||
        marker == 0xC6 ||
        marker == 0xC7 ||
        marker == 0xC9 ||
        marker == 0xCA ||
        marker == 0xCB ||
        marker == 0xCD ||
        marker == 0xCE ||
        marker == 0xCF;
    if (isStartOfFrame) {
      if (segmentLength < 7) return null;
      final height = (bytes[offset + 3] << 8) | bytes[offset + 4];
      final width = (bytes[offset + 5] << 8) | bytes[offset + 6];
      if (width <= 0 || height <= 0) return null;
      return Size(width.toDouble(), height.toDouble());
    }
    offset += segmentLength;
  }
  return null;
}

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
  bool _closing = false;
  Future<void>? _burstTask;
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
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: faceStreamImageFormat(android: Platform.isAndroid),
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
    } catch (error, stack) {
      FaceCameraDiagnostics.error(
        'registration camera open failed',
        error,
        stack,
      );
      if (!mounted) return;
      setState(() {
        _cameraStarting = false;
        _error =
            'We couldn’t open the camera. Close other camera apps and try again.';
      });
    }
  }

  Future<void> _retryCamera() async {
    if (!mounted) return;
    setState(() => _error = null);
    if (_cameraReady) {
      await _ensureStream();
      return;
    }
    await _startCamera();
  }

  Future<void> _ensureStream() async {
    final camera = _camera;
    if (camera == null || _streaming || !camera.value.isInitialized) return;
    try {
      _streaming = true;
      await camera.startImageStream(_onPreviewFrame);
      FaceCameraDiagnostics.streamStarted(
        'registration',
        faceStreamImageFormat(android: Platform.isAndroid).name,
      );
    } catch (error, stack) {
      _streaming = false;
      FaceCameraDiagnostics.streamFailed('registration', error, stack);
      if (!mounted) return;
      setState(() {
        _error =
            'The camera opened, but face scanning did not start. Close other camera apps and try again.';
        _guidance = 'Face scanning did not start.';
      });
    }
  }

  Future<void> _stopStream() async {
    final camera = _camera;
    if (camera == null || !_streaming) return;
    _streaming = false;
    try {
      await camera.stopImageStream();
      FaceCameraDiagnostics.streamStopped('registration');
    } catch (error, stack) {
      FaceCameraDiagnostics.error(
        'registration image stream stop failed',
        error,
        stack,
      );
    }
  }

  void _onPreviewFrame(CameraImage image) {
    if (_closing ||
        _bursting ||
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

    final CameraFaceConversion conversion;
    try {
      conversion = cameraFaceFrame(image, camera);
    } catch (error, stack) {
      FaceCameraDiagnostics.error(
        'registration frame conversion failed',
        error,
        stack,
      );
      return;
    }
    final frame = conversion.frame;
    _logFrame('registration', image, conversion);
    if (frame == null) return;

    _processingFrame = true;
    _lastProcessedAt = now;
    unawaited(_analyzePreviewFrame(frame, now));
  }

  Future<void> _analyzePreviewFrame(
    CameraFaceFrame frame,
    DateTime now,
  ) async {
    try {
      final faces = await _detector!.processImage(frame.input);
      _logFaces('registration', faces);
      if (!mounted || _closing || _bursting || _enrolling) return;

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
        frame.analysisSize,
        minScore: _minFrameQuality,
        naturalDistance: true,
      );
      _lastFrameOk = assessment.ok;
      if (!assessment.ok) {
        _stableSince = null;
        _updateGuidance(assessment.guidance);
        _logQualityRejection('registration', faces.first, assessment.guidance);
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
    } catch (error, stack) {
      FaceCameraDiagnostics.error(
        'registration face detection failed',
        error,
        stack,
      );
      _updateGuidance('Look naturally at the camera');
    } finally {
      _processingFrame = false;
    }
  }

  void _logFrame(
    String screen,
    CameraImage image,
    CameraFaceConversion conversion,
  ) {
    FaceCameraDiagnostics.frame(
      screen: screen,
      planes: image.planes.length,
      rawFormat: image.format.raw is int ? image.format.raw as int : -1,
      width: image.width,
      height: image.height,
      planeLayout: facePlaneLayout(image.planes),
      rotation: conversion.frame?.rotationDegrees,
      converted: conversion.frame != null,
      outputBytes: conversion.frame?.input.bytes?.length,
      skipReason: conversion.skipReason,
    );
  }

  void _logFaces(String screen, List<Face> faces) {
    final boxes = faces
        .map(
          (face) => faceBoxText(
            face.boundingBox.left.round(),
            face.boundingBox.top.round(),
            face.boundingBox.right.round(),
            face.boundingBox.bottom.round(),
          ),
        )
        .join(' ');
    FaceCameraDiagnostics.faces(
      screen: screen,
      count: faces.length,
      boxes: boxes.isEmpty ? 'none' : boxes,
    );
  }

  void _logQualityRejection(String screen, Face face, String reason) {
    FaceCameraDiagnostics.qualityRejected(
      screen: screen,
      reason: reason,
      box: faceBoxText(
        face.boundingBox.left.round(),
        face.boundingBox.top.round(),
        face.boundingBox.right.round(),
        face.boundingBox.bottom.round(),
      ),
    );
  }

  void _updateGuidance(String value) {
    if (!mounted || value == _guidance) return;
    setState(() => _guidance = value);
  }

  Future<void> _runBurstCapture() {
    if (_closing || _bursting || _enrolling || _finished) {
      _diag(
        'burst skipped closing=$_closing bursting=$_bursting '
        'enrolling=$_enrolling finished=$_finished',
      );
      return Future<void>.value();
    }
    final task = _runBurstCaptureBody();
    late final Future<void> tracked;
    tracked = task.whenComplete(() {
      if (identical(_burstTask, tracked)) _burstTask = null;
    });
    _burstTask = tracked;
    return tracked;
  }

  Future<void> _runBurstCaptureBody() async {
    if (_closing || _bursting || _enrolling || _finished) {
      _diag(
        'burst skipped closing=$_closing bursting=$_bursting '
        'enrolling=$_enrolling finished=$_finished',
      );
      return;
    }
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      _diag('burst skipped camera unavailable');
      return;
    }

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
    _diag(
      'burst start duration_ms=${_burstDuration.inMilliseconds} '
      'target=$_burstTargetFrames min_accepted=$_minAcceptedFrames',
    );

    try {
      await _stopStream();
      if (_closing || !mounted) {
        _diag(
          'burst stop reason=${_closing ? 'closing' : 'unmounted'} '
          'captured=$_framesCaptured accepted=${candidates.length}',
        );
        await _discardCaptured(candidates);
        _finishCancelledBurst();
        return;
      }

      var attempt = 0;
      while (!faceRegistrationBurstShouldStop(
        closing: _closing,
        elapsed: DateTime.now().difference(started) >= _burstDuration,
        frameLimitReached: _framesCaptured >= _burstTargetFrames,
      )) {
        if (_closing || !mounted) {
          _diag(
            'burst stop reason=${_closing ? 'closing' : 'unmounted'} '
            'captured=$_framesCaptured accepted=${candidates.length}',
          );
          await _discardCaptured(candidates);
          _finishCancelledBurst();
          return;
        }
        attempt += 1;
        await Future<void>.delayed(const Duration(milliseconds: 130));
        if (_closing || !mounted) break;

        late final XFile shot;
        final captureStarted = DateTime.now();
        try {
          shot = await camera.takePicture();
          _diag(
            'capture attempt=$attempt success '
            'elapsed_ms=${DateTime.now().difference(captureStarted).inMilliseconds}',
          );
        } catch (error) {
          _diag(
            'capture attempt=$attempt failure '
            'elapsed_ms=${DateTime.now().difference(captureStarted).inMilliseconds} '
            'error=${_diagError(error)}',
          );
          continue;
        }
        if (_closing || !mounted) {
          try {
            await File(shot.path).delete();
          } catch (error) {
            _diag(
              'capture attempt=$attempt delete failed error=${_diagError(error)}',
            );
          }
          break;
        }
        _framesCaptured += 1;

        final score = await _scoreStill(shot.path, attempt: attempt);
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
          } catch (error) {
            _diag(
              'capture attempt=$attempt delete failed error=${_diagError(error)}',
            );
          }
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

      if (_closing || !mounted) {
        _diag(
          'burst stop reason=${_closing ? 'closing' : 'unmounted'} '
          'captured=$_framesCaptured accepted=${candidates.length}',
        );
        await _discardCaptured(candidates);
        _finishCancelledBurst();
        return;
      }

      candidates.sort((a, b) => b.score.compareTo(a.score));
      final picked = candidates.take(_maxUploadFrames).toList();
      final elapsed = DateTime.now().difference(started).inMilliseconds;

      _diag(
        'burst end elapsed_ms=$elapsed captured=$_framesCaptured '
        'accepted=${candidates.length} selected=${picked.length} '
        'required=$_minAcceptedFrames',
      );

      if (picked.length < _minAcceptedFrames) {
        _diag(
          'burst rejected reason=below minimum accepted=${candidates.length} '
          'required=$_minAcceptedFrames',
        );
        if (!mounted) {
          _diag('burst rejected reason=unmounted before error ui');
          return;
        }
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

      if (_closing || !mounted) {
        _diag(
          'submit skipped reason=${_closing ? 'closing' : 'unmounted'} '
          'after burst',
        );
        await _discardCaptured(candidates);
        _finishCancelledBurst();
        return;
      }
      setState(() {
        _selected
          ..clear()
          ..addAll(picked);
        _bursting = false;
        _progress = 1;
      });
      await _enroll();
    } catch (e) {
      _diag('burst failed error=${_diagError(e)}');
      if (!mounted || _closing) {
        _diag(
          'burst failed reason=${_closing ? 'closing' : 'unmounted'} '
          'before error ui',
        );
        await _discardCaptured(candidates);
        _finishCancelledBurst();
        return;
      }
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

  Future<void> _discardCaptured(List<_ScoredFrame> frames) async {
    for (final frame in frames) {
      try {
        await File(frame.path).delete();
      } catch (error) {
        _diag('discard failed error=${_diagError(error)}');
      }
    }
  }

  void _finishCancelledBurst() {
    if (!mounted) return;
    setState(() {
      _bursting = false;
      _progress = 0;
      _stableSince = null;
    });
  }

  Future<void> _leaveFaceRegistration(FaceRegistrationDismiss action) async {
    if (action == FaceRegistrationDismiss.blocked || _closing) return;
    setState(() => _closing = true);
    _diag('close action=$action');
    final burst = _burstTask;
    if (burst != null) await burst;
    if (!mounted) return;
    await _stopStream();
    if (!mounted) return;
    if (action == FaceRegistrationDismiss.pop) {
      context.pop();
      return;
    }
    await confirmSignOut(context);
    if (!mounted) return;
    if (sl<AppState>().isLoggedIn) {
      setState(() => _closing = false);
      await _ensureStream();
    }
  }

  Future<double> _scoreStill(String path, {required int attempt}) async {
    final detector = _detector;
    if (detector == null) {
      _diag('still attempt=$attempt accepted=false reason=detector missing');
      return 0;
    }
    try {
      final bytes = await File(path).readAsBytes();
      final imageSize = _jpegStoredPixelSize(bytes);
      if (imageSize == null) {
        _diag(
          'still attempt=$attempt accepted=false faces=unknown '
          'reason=jpeg size unreadable',
        );
        return 0;
      }
      final image =
          '${imageSize.width.round()}x${imageSize.height.round()}';
      final faces = await detector.processImage(InputImage.fromFilePath(path));
      if (faces.length != 1) {
        _diag(
          'still attempt=$attempt accepted=false faces=${faces.length} '
          'image=$image score=0 guidance="face count"',
        );
        return 0;
      }
      final face = faces.first;
      final assessment = assessFaceQuality(
        face,
        imageSize,
        minScore: _minFrameQuality,
        naturalDistance: true,
      );
      final box = face.boundingBox;
      final area = imageSize.width * imageSize.height;
      final fill = area <= 0 ? 0.0 : (box.width * box.height) / area;
      final centerX =
          imageSize.width <= 0 ? 0.0 : box.center.dx / imageSize.width;
      final centerY =
          imageSize.height <= 0 ? 0.0 : box.center.dy / imageSize.height;
      _diag(
        'still attempt=$attempt accepted=${assessment.ok} faces=1 '
        'image=$image score=${assessment.score.toStringAsFixed(3)} '
        'fill=${fill.toStringAsFixed(3)} '
        'center=${centerX.toStringAsFixed(3)},${centerY.toStringAsFixed(3)} '
        'guidance="${assessment.guidance}"',
      );
      return assessment.ok ? assessment.score : 0;
    } catch (error) {
      _diag(
        'still attempt=$attempt accepted=false '
        'reason=detection failed error=${_diagError(error)}',
      );
      return 0;
    }
  }

  void _diag(String message) {
    developer.log('FACE_ENROLL_DIAG $message', name: 'FACE_ENROLL_DIAG');
  }

  String _diagError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      var code = '';
      if (data is Map) {
        final detail = data['detail'];
        if (detail is Map) code = detail['code']?.toString() ?? '';
      }
      return 'DioException type=${error.type.name} '
          'status=${error.response?.statusCode} code=$code';
    }
    final text = error.toString();
    return text.length <= 180 ? text : text.substring(0, 180);
  }

  Future<void> _enroll() async {
    if (_closing || _selected.length < _minAcceptedFrames || _enrolling) {
      _diag(
        'submit skipped closing=$_closing selected=${_selected.length} '
        'enrolling=$_enrolling required=$_minAcceptedFrames',
      );
      return;
    }
    setState(() {
      _enrolling = true;
      _error = null;
      _guidance = 'Saving your face…';
    });
    try {
      await _stopStream();
      final files = _selected.map((e) => File(e.path)).toList();
      _diag('submit start files=${files.length} path=/employee/face-samples');

      final status = await _repo.enrollFaceSamples(files);
      _diag(
        'submit response completed=${status.isCompleted} '
        'status=${status.faceRegistrationStatus} '
        'samples=${status.sampleCount} model=${status.modelVersion}',
      );
      if (!status.isCompleted) {
        final refreshed = await _repo.getFaceStatus();
        _diag(
          'submit refresh completed=${refreshed.isCompleted} '
          'status=${refreshed.faceRegistrationStatus} '
          'samples=${refreshed.sampleCount} model=${refreshed.modelVersion}',
        );
        if (!refreshed.isCompleted) {
          throw Exception('Enrollment did not complete.');
        }
      }

      _diag('submit complete');

      if (_closing || !mounted) {
        _diag(
          'submit complete reason=${_closing ? 'closing' : 'unmounted'} '
          'before success ui',
        );
        return;
      }
      sl<AppState>().setFaceEnrolled(true);
      setState(() {
        _finished = true;
        _enrolling = false;
        _guidance = 'You’re all set';
      });
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (_closing || !mounted) {
        _diag(
          'submit complete reason=${_closing ? 'closing' : 'unmounted'} '
          'before home',
        );
        return;
      }
      context.go('/home');
    } catch (e) {
      _diag('submit failed error=${_diagError(e)}');
      if (!mounted) {
        _diag('submit failed reason=unmounted before error ui');
        return;
      }
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
                              onPressed: _enrolling || _closing
                                  ? null
                                  : () {
                                      final action = faceRegistrationDismiss(
                                        canPop: context.canPop(),
                                        enrolling: _enrolling,
                                      );
                                      _leaveFaceRegistration(action);
                                    },
                              icon: Icon(
                                Icons.close_rounded,
                                color: _enrolling || _closing
                                    ? Colors.white38
                                    : Colors.white,
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
                              'Register as you usually look at work — glasses and makeup are OK. Use them the same way when you time in.',
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
                                  !_cameraStarting &&
                                  (!_cameraReady || _error != null)) ...[
                                const SizedBox(height: 14),
                                EmployeePrimaryButton(
                                  label: _cameraReady
                                      ? 'Try face scan again'
                                      : 'Turn on camera',
                                  onPressed: _retryCamera,
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
