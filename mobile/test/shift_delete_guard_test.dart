import 'package:aroll_mobile/presentation/owner/setup/shift_deletion.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile shows the backend message when a timed-in employee blocks deletion', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/shifts/1'),
      response: Response(
        requestOptions: RequestOptions(path: '/shifts/1'),
        statusCode: 409,
        data: {
          'detail': {
            'code': 'shift_delete_blocked',
            'title': 'Cannot delete shift',
            'message': shiftDeleteBlockedMessageText,
          },
        },
      ),
    );

    expect(shiftDeleteBlockedMessage(error), shiftDeleteBlockedMessageText);
    expect(shiftDeleteBlockedMessageText, contains('currently timed in'));
    expect(shiftDeleteBlockedMessageText, contains('Time Out'));
  });

  test('a completed attendance error is not this restriction', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/shifts/1'),
      response: Response(
        requestOptions: RequestOptions(path: '/shifts/1'),
        statusCode: 409,
        data: {
          'detail': {
            'code': 'shift_in_progress',
            'message': 'This shift has already started and cannot be changed.',
          },
        },
      ),
    );

    expect(shiftDeleteBlockedMessage(error), isNull);
  });
}
