import 'package:dio/dio.dart';

const scheduleRemovalFallback = 'Failed to remove schedule';

String scheduleRemovalErrorMessage(DioException error) {
  final data = error.response?.data;
  if (data is Map) {
    final detail = data['detail'];
    if (detail is String && detail.trim().isNotEmpty) return detail;
    if (detail is Map) {
      final message = detail['message']?.toString();
      if (message != null && message.trim().isNotEmpty) return message;
    }
  }
  return scheduleRemovalFallback;
}
