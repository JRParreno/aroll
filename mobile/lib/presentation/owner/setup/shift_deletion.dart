import 'package:dio/dio.dart';

const shiftDeleteBlockedMessageText =
    'This shift cannot be deleted because an employee assigned to it '
    'is currently timed in. Ask them to complete Time Out, then try again.';

String? shiftDeleteBlockedMessage(DioException error) {
  final data = error.response?.data;
  if (data is! Map) return null;
  final detail = data['detail'];
  if (detail is! Map) return null;
  if (detail['code'] != 'shift_delete_blocked') return null;
  final message = detail['message'];
  if (message is String && message.isNotEmpty) return message;
  return shiftDeleteBlockedMessageText;
}
