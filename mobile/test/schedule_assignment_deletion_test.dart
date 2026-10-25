import 'package:aroll_mobile/presentation/owner/schedule_assignment_deletion.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const openMessage =
      'This schedule cannot be removed because the employee is currently timed in. '
      'Ask them to complete Time Out, then try again.';

  DioException errorWith(Object? data) {
    return DioException(
      requestOptions: RequestOptions(path: '/schedules/assignments/1'),
      response: Response(
        requestOptions: RequestOptions(path: '/schedules/assignments/1'),
        statusCode: 409,
        data: data,
      ),
    );
  }

  test('schedule removal shows the backend detail', () {
    expect(
      scheduleRemovalErrorMessage(errorWith({'detail': openMessage})),
      openMessage,
    );
    expect(openMessage, contains('Time Out'));
  });

  test('schedule removal shows a structured detail message', () {
    expect(
      scheduleRemovalErrorMessage(
        errorWith({
          'detail': {'message': 'Attendance has already been recorded.'},
        }),
      ),
      'Attendance has already been recorded.',
    );
  });

  test('schedule removal keeps the generic fallback without a usable message', () {
    expect(
      scheduleRemovalErrorMessage(errorWith(<String, dynamic>{})),
      scheduleRemovalFallback,
    );
    expect(
      scheduleRemovalErrorMessage(errorWith({'detail': '  '})),
      scheduleRemovalFallback,
    );
    expect(
      scheduleRemovalErrorMessage(
        DioException(
          requestOptions: RequestOptions(path: '/schedules/assignments/1'),
        ),
      ),
      scheduleRemovalFallback,
    );
  });
}
