import 'package:aroll_mobile/domain/entities/employee_portal.dart';

abstract class EmployeeRepository {
  Future<EmployeeDashboard> getDashboard();

  Future<EmployeeProfile> getProfile();

  Future<List<EmployeeScheduleItem>> getSchedule();

  Future<List<EmployeeShiftHistoryItem>> getShiftHistory();

  Future<EmployeePayroll> getPayroll();

  Future<EmployeePayslip> getPayslip();

  Future<EmployeeProfile> updateFaceRegistration(String status);

  Future<EmployeeProfile> updateProfileImage(String imageData);

  Future<String> downloadPayslipPdf();
}
