import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:equatable/equatable.dart';

class EmployeeProfile extends Equatable {
  const EmployeeProfile({
    required this.employeeId,
    required this.businessId,
    required this.fullName,
    required this.username,
    required this.position,
    required this.employmentType,
    required this.phone,
    required this.profileImageUrl,
    required this.hireDate,
    required this.status,
    required this.businessName,
    required this.businessCode,
    required this.businessType,
    required this.ownerName,
    required this.faceRegistrationStatus,
    required this.branding,
  });

  final String employeeId;
  final String businessId;
  final String fullName;
  final String? username;
  final String? position;
  final String employmentType;
  final String? phone;
  final String? profileImageUrl;
  final DateTime? hireDate;
  final String status;
  final String businessName;
  final String businessCode;
  final String? businessType;
  final String? ownerName;
  final String faceRegistrationStatus;
  final BusinessBrandingSettings? branding;

  bool get faceRegistered => faceRegistrationStatus == 'completed';

  @override
  List<Object?> get props => [
        employeeId,
        businessId,
        fullName,
        username,
        position,
        employmentType,
        phone,
        profileImageUrl,
        hireDate,
        status,
        businessName,
        businessCode,
        businessType,
        ownerName,
        faceRegistrationStatus,
        branding,
      ];
}

class EmployeeScheduleItem extends Equatable {
  const EmployeeScheduleItem({
    required this.assignmentId,
    required this.shiftId,
    required this.shiftName,
    required this.workDate,
    required this.startTime,
    required this.endTime,
    required this.startLabel,
    required this.endLabel,
    required this.status,
    required this.locationLabel,
    required this.locationAddress,
    required this.holidayName,
    required this.notes,
    required this.coworkers,
  });

  final String assignmentId;
  final String shiftId;
  final String shiftName;
  final DateTime workDate;
  final String startTime;
  final String endTime;
  final String startLabel;
  final String endLabel;
  final String status;
  final String? locationLabel;
  final String? locationAddress;
  final String? holidayName;
  final String? notes;
  final List<EmployeeCoworker> coworkers;

  @override
  List<Object?> get props => [
        assignmentId,
        shiftId,
        shiftName,
        workDate,
        startTime,
        endTime,
        startLabel,
        endLabel,
        status,
        locationLabel,
        locationAddress,
        holidayName,
        notes,
        coworkers,
      ];
}

class EmployeeCoworker extends Equatable {
  const EmployeeCoworker({
    required this.employeeId,
    required this.fullName,
    required this.profileImageUrl,
    required this.isCurrentEmployee,
  });

  final String employeeId;
  final String fullName;
  final String? profileImageUrl;
  final bool isCurrentEmployee;

  @override
  List<Object?> get props => [
        employeeId,
        fullName,
        profileImageUrl,
        isCurrentEmployee,
      ];
}

class EmployeePerformanceSummary extends Equatable {
  const EmployeePerformanceSummary({
    required this.hasData,
    required this.onTime,
    required this.late,
    required this.undertime,
    required this.overtime,
    required this.absent,
  });

  final bool hasData;
  final int onTime;
  final int late;
  final int undertime;
  final int overtime;
  final int absent;

  @override
  List<Object?> get props => [hasData, onTime, late, undertime, overtime, absent];
}

class EmployeePayslip extends Equatable {
  const EmployeePayslip({
    required this.businessName,
    required this.employeeId,
    required this.employeeName,
    required this.positionTitle,
    required this.employmentType,
    required this.periodStart,
    required this.periodEnd,
    required this.dailyRate,
    required this.workedDays,
    required this.overtimeHours,
    required this.overtimePay,
    required this.holidayPay,
    required this.deductions,
    required this.absentDays,
    required this.grossPay,
    required this.netPay,
  });

  final String businessName;
  final String employeeId;
  final String employeeName;
  final String? positionTitle;
  final String employmentType;
  final DateTime periodStart;
  final DateTime periodEnd;
  final double dailyRate;
  final int workedDays;
  final double overtimeHours;
  final double overtimePay;
  final double holidayPay;
  final double deductions;
  final int absentDays;
  final double grossPay;
  final double netPay;

  @override
  List<Object?> get props => [
        businessName,
        employeeId,
        employeeName,
        positionTitle,
        employmentType,
        periodStart,
        periodEnd,
        dailyRate,
        workedDays,
        overtimeHours,
        overtimePay,
        holidayPay,
        deductions,
        absentDays,
        grossPay,
        netPay,
      ];
}

class EmployeePayrollRow extends Equatable {
  const EmployeePayrollRow({
    required this.date,
    required this.status,
    required this.dailyRate,
    required this.earned,
    required this.holidayName,
  });

  final DateTime date;
  final String status;
  final double dailyRate;
  final double earned;
  final String? holidayName;

  @override
  List<Object?> get props => [date, status, dailyRate, earned, holidayName];
}

class EmployeePayroll extends Equatable {
  const EmployeePayroll({
    required this.summary,
    required this.rows,
  });

  final EmployeePayslip summary;
  final List<EmployeePayrollRow> rows;

  @override
  List<Object?> get props => [summary, rows];
}

class EmployeeWorksite extends Equatable {
  const EmployeeWorksite({
    required this.label,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.geofenceRadiusM,
  });

  final String label;
  final String address;
  final double latitude;
  final double longitude;
  final int geofenceRadiusM;

  @override
  List<Object?> get props => [
        label,
        address,
        latitude,
        longitude,
        geofenceRadiusM,
      ];
}

class AttendanceClockResult extends Equatable {
  const AttendanceClockResult({
    required this.id,
    required this.status,
    required this.timeIn,
    required this.timeOut,
    required this.insideGeofence,
    required this.distanceM,
    required this.allowedRadiusM,
    required this.shiftName,
    required this.message,
  });

  final String id;
  final String status;
  final DateTime? timeIn;
  final DateTime? timeOut;
  final bool insideGeofence;
  final double distanceM;
  final double allowedRadiusM;
  final String? shiftName;
  final String message;

  @override
  List<Object?> get props => [
        id,
        status,
        timeIn,
        timeOut,
        insideGeofence,
        distanceM,
        allowedRadiusM,
        shiftName,
        message,
      ];
}

class EmployeeAttendanceStatus extends Equatable {
  const EmployeeAttendanceStatus({
    required this.status,
    required this.timeIn,
    required this.timeOut,
  });

  final String status;
  final DateTime? timeIn;
  final DateTime? timeOut;

  @override
  List<Object?> get props => [status, timeIn, timeOut];
}

class EmployeeShiftHistoryItem extends Equatable {
  const EmployeeShiftHistoryItem({
    required this.id,
    required this.date,
    required this.shiftName,
    required this.shiftStart,
    required this.shiftEnd,
    required this.timeIn,
    required this.timeOut,
    required this.status,
    required this.overtimeMinutes,
    required this.holidayName,
  });

  final String id;
  final DateTime date;
  final String? shiftName;
  final String? shiftStart;
  final String? shiftEnd;
  final DateTime? timeIn;
  final DateTime? timeOut;
  final String status;
  final double overtimeMinutes;
  final String? holidayName;

  @override
  List<Object?> get props => [
        id,
        date,
        shiftName,
        shiftStart,
        shiftEnd,
        timeIn,
        timeOut,
        status,
        overtimeMinutes,
        holidayName,
      ];
}

class EmployeeDashboard extends Equatable {
  const EmployeeDashboard({
    required this.profile,
    required this.todaySchedule,
    required this.upcomingSchedules,
    required this.attendanceStatus,
    required this.payrollSummary,
    required this.performance,
  });

  final EmployeeProfile profile;
  final EmployeeScheduleItem? todaySchedule;
  final List<EmployeeScheduleItem> upcomingSchedules;
  final EmployeeAttendanceStatus attendanceStatus;
  final EmployeePayslip payrollSummary;
  final EmployeePerformanceSummary performance;

  @override
  List<Object?> get props => [
        profile,
        todaySchedule,
        upcomingSchedules,
        attendanceStatus,
        payrollSummary,
        performance,
      ];
}
