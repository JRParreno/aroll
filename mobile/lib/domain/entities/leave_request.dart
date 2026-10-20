import 'package:equatable/equatable.dart';

class LeaveRequestPreviousVersion extends Equatable {
  const LeaveRequestPreviousVersion({
    required this.leaveType,
    required this.leaveTypeLabel,
    required this.startDate,
    required this.endDate,
    required this.leaveDays,
    required this.reason,
    this.otherLeaveSpecification,
    required this.hasSupportingDocument,
    this.supportingDocument,
    required this.isPaid,
  });

  final String leaveType;
  final String leaveTypeLabel;
  final DateTime startDate;
  final DateTime endDate;
  final int leaveDays;
  final String reason;
  final String? otherLeaveSpecification;
  final bool hasSupportingDocument;
  final String? supportingDocument;
  final bool isPaid;

  @override
  List<Object?> get props => [leaveType, startDate, endDate, leaveDays];
}

class LeaveRequestItem extends Equatable {
  const LeaveRequestItem({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.employeePosition,
    required this.leaveType,
    required this.leaveTypeLabel,
    required this.startDate,
    required this.endDate,
    required this.leaveDays,
    required this.reason,
    this.otherLeaveSpecification,
    required this.status,
    required this.isPaid,
    this.policyIsPaid,
    this.isPaidOverridden = false,
    required this.hasSupportingDocument,
    this.supportingDocument,
    this.ownerRemarks,
    this.reviewedAt,
    required this.createdAt,
    this.hasPendingChanges = false,
    this.previousRequest,
  });

  final String id;
  final String employeeId;
  final String? employeeName;
  final String? employeePosition;
  final String leaveType;
  final String leaveTypeLabel;
  final DateTime startDate;
  final DateTime endDate;
  final int leaveDays;
  final String reason;
  final String? otherLeaveSpecification;
  final String status;
  final bool isPaid;
  final bool? policyIsPaid;
  final bool isPaidOverridden;
  final bool hasSupportingDocument;
  final String? supportingDocument;
  final String? ownerRemarks;
  final DateTime? reviewedAt;
  final DateTime createdAt;
  final bool hasPendingChanges;
  final LeaveRequestPreviousVersion? previousRequest;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isCancellationPending => status == 'cancellation_pending';
  bool get isCancelled => status == 'cancelled';

  bool get canEdit => isPending || isApproved;
  bool get canCancel => isPending || isApproved;

  String get statusLabel => switch (status) {
        'approved' => 'Approved',
        'rejected' => 'Rejected',
        'cancellation_pending' => 'Cancellation Pending',
        'cancelled' => 'Cancelled',
        _ => 'Pending Approval',
      };

  @override
  List<Object?> get props => [id, status, leaveType, startDate, endDate];
}

const leaveTypeOptions = <(String value, String label)>[
  ('sick', 'Sick Leave'),
  ('vacation', 'Vacation Leave'),
  ('emergency', 'Emergency Leave'),
  ('maternity', 'Maternity Leave'),
  ('paternity', 'Paternity Leave'),
  ('other', 'Other'),
];

class LeaveBalanceItem {
  const LeaveBalanceItem({
    required this.leaveType,
    required this.leaveTypeLabel,
    required this.allocatedDays,
    required this.usedDays,
    required this.remainingDays,
    required this.configured,
    this.enabled = false,
    this.disabled = false,
    this.scheduledDays,
    this.sufficient,
    this.year,
  });

  final String leaveType;
  final String leaveTypeLabel;
  final int? allocatedDays;
  final int usedDays;
  final int? remainingDays;
  final bool configured;
  final bool enabled;
  final bool disabled;
  final int? scheduledDays;
  final bool? sufficient;
  final int? year;

  factory LeaveBalanceItem.fromJson(Map<String, dynamic> json) {
    return LeaveBalanceItem(
      leaveType: '${json['leave_type']}',
      leaveTypeLabel: '${json['leave_type_label'] ?? json['leave_type']}',
      allocatedDays: json['allocated_days'] as int?,
      usedDays: json['used_days'] as int? ?? 0,
      remainingDays: json['remaining_days'] as int?,
      configured: json['configured'] == true,
      enabled: json['enabled'] == true || json['configured'] == true,
      disabled: json['disabled'] == true,
      scheduledDays: json['scheduled_days'] as int?,
      sufficient: json['sufficient'] as bool?,
      year: json['year'] as int?,
    );
  }
}

class LeaveBalance {
  const LeaveBalance({required this.year, required this.items});

  final int year;
  final List<LeaveBalanceItem> items;

  factory LeaveBalance.fromJson(Map<String, dynamic> json) {
    final raw = json['items'] as List? ?? const [];
    return LeaveBalance(
      year: json['year'] as int? ?? DateTime.now().year,
      items: raw
          .whereType<Map>()
          .map((item) => LeaveBalanceItem.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }
}

class LeaveRequestPreview {
  const LeaveRequestPreview({
    required this.calendarDays,
    required this.scheduledDays,
    required this.balanceSufficient,
    required this.advanceNoticeMet,
    required this.minimumAdvanceNoticeDays,
    required this.earliestStartDate,
    required this.years,
  });

  final int calendarDays;
  final int scheduledDays;
  final bool balanceSufficient;
  final bool advanceNoticeMet;
  final int minimumAdvanceNoticeDays;
  final String? earliestStartDate;
  final List<LeaveBalanceItem> years;

  factory LeaveRequestPreview.fromJson(Map<String, dynamic> json) {
    final raw = json['years'] as List? ?? const [];
    return LeaveRequestPreview(
      calendarDays: json['calendar_days'] as int? ?? 0,
      scheduledDays: json['scheduled_days'] as int? ?? 0,
      balanceSufficient: json['balance_sufficient'] == true,
      advanceNoticeMet: json['advance_notice_met'] != false,
      minimumAdvanceNoticeDays: json['minimum_advance_notice_days'] as int? ?? 0,
      earliestStartDate: json['earliest_start_date'] as String?,
      years: raw
          .whereType<Map>()
          .map((item) => LeaveBalanceItem.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }
}
