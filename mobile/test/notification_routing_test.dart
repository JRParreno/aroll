import 'package:aroll_mobile/presentation/shared/notification_routing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('employee overtime opens shift history', () {
    expect(
      notificationDestination(type: 'overtime_approved'),
      '/shift-history',
    );
  });

  test('employee schedule reminder opens schedule', () {
    expect(
      notificationDestination(type: 'schedule_reminder'),
      '/schedule',
    );
  });

  test('employee payroll adjustment opens payslip', () {
    expect(
      notificationDestination(type: 'payroll_adjustment_added'),
      '/payslip',
    );
  });

  test('deep link wins over type fallback', () {
    expect(
      notificationDestination(
        type: 'overtime_submitted',
        deepLink: '/shift-history?attendance_record_id=1',
      ),
      '/shift-history?attendance_record_id=1',
    );
  });

  test('owner overtime opens attendance', () {
    expect(
      notificationDestination(type: 'overtime_submitted', owner: true),
      '/owner/attendance',
    );
  });

  test('icon kinds stay specific', () {
    expect(notificationIconKind('overtime_rejected'), IconDataForType.overtime);
    expect(notificationIconKind('schedule_cancelled'), IconDataForType.schedule);
    expect(
      notificationIconKind('payroll_adjustment_changed'),
      IconDataForType.payroll,
    );
  });
}
