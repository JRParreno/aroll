import 'dart:io';

import 'package:aroll_mobile/core/face/face_api_errors.dart';
import 'package:aroll_mobile/core/face/gesture_liveness_detector.dart';
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
  const FaceLivenessCaptureScreen({super.key});

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
  String? _error;
  String _guidance = 'Opening camera…';

  static const _minFrameInterval = Duration(milliseconds: 400);

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
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final detector = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,
          enableTracking: true,
          performanceMode: FaceDetectorMode.fast,
        ),
      );
      if (!mounted) return;
      setState(() {
        _camera = controller;
        _detector = detector;
        _busy = false;
        _guidance = 'Look at the camera, then blink or smile';
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
        _updateGuidance(
          faces.isEmpty
              ? 'Move closer so your face is clearly in view'
              : 'Make sure only you are in the photo',
        );
        return;
      }

      final face = faces.first;
      final gesture = _gesture.observe(
        leftEyeOpen: face.leftEyeOpenProbability,
        rightEyeOpen: face.rightEyeOpenProbability,
        smiling: face.smilingProbability,
      );
      if (gesture != null) {
        await _finish(gesture);
        return;
      }
      _updateGuidance('Look at the camera, then blink or smile');
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
    setState(() {
      _guidance = gesture == FaceGesture.blink
          ? 'Blink detected — taking photo…'
          : 'Smile detected — taking photo…';
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Face check'),
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      EmployeePrimaryButton(
                        label: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final ovalW =
                        (constraints.maxWidth * 0.72).clamp(200.0, 280.0);
                    final ovalH = ovalW * 1.25;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_camera != null && _camera!.value.isInitialized)
                          _CameraCoverPreview(controller: _camera!),
                        Positioned(
                          top: (constraints.maxHeight - ovalH) * 0.28,
                          left: (constraints.maxWidth - ovalW) / 2,
                          width: ovalW,
                          height: ovalH,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(ovalW),
                                border: Border.all(
                                  color: Colors.white70,
                                  width: 2.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: SafeArea(
                            top: false,
                            child: Container(
                              width: double.infinity,
                              padding:
                                  const EdgeInsets.fromLTRB(20, 20, 20, 28),
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black87,
                                  ],
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Quick face check',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _guidance,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 15,
                                      height: 1.35,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Blink or smile — no head turn needed',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
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
