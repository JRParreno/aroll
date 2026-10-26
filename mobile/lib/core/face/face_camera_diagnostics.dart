import 'dart:developer' as developer;

/// Throttled camera diagnostics. Never includes image bytes or identity data.
class FaceCameraDiagnostics {
  FaceCameraDiagnostics._();

  static final Map<String, DateTime> _lastSummary = {};
  static String? _lastError;
  static DateTime? _lastErrorAt;

  static void streamStarted(String screen, String format) {
    developer.log(
      '$screen image stream started format=$format',
      name: 'aroll.face.camera',
    );
  }

  static void streamStopped(String screen) {
    developer.log('$screen image stream stopped', name: 'aroll.face.camera');
  }

  static void streamFailed(String screen, Object error, StackTrace stack) {
    developer.log(
      '$screen image stream failed',
      name: 'aroll.face.camera',
      error: error,
      stackTrace: stack,
    );
  }

  static void frame({
    required String screen,
    required int planes,
    required int rawFormat,
    required int width,
    required int height,
    required String planeLayout,
    required int? rotation,
    required bool converted,
    required int? outputBytes,
    String? skipReason,
  }) {
    _summary(
      'frame',
      '$screen planes=$planes raw=$rawFormat ${width}x$height '
      'layout=$planeLayout rotation=$rotation converted=$converted '
      'nv21Bytes=$outputBytes'
      '${skipReason == null ? '' : ' skip=$skipReason'}',
    );
  }

  static void faces({
    required String screen,
    required int count,
    required String boxes,
  }) {
    _summary('faces', '$screen faces=$count boxes=$boxes');
  }

  static void qualityRejected({
    required String screen,
    required String reason,
    required String box,
  }) {
    _summary('quality', '$screen quality rejected reason="$reason" box=$box');
  }

  static void error(String message, Object error, StackTrace stack) {
    final now = DateTime.now();
    final text = '$message: $error';
    if (_lastError == text &&
        _lastErrorAt != null &&
        now.difference(_lastErrorAt!) < const Duration(seconds: 1)) {
      return;
    }
    _lastError = text;
    _lastErrorAt = now;
    developer.log(
      message,
      name: 'aroll.face.camera',
      error: error,
      stackTrace: stack,
    );
  }

  static void _summary(String key, String message) {
    final now = DateTime.now();
    final previous = _lastSummary[key];
    if (previous != null &&
        now.difference(previous) < const Duration(seconds: 1)) {
      return;
    }
    _lastSummary[key] = now;
    developer.log(message, name: 'aroll.face.camera');
  }
}

String faceBoxText(Object left, Object top, Object right, Object bottom) {
  return '$left,$top,$right,$bottom';
}
