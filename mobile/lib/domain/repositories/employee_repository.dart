import 'dart:io';

import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/domain/entities/employee_workplace_policies.dart';
import 'package:aroll_mobile/domain/entities/face_liveness.dart';
import 'package:aroll_mobile/domain/entities/leave_request.dart';
import 'package:aroll_mobile/domain/entities/legal_consent.dart';

abstract class EmployeeRepository {
  Future<EmployeeDashboard> getDashboard();

  Future<EmployeeProfile> getProfile();

  Future<void> registerRecoveryEmail(String email);

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

  Future<LegalConsentStatus> getConsentStatus();

  Future<LegalConsentStatus> acceptConsent({
    required List<String> types,
    required Map<String, String> versions,
    required bool adultAcknowledged,
    String client = 'mobile',
  });

  Future<EmployeeConsents> getConsents();

  Future<EmployeeConsents> acceptConsentDocument(
    String documentId, {
    String client = 'mobile',
  });

  /// Append-only biometric consent withdrawal (existing backend endpoint).
  Future<void> withdrawBiometricConsent({String client = 'mobile'});

  /// Mark account-level permissions onboarding complete (auth identity only).
  Future<void> completePermissionsOnboarding();

  Future<PublicLegalPage> getPublicLegalPage(String businessCode);

  Future<FaceStatus> enrollFaceSamples(List<File> images);

  Future<EmployeeProfile> updateProfileImage(String imageData);

  Future<EmployeeProfile> removeProfileImage();

  Future<String> downloadPayslipPdf({DateTime? asOf});

  Future<EmployeeWorksite> getWorksite();

  Future<EmployeeWorkplacePolicies> getWorkplacePolicies();

  Future<void> confirmWorkplaceWifiFallback(
    String bssid, {
    int? observedRssiDbm,
  });

  Future<AttendanceClockResult> clockInWithFace({
    double? latitude,
    double? longitude,
    double? horizontalAccuracyM,
    FaceQuickCapture? capture,
    String? shiftAssignmentId,
    String? observedBssid,
    int? observedRssiDbm,
    String? locationEvidence,
  });

  Future<AttendanceClockResult> clockOutWithFace({
    double? latitude,
    double? longitude,
    double? horizontalAccuracyM,
    FaceQuickCapture? capture,
    String? observedBssid,
    int? observedRssiDbm,
    String? locationEvidence,
  });

  Future<List<LeaveRequestItem>> getLeaveRequests({String? status});

  Future<LeaveRequestItem> getLeaveRequest(String requestId);

  Future<LeaveRequestItem> createLeaveRequest({
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
    String? otherLeaveSpecification,
    String? supportingDocument,
  });

  Future<LeaveRequestItem> updateLeaveRequest({
    required String requestId,
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
    String? otherLeaveSpecification,
    String? supportingDocument,
  });

  Future<LeaveRequestItem> cancelLeaveRequest(String requestId);

  Future<LeaveBalance> getLeaveBalances({int? year});

  Future<LeaveRequestPreview> previewLeaveRequest({
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
  });

  Future<List<Map<String, dynamic>>> notifications({
    bool unreadOnly = false,
    int limit = 50,
  });

  Future<int> unreadNotificationCount({String? createdAfter});

  Future<void> markNotificationRead(String notificationId);

  Future<int> markAllNotificationsRead({String? createdThrough});

  Future<void> registerDeviceToken({
    required String token,
    required String platform,
  });
}
