import 'package:aroll_mobile/core/face/blink_detector.dart';

enum FaceGesture { blink, smile }

/// Client-side blink or smile detector (ML Kit probabilities).
/// Used to decide *when* to capture; server still checks identity.
class GestureLivenessDetector {
  GestureLivenessDetector({
    this.smileThreshold = 0.55,
    this.smileHoldFrames = 3,
    BlinkDetector? blinkDetector,
  }) : _blink = blinkDetector ?? BlinkDetector();

  final BlinkDetector _blink;
  final double smileThreshold;
  final int smileHoldFrames;

  int _smileFrames = 0;
  bool _smileLatched = false;

  void reset() {
    _blink.reset();
    _smileFrames = 0;
    _smileLatched = false;
  }

  /// Returns a gesture once when blink or smile completes; otherwise null.
  FaceGesture? observe({
    required double? leftEyeOpen,
    required double? rightEyeOpen,
    required double? smiling,
  }) {
    if (_blink.observe(
      leftEyeOpen: leftEyeOpen,
      rightEyeOpen: rightEyeOpen,
    )) {
      return FaceGesture.blink;
    }

    if (smiling != null && smiling >= smileThreshold) {
      _smileFrames += 1;
      if (_smileFrames >= smileHoldFrames && !_smileLatched) {
        _smileLatched = true;
        return FaceGesture.smile;
      }
    } else {
      _smileFrames = 0;
      _smileLatched = false;
    }
    return null;
  }
}
