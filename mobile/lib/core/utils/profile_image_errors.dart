import 'package:dio/dio.dart';

String profileImageErrorMessage(Object error, {required String action}) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    final detail = _errorDetail(error.response?.data);
    if (status == 401 || status == 403) {
      return 'You are not authorized to $action your profile picture.';
    }
    if (status == 400 && detail != null) {
      return detail;
    }
    if (status == 400) {
      return 'Invalid image. Use a JPG or PNG under 2.5 MB.';
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return 'Network error. Check your connection and try again.';
    }
    if (status != null && status >= 500) {
      return 'Server error. Please try again shortly.';
    }
  }
  return 'Unable to $action profile picture.';
}

String? _errorDetail(Object? data) {
  if (data is Map<String, dynamic>) {
    final detail = data['detail'];
    if (detail is String && detail.trim().isNotEmpty) {
      return detail;
    }
  }
  return null;
}
