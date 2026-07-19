/// Simple open → closed → open blink detector using ML Kit eye-open probabilities.
class BlinkDetector {
  BlinkDetector({
    this.closedThreshold = 0.35,
    this.openThreshold = 0.65,
  });

  final double closedThreshold;
  final double openThreshold;

  bool _eyesWereClosed = false;

  void reset() {
    _eyesWereClosed = false;
  }

  /// Returns true once when a blink sequence completes.
  bool observe({
    required double? leftEyeOpen,
    required double? rightEyeOpen,
  }) {
    if (leftEyeOpen == null || rightEyeOpen == null) {
      _eyesWereClosed = false;
      return false;
    }

    final bothClosed =
        leftEyeOpen < closedThreshold && rightEyeOpen < closedThreshold;
    final bothOpen =
        leftEyeOpen > openThreshold && rightEyeOpen > openThreshold;

    if (bothClosed) {
      _eyesWereClosed = true;
      return false;
    }

    if (_eyesWereClosed && bothOpen) {
      _eyesWereClosed = false;
      return true;
    }

    return false;
  }
}
