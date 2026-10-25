import 'dart:io';

import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/domain/entities/employee_workplace_policies.dart';
import 'package:aroll_mobile/domain/entities/face_liveness.dart';
import 'package:aroll_mobile/domain/entities/leave_request.dart';
import 'package:aroll_mobile/domain/entities/legal_consent.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/attendance_correction_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    sl.registerSingleton<AppState>(AppState());
    sl.registerSingleton<EmployeeRepository>(_QuietEmployeeRepository());
  });

  tearDown(() async {
    await sl.reset();
  });

  testWidgets('recorded Time In is locked on the correction form', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final timeIn = DateTime.utc(2026, 10, 21, 8, 10, 6);
    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceCorrectionScreen(item: _item(timeIn: timeIn)),
      ),
    );
    await tester.pump();

    expect(find.text('Time In (locked)'), findsOneWidget);
    expect(find.text('8:10 AM'), findsWidgets);
    expect(
      find.text('Edit Time Out and remarks only. Time In is locked.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Time In (locked)'));
    await tester.pump();
    expect(find.byType(TimePickerDialog), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a shift with no Time In can still set one', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceCorrectionScreen(
          item: _item(timeIn: null, timeOut: null, status: 'absent'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Time In (locked)'), findsNothing);
    expect(find.text('Time In'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('24-hour shift start is used and a 12-hour label is not parsed', () {
    expect(timeOfDayFrom24Hour('17:00')?.hour, 17);
    expect(timeOfDayFrom24Hour('17:00:00')?.hour, 17);
    expect(timeOfDayFrom24Hour('23:00:00')?.hour, 23);
    expect(timeOfDayFrom24Hour('5:00 PM'), isNull);
    expect(timeOfDayFrom24Hour('5:00 AM'), isNull);
  });

  testWidgets('empty Time In prefills from the 24-hour shift start', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceCorrectionScreen(
          item: _item(
            timeIn: null,
            status: 'absent',
            omitTimeOut: true,
            shiftStart: '5:00 AM',
            shiftEnd: '11:00 PM',
            shiftStartTime: '17:00:00',
            shiftEndTime: '23:00:00',
          ),
        ),
      ),
    );
    await tester.pump();

    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map(
          (widget) => (widget.data ?? widget.textSpan?.toPlainText() ?? '')
              .replaceAll('\u202f', ' ')
              .replaceAll('\u00a0', ' '),
        )
        .toList();
    expect(labels, contains('5:00 PM'));
    expect(labels, contains('11:00 PM'));
    expect(
      labels.any((text) => text.contains('5:00 AM')),
      isTrue,
    );
    expect(find.text('Time In (locked)'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

EmployeeShiftHistoryItem _item({
  required DateTime? timeIn,
  DateTime? timeOut,
  String status = 'late',
  bool omitTimeOut = false,
  String shiftStart = '8:00 AM',
  String shiftEnd = '12:00 PM',
  String? shiftStartTime,
  String? shiftEndTime,
}) {
  return EmployeeShiftHistoryItem(
    id: 'record-1',
    assignmentId: 'assignment-1',
    attendanceRecordId: 'record-1',
    date: DateTime.utc(2026, 10, 21),
    shiftName: 'Morning Shift',
    shiftStart: shiftStart,
    shiftEnd: shiftEnd,
    shiftStartTime: shiftStartTime,
    shiftEndTime: shiftEndTime,
    timeIn: timeIn,
    timeOut: omitTimeOut
        ? null
        : (timeOut ?? DateTime.utc(2026, 10, 21, 12, 4, 1)),
    status: status,
    overtimeMinutes: 0,
    holidayName: null,
  );
}

class _QuietEmployeeRepository implements EmployeeRepository {
  @override
  Future<List<Map<String, dynamic>>> notifications({
    bool unreadOnly = false,
    int limit = 50,
  }) async {
    return const [];
  }

  @override
  Future<EmployeeDashboard> getDashboard() => throw UnimplementedError();

  @override
  Future<EmployeeProfile> getProfile() => throw UnimplementedError();

  @override
  Future<void> registerRecoveryEmail(String email) => throw UnimplementedError();

  @override
  Future<List<EmployeeScheduleItem>> getSchedule({
    DateTime? startDate,
    DateTime? endDate,
    bool activeOnly = false,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<EmployeeShiftHistoryItem>> getShiftHistory() =>
      throw UnimplementedError();

  @override
  Future<AttendanceCorrectionRequest> submitAttendanceCorrection({
    required String shiftAssignmentId,
    DateTime? requestedTimeIn,
    DateTime? requestedTimeOut,
    required String reason,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<AttendanceCorrectionRequest>> getAttendanceCorrections() =>
      throw UnimplementedError();

  @override
  Future<EmployeePayroll> getPayroll({DateTime? asOf, int historyLimit = 6}) =>
      throw UnimplementedError();

  @override
  Future<EmployeePayslip> getPayslip({DateTime? asOf}) =>
      throw UnimplementedError();

  @override
  Future<FaceStatus> getFaceStatus() => throw UnimplementedError();

  @override
  Future<LegalConsentStatus> getConsentStatus() => throw UnimplementedError();

  @override
  Future<LegalConsentStatus> acceptConsent({
    required List<String> types,
    required Map<String, String> versions,
    required bool adultAcknowledged,
    String client = 'mobile',
  }) =>
      throw UnimplementedError();

  @override
  Future<EmployeeConsents> getConsents() => throw UnimplementedError();

  @override
  Future<EmployeeConsents> acceptConsentDocument(
    String documentId, {
    String client = 'mobile',
  }) =>
      throw UnimplementedError();

  @override
  Future<void> withdrawBiometricConsent({String client = 'mobile'}) =>
      throw UnimplementedError();

  @override
  Future<void> completePermissionsOnboarding() => throw UnimplementedError();

  @override
  Future<PublicLegalPage> getPublicLegalPage(String businessCode) =>
      throw UnimplementedError();

  @override
  Future<FaceStatus> enrollFaceSamples(List<File> images) =>
      throw UnimplementedError();

  @override
  Future<EmployeeProfile> updateProfileImage(String imageData) =>
      throw UnimplementedError();

  @override
  Future<EmployeeProfile> removeProfileImage() => throw UnimplementedError();

  @override
  Future<String> downloadPayslipPdf({DateTime? asOf}) =>
      throw UnimplementedError();

  @override
  Future<EmployeeWorksite> getWorksite() => throw UnimplementedError();

  @override
  Future<EmployeeWorkplacePolicies> getWorkplacePolicies() =>
      throw UnimplementedError();

  @override
  Future<void> confirmWorkplaceWifiFallback(
    String bssid, {
    int? observedRssiDbm,
  }) =>
      throw UnimplementedError();

  @override
  Future<AttendanceClockResult> clockInWithFace({
    double? latitude,
    double? longitude,
    double? horizontalAccuracyM,
    FaceQuickCapture? capture,
    String? shiftAssignmentId,
    String? observedBssid,
    int? observedRssiDbm,
    String? locationEvidence,
  }) =>
      throw UnimplementedError();

  @override
  Future<AttendanceClockResult> clockOutWithFace({
    double? latitude,
    double? longitude,
    double? horizontalAccuracyM,
    FaceQuickCapture? capture,
    String? observedBssid,
    int? observedRssiDbm,
    String? locationEvidence,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<LeaveRequestItem>> getLeaveRequests({String? status}) =>
      throw UnimplementedError();

  @override
  Future<LeaveRequestItem> getLeaveRequest(String requestId) =>
      throw UnimplementedError();

  @override
  Future<LeaveRequestItem> createLeaveRequest({
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
    String? otherLeaveSpecification,
    String? supportingDocument,
  }) =>
      throw UnimplementedError();

  @override
  Future<LeaveRequestItem> updateLeaveRequest({
    required String requestId,
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
    String? otherLeaveSpecification,
    String? supportingDocument,
  }) =>
      throw UnimplementedError();

  @override
  Future<LeaveRequestItem> cancelLeaveRequest(String requestId) =>
      throw UnimplementedError();

  @override
  Future<LeaveBalance> getLeaveBalances({int? year}) =>
      throw UnimplementedError();

  @override
  Future<LeaveRequestPreview> previewLeaveRequest({
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
  }) =>
      throw UnimplementedError();

  @override
  Future<int> unreadNotificationCount({String? createdAfter}) =>
      throw UnimplementedError();

  @override
  Future<void> markNotificationRead(String notificationId) =>
      throw UnimplementedError();

  @override
  Future<int> markAllNotificationsRead({String? createdThrough}) =>
      throw UnimplementedError();

  @override
  Future<void> registerDeviceToken({
    required String token,
    required String platform,
  }) =>
      throw UnimplementedError();
}
