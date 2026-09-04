import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceQualityAssessment {
  const FaceQualityAssessment({
    required this.ok,
    required this.score,
    required this.guidance,
  });

  final bool ok;
  final double score;
  final String guidance;
}

/// Geometric / pose quality gate used by enrollment burst and attendance.
///
/// [naturalDistance] tunes fill ranges for holding the phone ~40–70 cm away
/// (identity-verification style). Attendance keeps the stricter default.
FaceQualityAssessment assessFaceQuality(
  Face face,
  Size imageSize, {
  double minScore = 0.58,
  bool naturalDistance = false,
}) {
  if (imageSize.width <= 0 || imageSize.height <= 0) {
    return const FaceQualityAssessment(
      ok: false,
      score: 0,
      guidance: 'Hold the phone steady and look at the camera',
    );
  }

  final minFill = naturalDistance ? 0.028 : 0.08;
  final maxFill = naturalDistance ? 0.42 : 0.72;
  final centerXTol = naturalDistance ? 0.28 : 0.22;
  final centerYTol = naturalDistance ? 0.32 : 0.28;

  final box = face.boundingBox;
  final fill = (box.width * box.height) / (imageSize.width * imageSize.height);
  if (fill < minFill) {
    return const FaceQualityAssessment(
      ok: false,
      score: 0.2,
      guidance: 'Move a little closer.',
    );
  }
  if (fill > maxFill) {
    return const FaceQualityAssessment(
      ok: false,
      score: 0.25,
      guidance: 'Move slightly farther away.',
    );
  }

  final centerX = box.center.dx / imageSize.width;
  final centerY = box.center.dy / imageSize.height;
  final centered =
      (centerX - 0.5).abs() <= centerXTol &&
      (centerY - 0.48).abs() <= centerYTol;
  if (!centered) {
    return const FaceQualityAssessment(
      ok: false,
      score: 0.35,
      guidance: 'Center your face inside the guide.',
    );
  }

  final yaw = face.headEulerAngleY?.abs() ?? 0;
  final pitch = face.headEulerAngleX?.abs() ?? 0;
  final roll = face.headEulerAngleZ?.abs() ?? 0;
  final maxYaw = naturalDistance ? 30.0 : 26.0;
  final maxPitch = naturalDistance ? 28.0 : 24.0;
  final maxRoll = naturalDistance ? 30.0 : 26.0;
  if (yaw > maxYaw || pitch > maxPitch || roll > maxRoll) {
    return const FaceQualityAssessment(
      ok: false,
      score: 0.3,
      guidance: 'Look straight at the camera.',
    );
  }

  // Glasses and heavier makeup often hide eye landmarks in ML Kit.
  // Do not block capture if the face box and pose are already good.
  final leftEye = face.landmarks[FaceLandmarkType.leftEye];
  final rightEye = face.landmarks[FaceLandmarkType.rightEye];
  final nose = face.landmarks[FaceLandmarkType.noseBase];
  final hasBothEyes = leftEye != null && rightEye != null;
  if (nose == null && !hasBothEyes) {
    return const FaceQualityAssessment(
      ok: false,
      score: 0.32,
      guidance: 'Keep your whole face visible.',
    );
  }

  final fillScore =
      ((fill - minFill) / (maxFill - minFill).clamp(0.01, 1.0)).clamp(0.0, 1.0);
  final poseScore =
      (1.0 - ((yaw + pitch + roll) / (maxYaw + maxPitch + maxRoll))).clamp(
        0.0,
        1.0,
      );
  final centerScore = (1.0 -
          (((centerX - 0.5).abs() / centerXTol) +
                  ((centerY - 0.48).abs() / centerYTol)) /
              2.0)
      .clamp(0.0, 1.0);
  final score = (0.45 * fillScore) + (0.35 * poseScore) + (0.20 * centerScore);

  if (score < minScore) {
    return FaceQualityAssessment(
      ok: false,
      score: score,
      guidance: naturalDistance
          ? 'Improve lighting.'
          : 'Hold still with good lighting',
    );
  }

  return FaceQualityAssessment(
    ok: true,
    score: score,
    guidance: 'Hold still…',
  );
}
