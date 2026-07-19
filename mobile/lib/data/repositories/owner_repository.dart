import 'package:aroll_mobile/core/network/api_client.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

class OwnerRepository {
  OwnerRepository(this._api);

  final ApiClient _api;

  Future<Map<String, dynamic>> performance({int days = 30}) async =>
      (await _api.dio.get<Map<String, dynamic>>(
        '/owner/performance',
        queryParameters: {'days': days},
      ))
          .data!;

  Future<Map<String, dynamic>> setupStatus() async =>
      (await _api.dio.get<Map<String, dynamic>>('/businesses/me/setup-status'))
          .data!;

  Future<List<Map<String, dynamic>>> employees({bool includeInactive = false}) async =>
      _list(await _api.dio.get<List<dynamic>>(
        '/employees',
        queryParameters: includeInactive ? {'include_inactive': true} : null,
      ));

  Future<Map<String, dynamic>> createEmployee({
    required String fullName,
    required String positionTitle,
    String? positionId,
    String employmentType = 'full_time',
    String? phone,
  }) async =>
      (await _api.dio.post<Map<String, dynamic>>(
        '/employees',
        data: {
          'full_name': fullName,
          'position_title': positionTitle,
          if (positionId != null && positionId.isNotEmpty)
            'position_id': positionId,
          'employment_type': employmentType,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
        },
      ))
          .data!;

  Future<Map<String, dynamic>> updateEmployee({
    required String employeeId,
    required String fullName,
    required String positionTitle,
    String? positionId,
    required String employmentType,
    String? phone,
  }) async =>
      (await _api.dio.put<Map<String, dynamic>>(
        '/employees/$employeeId',
        data: {
          'full_name': fullName,
          'position_title': positionTitle,
          if (positionId != null && positionId.isNotEmpty)
            'position_id': positionId,
          'employment_type': employmentType,
          'phone': phone,
        },
      ))
          .data!;

  Future<Map<String, dynamic>> deleteEmployee(String employeeId) async =>
      (await _api.dio.delete<Map<String, dynamic>>('/employees/$employeeId'))
          .data ??
      {'status': 'ok'};

  Future<Map<String, dynamic>> reactivateEmployee(String employeeId) async =>
      (await _api.dio.post<Map<String, dynamic>>(
        '/employees/$employeeId/reactivate',
      ))
          .data!;

  Future<Map<String, dynamic>> weeklySchedule(DateTime weekStart) async =>
      (await _api.dio.get<Map<String, dynamic>>(
        '/schedules/weekly',
        queryParameters: {'week_start': _date(weekStart)},
      ))
          .data!;

  Future<Map<String, dynamic>> attendance() async =>
      (await _api.dio
              .get<Map<String, dynamic>>('/owner/reports/attendance'))
          .data!;

  Future<Map<String, dynamic>> payroll() async =>
      (await _api.dio.get<Map<String, dynamic>>('/owner/reports/payroll'))
          .data!;

  Future<Map<String, dynamic>> employeePayslip(String employeeId) async =>
      (await _api.dio.get<Map<String, dynamic>>(
        '/owner/reports/payroll/$employeeId/payslip',
      ))
          .data!;

  Future<Map<String, dynamic>> location() async =>
      (await _api.dio.get<Map<String, dynamic>>('/businesses/me/location'))
          .data!;

  Future<Map<String, dynamic>> accountSettings() async =>
      (await _api.dio
              .get<Map<String, dynamic>>('/businesses/me/account-settings'))
          .data!;

  Future<String> updateProfileImage(String imageData) async {
    final response = await _api.dio.post<Map<String, dynamic>>(
      '/businesses/me/profile/image',
      data: {'image_data': imageData},
    );
    return response.data!['owner_profile_image_url'] as String;
  }

  Future<void> removeProfileImage() async {
    await _api.dio.delete<void>('/businesses/me/profile/image');
  }

  Future<Map<String, dynamic>> businessSettings() async =>
      (await _api.dio
              .get<Map<String, dynamic>>('/businesses/me/business-settings'))
          .data!;

  Future<List<Map<String, dynamic>>> shifts() async =>
      _list(await _api.dio.get<List<dynamic>>('/shifts'));

  Future<List<Map<String, dynamic>>> holidays() async =>
      _list(await _api.dio.get<List<dynamic>>('/holidays'));

  Future<Map<String, dynamic>> assignSchedule({
    required String shiftId,
    required String workDate,
    required List<String> employeeIds,
    bool isRestDayWork = false,
  }) async =>
      (await _api.dio.post<Map<String, dynamic>>(
        '/schedules/assign',
        data: {
          'shift_id': shiftId,
          'work_date': workDate,
          'employee_ids': employeeIds,
          'is_rest_day_work': isRestDayWork,
        },
      ))
          .data!;

  Future<Map<String, dynamic>> updateScheduleAssignment({
    required String assignmentId,
    required String shiftId,
    required String workDate,
    bool? isRestDayWork,
  }) async =>
      (await _api.dio.put<Map<String, dynamic>>(
        '/schedules/assignments/$assignmentId',
        data: {
          'shift_id': shiftId,
          'work_date': workDate,
          if (isRestDayWork != null) 'is_rest_day_work': isRestDayWork,
        },
      ))
          .data!;

  Future<void> deleteScheduleAssignment(String assignmentId) async {
    await _api.dio.delete<void>('/schedules/assignments/$assignmentId');
  }

  Future<Map<String, dynamic>> createShift({
    required String name,
    required String startTime,
    required String endTime,
    required int employeeCapacity,
    String shiftType = 'morning',
    int breakMinutes = 0,
  }) async =>
      (await _api.dio.post<Map<String, dynamic>>(
        '/shifts',
        data: {
          'name': name,
          'shift_type': shiftType,
          'start_time': startTime,
          'end_time': endTime,
          'employee_capacity': employeeCapacity,
          'break_minutes': breakMinutes,
        },
      ))
          .data!;

  Future<void> deleteShift(String shiftId) async {
    await _api.dio.delete<void>('/shifts/$shiftId');
  }

  Future<Map<String, dynamic>> createPosition({
    required String title,
    required double dailyRate,
    String? description,
  }) async =>
      (await _api.dio.post<Map<String, dynamic>>(
        '/positions',
        data: {
          'title': title,
          'daily_rate': dailyRate,
          if (description != null && description.isNotEmpty)
            'description': description,
        },
      ))
          .data!;

  Future<void> deletePosition(String positionId) async {
    await _api.dio.delete<void>('/positions/$positionId');
  }

  Future<Map<String, dynamic>> updatePayrollConfig(
    Map<String, dynamic> payload,
  ) async =>
      (await _api.dio.put<Map<String, dynamic>>(
        '/businesses/me/payroll-config',
        data: payload,
      ))
          .data!;

  Future<Map<String, dynamic>> updateAttendancePolicy(
    Map<String, dynamic> payload,
  ) async =>
      (await _api.dio.put<Map<String, dynamic>>(
        '/businesses/me/attendance-policy',
        data: payload,
      ))
          .data!;

  Future<Map<String, dynamic>> restDayPolicy() async =>
      (await _api.dio
              .get<Map<String, dynamic>>('/businesses/me/rest-day-policy'))
          .data!;

  Future<Map<String, dynamic>> updateRestDayPolicy(
    Map<String, dynamic> payload,
  ) async =>
      (await _api.dio.put<Map<String, dynamic>>(
        '/businesses/me/rest-day-policy',
        data: payload,
      ))
          .data!;

  Future<Map<String, dynamic>> updateLocation(
    Map<String, dynamic> payload,
  ) async =>
      (await _api.dio.put<Map<String, dynamic>>(
        '/businesses/me/location',
        data: payload,
      ))
          .data!;

  Future<Map<String, dynamic>> completeSetup() async =>
      (await _api.dio.post<Map<String, dynamic>>(
        '/businesses/me/complete-setup',
      ))
          .data!;

  Future<List<Map<String, dynamic>>> seedDefaultHolidays() async =>
      _list(await _api.dio.post<List<dynamic>>('/holidays/seed-defaults'));

  Future<Map<String, dynamic>> createHoliday({
    required String name,
    required String holidayDate,
    bool isPaid = true,
    required double payMultiplier,
    String holidayType = 'company',
  }) async =>
      (await _api.dio.post<Map<String, dynamic>>(
        '/holidays',
        data: {
          'name': name,
          'holiday_date': holidayDate,
          'is_paid': isPaid,
          'pay_multiplier': payMultiplier,
          'holiday_type': holidayType,
        },
      ))
          .data!;

  Future<Map<String, dynamic>> updateHoliday(
    String holidayId,
    Map<String, dynamic> payload,
  ) async =>
      (await _api.dio.put<Map<String, dynamic>>(
        '/holidays/$holidayId',
        data: payload,
      ))
          .data!;

  Future<void> deleteHoliday(String holidayId) async {
    await _api.dio.delete<void>('/holidays/$holidayId');
  }

  Future<List<Map<String, dynamic>>> positions() async =>
      _list(await _api.dio.get<List<dynamic>>('/positions'));

  Future<Map<String, dynamic>> payrollConfig() async =>
      (await _api.dio
              .get<Map<String, dynamic>>('/businesses/me/payroll-config'))
          .data!;

  Future<Map<String, dynamic>> attendancePolicy() async =>
      (await _api.dio
              .get<Map<String, dynamic>>('/businesses/me/attendance-policy'))
          .data!;

  Future<Map<String, dynamic>> createRegistration({
    required String businessName,
    required String ownerName,
    required String email,
    required String phone,
    required String address,
    required String businessType,
  }) async =>
      (await _api.dio.post<Map<String, dynamic>>(
        '/registrations',
        data: {
          'business_name': businessName,
          'owner_name': ownerName,
          'owner_email': email.trim(),
          if (phone.trim().isNotEmpty) 'owner_phone': phone.trim(),
          'proposed_address': address,
          if (businessType.trim().isNotEmpty) 'business_type': businessType.trim(),
        },
      ))
          .data!;

  Future<Map<String, dynamic>> registrationByEmail(String email) async =>
      (await _api.dio.get<Map<String, dynamic>>(
        '/registrations/by-email/${Uri.encodeComponent(email.trim())}',
      ))
          .data!;

  Future<void> uploadRegistrationDocument(
    String registrationId,
    String documentType,
    XFile file,
  ) async {
    final filename = _registrationFilename(file);
    final bytes = await file.readAsBytes();
    final formData = FormData.fromMap({
      'document_type': documentType,
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
      ),
    });
    await _api.dio.post(
      '/registrations/$registrationId/documents',
      data: formData,
    );
  }

  Future<Map<String, dynamic>> submitRegistration(String registrationId) async =>
      (await _api.dio.post<Map<String, dynamic>>(
        '/registrations/$registrationId/submit',
      ))
          .data!;

  List<Map<String, dynamic>> _list(Response<List<dynamic>> response) =>
      (response.data ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _registrationFilename(XFile file) {
  for (final candidate in [file.name, file.path.split(RegExp(r'[\\/]')).last]) {
    if (candidate.isNotEmpty && candidate.contains('.')) {
      return candidate;
    }
  }
  return 'registration_document_${DateTime.now().millisecondsSinceEpoch}.jpg';
}
