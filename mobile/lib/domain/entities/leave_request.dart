import 'package:equatable/equatable.dart';

class LeaveRequestPreviousVersion extends Equatable {
  const LeaveRequestPreviousVersion({
    required this.leaveType,
    required this.leaveTypeLabel,
    required this.startDate,
    required this.endDate,
    required this.leaveDays,
    required this.reason,
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
  ('unpaid', 'Unpaid Leave'),
  ('other', 'Other'),
];
