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

  bool get isCompleted =>
      faceRegistrationStatus == 'completed' && sampleCount > 0;

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

/// Single-frame capture after on-device blink or smile.
class FaceQuickCapture extends Equatable {
  const FaceQuickCapture({
    required this.imagePath,
    required this.gesture,
  });

  final String imagePath;
  /// `blink` or `smile`
  final String gesture;

  @override
  List<Object?> get props => [imagePath, gesture];
}
