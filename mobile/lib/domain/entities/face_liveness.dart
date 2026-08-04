import 'package:aroll_mobile/core/face/face_model.dart';
import 'package:equatable/equatable.dart';

class FaceStatus extends Equatable {
  const FaceStatus({
    required this.employeeId,
    required this.faceRegistrationStatus,
    required this.sampleCount,
    required this.modelVersion,
    required this.faceRegisteredAt,
    required this.threshold,
  });

  final String employeeId;
  final String faceRegistrationStatus;
  final int sampleCount;
  final String? modelVersion;
  final DateTime? faceRegisteredAt;
  final double threshold;

  /// True only when enrollment exists and matches the current ArcFace model.
  bool get hasCompatibleModel =>
      modelVersion != null && modelVersion == kExpectedFaceModelVersion;

  /// Incomplete or outdated embeddings force re-registration (no matching attempt).
  bool get isCompleted =>
      faceRegistrationStatus == 'completed' &&
      sampleCount > 0 &&
      hasCompatibleModel;

  bool get needsReregistration => !isCompleted;

  @override
  List<Object?> get props => [
        employeeId,
        faceRegistrationStatus,
        sampleCount,
        modelVersion,
        faceRegisteredAt,
        threshold,
      ];
}

/// Single-frame capture for attendance. Gesture is a Form contract value
/// (`blink`/`smile`); identity matching is always performed on the server.
class FaceQuickCapture extends Equatable {
  const FaceQuickCapture({
    required this.imagePath,
    this.gesture = 'blink',
  });

  final String imagePath;
  /// `blink` or `smile` — required by the clock-*-face Form contract.
  final String gesture;

  @override
  List<Object?> get props => [imagePath, gesture];
}
