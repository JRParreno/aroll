import 'dart:io';

import 'package:aroll_mobile/core/network/api_client.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/domain/entities/face_liveness.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class EmployeeRepositoryImpl implements EmployeeRepository {
  EmployeeRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<EmployeeDashboard> getDashboard() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/employee/dashboard');
    return _dashboardFromJson(res.data!);
  }

  @override
  Future<EmployeeProfile> getProfile() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/employee/profile');
    return _profileFromJson(res.data!);
  }

  @override
  Future<List<EmployeeScheduleItem>> getSchedule({
    DateTime? startDate,
    DateTime? endDate,
    bool activeOnly = false,
  }) async {
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/employee/schedule',
      queryParameters: {
        if (startDate != null) 'start_date': _apiDate(startDate),
        if (endDate != null) 'end_date': _apiDate(endDate),
        if (activeOnly) 'active_only': true,
      },
    );
    final items = res.data!['items'] as List<dynamic>? ?? [];
    return items
        .map((item) => _scheduleFromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<EmployeeShiftHistoryItem>> getShiftHistory() async {
    final res =
        await _api.dio.get<Map<String, dynamic>>('/employee/shift-history');
    final items = res.data!['items'] as List<dynamic>? ?? [];
    return items
        .map((item) => _historyFromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<AttendanceCorrectionRequest> submitAttendanceCorrection({
    required String shiftAssignmentId,
    DateTime? requestedTimeIn,
    DateTime? requestedTimeOut,
    required String reason,
  }) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/employee/attendance-corrections',
      data: {
        'shift_assignment_id': shiftAssignmentId,
        if (requestedTimeIn != null)
          'requested_time_in': requestedTimeIn.toUtc().toIso8601String(),
        if (requestedTimeOut != null)
          'requested_time_out': requestedTimeOut.toUtc().toIso8601String(),
        'reason': reason,
      },
    );
    return _correctionFromJson(res.data!);
  }

  @override
  Future<List<AttendanceCorrectionRequest>> getAttendanceCorrections() async {
    final res = await _api.dio.get<List<dynamic>>(
      '/employee/attendance-corrections',
    );
    return (res.data ?? [])
        .map((item) => _correctionFromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<EmployeePayroll> getPayroll() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/employee/payroll');
    final rows = res.data!['rows'] as List<dynamic>? ?? [];
    return EmployeePayroll(
      summary: _payslipFromJson(
        res.data!['summary'] as Map<String, dynamic>,
        businessName: res.data!['business_name'] as String? ?? 'Business',
      ),
      rows: rows
          .map((row) => _payrollRowFromJson(row as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<EmployeePayslip> getPayslip() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/employee/payslip');
    return _payslipFromJson(
      res.data!,
      businessName: res.data!['business_name'] as String? ?? 'Business',
    );
  }

  @override
  Future<FaceStatus> getFaceStatus() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/employee/face-status');
    return _faceStatusFromJson(res.data!);
  }

  @override
  Future<FaceStatus> enrollFaceSamples(List<File> images) async {
    final form = FormData();
    for (var i = 0; i < images.length; i++) {
      form.files.add(
        MapEntry(
          'files',
          await MultipartFile.fromFile(
            images[i].path,
            filename: 'sample-${i + 1}.jpg',
          ),
        ),
      );
    }
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/employee/face-samples',
      data: form,
    );
    return _faceStatusFromJson(res.data!);
  }

  @override
  Future<EmployeeProfile> updateProfileImage(String imageData) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/employee/profile/image',
      data: {'image_data': imageData},
    );
    return _profileFromJson(res.data!);
  }

  @override
  Future<EmployeeProfile> removeProfileImage() async {
    final res = await _api.dio.delete<Map<String, dynamic>>(
      '/employee/profile/image',
    );
    return _profileFromJson(res.data!);
  }

  @override
  Future<String> downloadPayslipPdf() async {
    final res = await _api.dio.get<List<int>>(
      '/employee/payslip/pdf',
      options: Options(responseType: ResponseType.bytes),
    );
    final dir = await getTemporaryDirectory();
    final safeDate = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/aroll-payslip-$safeDate.pdf');
    await file.writeAsBytes(res.data ?? const []);
    return file.path;
  }

  @override
  Future<EmployeeWorksite> getWorksite() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/employee/worksite');
    return _worksiteFromJson(res.data!);
  }

  @override
  Future<AttendanceClockResult> clockInWithFace({
    required double latitude,
    required double longitude,
    required FaceQuickCapture capture,
    String? shiftAssignmentId,
  }) async {
    final form = FormData.fromMap({
      'latitude': latitude,
      'longitude': longitude,
      'liveness_gesture': capture.gesture,
      if (shiftAssignmentId != null) 'shift_assignment_id': shiftAssignmentId,
      'file': await MultipartFile.fromFile(
        capture.imagePath,
        filename: 'face.jpg',
      ),
    });
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/employee/attendance/clock-in-face',
      data: form,
    );
    return _clockResultFromJson(res.data!);
  }

  @override
  Future<AttendanceClockResult> clockOutWithFace({
    required double latitude,
    required double longitude,
    required FaceQuickCapture capture,
  }) async {
    final form = FormData.fromMap({
      'latitude': latitude,
      'longitude': longitude,
      'liveness_gesture': capture.gesture,
      'file': await MultipartFile.fromFile(
        capture.imagePath,
        filename: 'face.jpg',
      ),
    });
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/employee/attendance/clock-out-face',
      data: form,
    );
    return _clockResultFromJson(res.data!);
  }
}

FaceStatus _faceStatusFromJson(Map<String, dynamic> json) {
  return FaceStatus(
    employeeId: json['employee_id'] as String? ?? '',
    faceRegistrationStatus:
        json['face_registration_status'] as String? ?? 'not_registered',
    sampleCount: (json['sample_count'] as num?)?.toInt() ?? 0,
    modelVersion: json['model_version'] as String?,
    faceRegisteredAt: json['face_registered_at'] != null
        ? DateTime.tryParse(json['face_registered_at'] as String)
        : null,
    threshold: (json['threshold'] as num?)?.toDouble() ?? 0.78,
  );
}

EmployeeDashboard _dashboardFromJson(Map<String, dynamic> json) {
  final schedules = json['upcoming_schedules'] as List<dynamic>? ?? [];
  return EmployeeDashboard(
    profile: _profileFromJson(json['profile'] as Map<String, dynamic>),
    todaySchedule: json['today_schedule'] is Map<String, dynamic>
        ? _scheduleFromJson(json['today_schedule'] as Map<String, dynamic>)
        : null,
    upcomingSchedules: schedules
        .map((item) => _scheduleFromJson(item as Map<String, dynamic>))
        .toList(),
    attendanceStatus: _attendanceStatusFromJson(
      json['attendance_status'] as Map<String, dynamic>? ?? {},
    ),
    payrollSummary: _payslipFromJson(
      json['payroll_summary'] as Map<String, dynamic>,
      businessName:
          (json['profile'] as Map<String, dynamic>)['business_name'] as String? ??
              'Business',
    ),
    performance:
        _performanceFromJson(json['performance'] as Map<String, dynamic>),
  );
}

EmployeeAttendanceStatus _attendanceStatusFromJson(Map<String, dynamic> json) {
  return EmployeeAttendanceStatus(
    status: json['status'] as String? ?? 'not_started',
    timeIn: _dateTime(json['time_in'] as String?),
    timeOut: _dateTime(json['time_out'] as String?),
  );
}

EmployeeProfile _profileFromJson(Map<String, dynamic> json) {
  return EmployeeProfile(
    employeeId: json['employee_id'] as String,
    businessId: json['business_id'] as String,
    fullName: json['full_name'] as String? ?? 'Employee',
    username: json['username'] as String?,
    position: json['position'] as String?,
    employmentType: json['employment_type'] as String? ?? 'full_time',
    phone: json['phone'] as String?,
    profileImageUrl: json['profile_image_url'] as String?,
    hireDate: _date(json['hire_date'] as String?),
    status: json['status'] as String? ?? 'active',
    businessName: json['business_name'] as String? ?? 'Business',
    businessCode: json['business_code'] as String? ?? '',
    businessType: json['business_type'] as String?,
    ownerName: json['owner_name'] as String?,
    faceRegistrationStatus:
        json['face_registration_status'] as String? ?? 'not_registered',
    branding: _brandingFromJson(json),
  );
}

EmployeeScheduleItem _scheduleFromJson(Map<String, dynamic> json) {
  final coworkers = json['coworkers'] as List<dynamic>? ?? [];
  return EmployeeScheduleItem(
    assignmentId: json['assignment_id'] as String,
    shiftId: json['shift_id'] as String,
    shiftName: json['shift_name'] as String? ?? 'Shift',
    workDate: _requiredDate(json['work_date'] as String?),
    startTime: json['start_time'] as String? ?? '',
    endTime: json['end_time'] as String? ?? '',
    startLabel: json['start_label'] as String? ?? '',
    endLabel: json['end_label'] as String? ?? '',
    status: json['status'] as String? ?? 'upcoming',
    locationLabel: json['location_label'] as String?,
    locationAddress: json['location_address'] as String?,
    holidayName: json['holiday_name'] as String?,
    notes: json['notes'] as String?,
    coworkers: coworkers
        .map((coworker) => _coworkerFromJson(coworker as Map<String, dynamic>))
        .toList(),
  );
}

EmployeeCoworker _coworkerFromJson(Map<String, dynamic> json) {
  return EmployeeCoworker(
    employeeId: json['employee_id'] as String,
    fullName: json['full_name'] as String? ?? 'Employee',
    profileImageUrl: json['profile_image_url'] as String?,
    isCurrentEmployee: json['is_current_employee'] as bool? ?? false,
  );
}

EmployeePerformanceSummary _performanceFromJson(Map<String, dynamic> json) {
  return EmployeePerformanceSummary(
    hasData: json['has_data'] as bool? ?? false,
    onTime: _int(json['on_time']),
    late: _int(json['late']),
    undertime: _int(json['undertime']),
    overtime: _int(json['overtime']),
    absent: _int(json['absent']),
  );
}

EmployeeShiftHistoryItem _historyFromJson(Map<String, dynamic> json) {
  return EmployeeShiftHistoryItem(
    id: json['id'] as String,
    assignmentId: json['assignment_id'] as String? ?? json['id'] as String,
    attendanceRecordId: json['attendance_record_id'] as String?,
    date: _requiredDate(json['date'] as String?),
    shiftName: json['shift_name'] as String?,
    shiftStart: json['shift_start'] as String?,
    shiftEnd: json['shift_end'] as String?,
    timeIn: _dateTime(json['time_in'] as String?),
    timeOut: _dateTime(json['time_out'] as String?),
    status: json['status'] as String? ?? 'in_progress',
    overtimeMinutes: _double(json['overtime_minutes']),
    holidayName: json['holiday_name'] as String?,
    canRequestCorrection: json['can_request_correction'] as bool? ?? false,
    correctionStatus: json['correction_status'] as String?,
    correctionId: json['correction_id'] as String?,
    correctionReviewNote: json['correction_review_note'] as String?,
  );
}

AttendanceCorrectionRequest _correctionFromJson(Map<String, dynamic> json) {
  return AttendanceCorrectionRequest(
    id: json['id'] as String,
    assignmentId: json['shift_assignment_id'] as String,
    workDate: _requiredDate(json['work_date'] as String?),
    shiftName: json['shift_name'] as String?,
    reason: json['reason'] as String? ?? '',
    status: json['status'] as String? ?? 'pending',
    requestedTimeIn: _dateTime(json['requested_time_in'] as String?),
    requestedTimeOut: _dateTime(json['requested_time_out'] as String?),
    reviewNote: json['review_note'] as String?,
    createdAt: _dateTime(json['created_at'] as String?) ?? DateTime.now(),
  );
}

EmployeePayrollRow _payrollRowFromJson(Map<String, dynamic> json) {
  return EmployeePayrollRow(
    date: _requiredDate(json['date'] as String?),
    status: json['status'] as String? ?? 'complete',
    dailyRate: _double(json['daily_rate']),
    earned: _double(json['earned']),
    holidayName: json['holiday_name'] as String?,
  );
}

EmployeePayslip _payslipFromJson(
  Map<String, dynamic> json, {
  required String businessName,
}) {
  final restDayRows = json['rest_day_records'] as List<dynamic>? ?? const [];
  return EmployeePayslip(
    businessName: businessName,
    employeeId: json['employee_id'] as String,
    employeeName: json['employee_name'] as String? ?? 'Employee',
    positionTitle: json['position_title'] as String?,
    employmentType: json['employment_type'] as String? ?? 'full_time',
    periodStart: _requiredDate(json['period_start'] as String?),
    periodEnd: _requiredDate(json['period_end'] as String?),
    dailyRate: _double(json['daily_rate']),
    workedDays: _int(json['worked_days']),
    overtimeHours: _double(json['overtime_hours']),
    overtimePay: _double(json['overtime_pay']),
    holidayPay: _double(json['holiday_pay']),
    restDayPay: _double(json['rest_day_pay']),
    restDayDays: _int(json['rest_day_days']),
    restDayPremiumPercent: _double(json['rest_day_premium_percent']),
    restDayName: json['rest_day_name'] as String?,
    restDayRecords: restDayRows
        .whereType<Map<String, dynamic>>()
        .map(_restDayRecordFromJson)
        .toList(),
    deductions: _double(json['deductions']),
    absentDays: _int(json['absent_days']),
    grossPay: _double(json['gross_pay']),
    netPay: _double(json['net_pay']),
  );
}

EmployeeRestDayRecord _restDayRecordFromJson(Map<String, dynamic> json) {
  return EmployeeRestDayRecord(
    date: _requiredDate(json['date'] as String?),
    weekday: json['weekday'] as String? ?? '',
    status: json['status'] as String? ?? '',
    timeIn: _dateTime(json['time_in'] as String?),
    timeOut: _dateTime(json['time_out'] as String?),
    shiftName: json['shift_name'] as String?,
    premiumPercent: _double(json['premium_percent']),
    premiumPay: _double(json['premium_pay']),
  );
}

BusinessBrandingSettings? _brandingFromJson(Map<String, dynamic> data) {
  final branding = data['branding'];
  if (branding is! Map<String, dynamic>) return null;
  final theme = branding['theme'];
  final themeMap = theme is Map<String, dynamic> ? theme : <String, dynamic>{};
  return BusinessBrandingSettings(
    logoUrl: branding['logo_url'] as String?,
    ownerProfileImageUrl: branding['owner_profile_image_url'] as String?,
    displayImageUrl: branding['display_image_url'] as String?,
    theme: BusinessThemeSettings(
      primaryColor: (themeMap['primary_color'] as String?) ?? '#1E3A5F',
      secondaryColor: (themeMap['secondary_color'] as String?) ?? '#284B73',
      sidebarColor: (themeMap['sidebar_color'] as String?) ?? '#1E3A5F',
      accentColor: (themeMap['accent_color'] as String?) ?? '#3B82F6',
      buttonColor: (themeMap['button_color'] as String?) ?? '#1E3A5F',
      cardStyle: (themeMap['card_style'] as String?) ?? 'soft',
      fontSize: (themeMap['font_size'] as String?) ?? 'comfortable',
      colorMode: (themeMap['color_mode'] as String?) ?? 'light',
      layoutDensity: (themeMap['layout_density'] as String?) ?? 'rounded',
    ),
  );
}

DateTime? _date(String? value) => value == null ? null : DateTime.tryParse(value);

DateTime _requiredDate(String? value) => _date(value) ?? DateTime.now();

String _apiDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

DateTime? _dateTime(String? value) {
  if (value == null) return null;
  return DateTime.tryParse(value)?.toLocal();
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

double _double(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

EmployeeWorksite _worksiteFromJson(Map<String, dynamic> json) {
  return EmployeeWorksite(
    label: json['label'] as String? ?? 'Work site',
    address: json['address'] as String? ?? '',
    latitude: _double(json['latitude']),
    longitude: _double(json['longitude']),
    geofenceRadiusM: _int(json['geofence_radius_m']),
  );
}

AttendanceClockResult _clockResultFromJson(Map<String, dynamic> json) {
  final geofence = json['geofence'] as Map<String, dynamic>? ?? {};
  return AttendanceClockResult(
    id: json['id'] as String,
    status: json['status'] as String? ?? 'in_progress',
    timeIn: _dateTime(json['time_in'] as String?),
    timeOut: _dateTime(json['time_out'] as String?),
    insideGeofence: geofence['inside_geofence'] as bool? ?? false,
    distanceM: _double(geofence['distance_m']),
    allowedRadiusM: _double(geofence['allowed_radius_m']),
    shiftName: json['shift_name'] as String?,
    message: json['message'] as String? ?? 'Attendance recorded.',
  );
}
