import 'package:aroll_mobile/domain/entities/employee_portal.dart';

abstract class EmployeeRepository {
  Future<EmployeeDashboard> getDashboard();

  Future<EmployeeProfile> getProfile();

  Future<List<EmployeeScheduleItem>> getSchedule({
    DateTime? startDate,
    DateTime? endDate,
    bool activeOnly = false,
  });

  Future<List<EmployeeShiftHistoryItem>> getShiftHistory();

  Future<EmployeePayroll> getPayroll();

  Future<EmployeePayslip> getPayslip();

  Future<EmployeeProfile> updateFaceRegistration(String status);

  Future<EmployeeProfile> updateProfileImage(String imageData);

  Future<EmployeeProfile> removeProfileImage();

  Future<String> downloadPayslipPdf();

  Future<EmployeeWorksite> getWorksite();

  Future<AttendanceClockResult> clockIn({
    required double latitude,
    required double longitude,
    String? shiftAssignmentId,
  });

  Future<AttendanceClockResult> clockOut({
    required double latitude,
    required double longitude,
  });
}
