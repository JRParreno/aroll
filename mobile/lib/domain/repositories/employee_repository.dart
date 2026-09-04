import 'dart:io';

import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/domain/entities/face_liveness.dart';
import 'package:aroll_mobile/domain/entities/leave_request.dart';

abstract class EmployeeRepository {
  Future<EmployeeDashboard> getDashboard();

  Future<EmployeeProfile> getProfile();

  Future<List<EmployeeScheduleItem>> getSchedule({
    DateTime? startDate,
    DateTime? endDate,
    bool activeOnly = false,
  });

  Future<List<EmployeeShiftHistoryItem>> getShiftHistory();

  Future<AttendanceCorrectionRequest> submitAttendanceCorrection({
    required String shiftAssignmentId,
    DateTime? requestedTimeIn,
    DateTime? requestedTimeOut,
    required String reason,
  });

  Future<List<AttendanceCorrectionRequest>> getAttendanceCorrections();

  Future<EmployeePayroll> getPayroll({
    DateTime? asOf,
    int historyLimit = 6,
  });

  Future<EmployeePayslip> getPayslip({DateTime? asOf});

  Future<FaceStatus> getFaceStatus();

  Future<FaceStatus> enrollFaceSamples(List<File> images);

  Future<EmployeeProfile> updateProfileImage(String imageData);

  Future<EmployeeProfile> removeProfileImage();

  Future<String> downloadPayslipPdf();

  Future<EmployeeWorksite> getWorksite();

  Future<AttendanceClockResult> clockInWithFace({
    required double latitude,
    required double longitude,
    FaceQuickCapture? capture,
    String? shiftAssignmentId,
  });

  Future<AttendanceClockResult> clockOutWithFace({
    required double latitude,
    required double longitude,
    FaceQuickCapture? capture,
  });

  Future<List<LeaveRequestItem>> getLeaveRequests({String? status});

  Future<LeaveRequestItem> getLeaveRequest(String requestId);

  Future<LeaveRequestItem> createLeaveRequest({
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
    String? supportingDocument,
  });

  Future<LeaveRequestItem> updateLeaveRequest({
    required String requestId,
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
    String? supportingDocument,
  });

  Future<LeaveRequestItem> cancelLeaveRequest(String requestId);

  Future<List<Map<String, dynamic>>> notifications({
    bool unreadOnly = false,
    int limit = 50,
  });

  Future<int> unreadNotificationCount();

  Future<void> markNotificationRead(String notificationId);

  Future<void> markAllNotificationsRead();
}
