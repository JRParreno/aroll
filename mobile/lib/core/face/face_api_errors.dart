import 'package:dio/dio.dart';

String faceApiErrorMessage(Object error, {required String fallback}) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map) {
      final detail = data['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
      if (detail is Map) {
        final code = detail['code']?.toString();
        final message = detail['message']?.toString();
        if (message != null && message.isNotEmpty) {
          return _friendlyCode(code) ?? message;
        }
        return _friendlyCode(code) ?? fallback;
      }
    }
  }
  return fallback;
}

String? _friendlyCode(String? code) {
  switch (code) {
    case 'outside_geofence':
      return 'Please move closer to your work site, then try again.';
    case 'no_face':
      return 'We couldn’t see your face clearly. Hold the phone steady and try again.';
    case 'not_enrolled':
      return 'Your face isn’t set up yet. Finish face setup, or ask your manager for help.';
    case 'face_mismatch':
      return 'That didn’t match your saved face. Try again in good light.';
    case 'challenge_not_found':
    case 'challenge_expired':
    case 'challenge_used':
      return 'That check timed out. Please start again.';
    case 'pose_not_centered':
      return 'Look straight at the camera.';
    case 'turn_not_detected':
      return 'Turn your head a bit more the way the screen asks.';
    case 'turn_wrong_direction':
      return 'Turn your head the other way.';
    case 'identity_changed':
      return 'Please keep the same person in the frame for every step.';
    case 'face_required':
      return 'You’ll need face recognition to clock in or out.';
    case 'face_enrollment_required':
      return 'Please finish setting up your face first (3 quick photos).';
    default:
      return null;
  }
}
