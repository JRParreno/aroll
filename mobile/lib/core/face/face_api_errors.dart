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
      return 'You’re currently outside your workplace’s allowed attendance area. '
          'Please move closer and try again.';
    case 'face_mismatch':
      return 'We couldn’t verify your face. Please make sure your face is '
          'clearly visible and try again.';
    case 'face_enrollment_quality':
      return 'Your face setup needs to be updated. Please set up your face again.';
    case 'multiple_faces':
      return 'Only one person should be visible during attendance.';
    case 'liveness_required':
      return 'Please look at the camera so we can confirm it’s you.';
    case 'inconsistent_samples':
      return 'Those photos don’t look consistent. Please scan again.';
    case 'no_face':
      return 'We couldn’t see your face clearly. Please look at the camera and try again.';
    case 'not_enrolled':
      return 'Your face isn’t set up yet. Finish face setup, or ask your manager for help.';
    case 'challenge_not_found':
    case 'challenge_expired':
    case 'challenge_used':
      return 'That check timed out. Please start again.';
    case 'pose_not_centered':
      return 'Center your face inside the guide.';
    case 'turn_not_detected':
    case 'turn_wrong_direction':
      return 'Please look straight at the camera.';
    case 'identity_changed':
      return 'Please keep the same person in the frame.';
    case 'face_required':
      return 'You’ll need face recognition to clock in or out.';
    case 'face_enrollment_required':
    case 'face_model_outdated':
      return 'Please finish setting up your face first.';
    case 'business_inactive':
      return 'This workplace isn’t active right now. Please contact your employer.';
    case 'employee_inactive':
      return 'Your account isn’t active. Please contact your employer.';
    case 'mock_location':
      return 'Location spoofing isn’t allowed. Please turn off any fake GPS apps and try again.';
    case 'not_clocked_in':
      return 'You need to clock in before you can clock out.';
    case 'already_clocked_out':
      return 'You’ve already completed attendance for this shift.';
    case 'incomplete_attendance':
      return 'Your shift has already ended and your attendance has been marked '
          'as incomplete because you forgot to clock out. Please submit an '
          'attendance correction request or contact your manager.';
    default:
      return null;
  }
}
