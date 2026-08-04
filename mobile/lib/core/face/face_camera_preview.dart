import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Full field-of-view camera preview — aspect-fit, no BoxFit.cover crop/zoom.
class FullFovCameraPreview extends StatelessWidget {
  const FullFovCameraPreview({super.key, required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }

    final preview = controller.value.previewSize;
    // previewSize is reported in landscape sensor coords.
    final sensorW = preview?.width ?? 1280;
    final sensorH = preview?.height ?? 720;
    final portraitAspect = sensorH / sensorW;

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: portraitAspect,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

/// Guide-only oval. Does not crop or zoom the camera image.
class FaceGuideOverlay extends StatelessWidget {
  const FaceGuideOverlay({
    super.key,
    this.ringColor = const Color(0xFFE8E8E8),
    this.accentColor = const Color(0x334ADE80),
  });

  final Color ringColor;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final ovalW = w * 0.78;
        final ovalH = h * 0.42;
        final center = Offset(w / 2, h * 0.42);

        return IgnorePointer(
          child: CustomPaint(
            size: Size(w, h),
            painter: _GuidePainter(
              oval: Rect.fromCenter(
                center: center,
                width: ovalW,
                height: ovalH,
              ),
              ringColor: ringColor,
              accentColor: accentColor,
            ),
          ),
        );
      },
    );
  }
}

class _GuidePainter extends CustomPainter {
  const _GuidePainter({
    required this.oval,
    required this.ringColor,
    required this.accentColor,
  });

  final Rect oval;
  final Color ringColor;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.48);
    final hole = Path()..addOval(oval);
    final full = Path()..addRect(Offset.zero & size);
    canvas.drawPath(Path.combine(PathOperation.difference, full, hole), dim);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = ringColor;
    canvas.drawOval(oval, ring);

    final soft = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = accentColor;
    canvas.drawOval(oval.inflate(4), soft);
  }

  @override
  bool shouldRepaint(covariant _GuidePainter oldDelegate) =>
      oldDelegate.oval != oval ||
      oldDelegate.ringColor != ringColor ||
      oldDelegate.accentColor != accentColor;
}

/// Initialize zoom to optical/digital 1.0x when the platform allows it.
Future<void> setCameraZoomOneX(CameraController controller) async {
  try {
    await controller.setZoomLevel(1.0);
  } catch (_) {}
}
