import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/theme/business_brand_theme.dart';
import 'package:aroll_mobile/domain/entities/leave_request.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:aroll_mobile/presentation/shared/supporting_document_viewer.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class LeaveRequestDetailScreen extends StatefulWidget {
  const LeaveRequestDetailScreen({super.key, required this.requestId});

  final String requestId;

  @override
  State<LeaveRequestDetailScreen> createState() =>
      _LeaveRequestDetailScreenState();
}

class _LeaveRequestDetailScreenState extends State<LeaveRequestDetailScreen> {
  final _repo = sl<EmployeeRepository>();
  late Future<LeaveRequestItem> _future;
  bool _actionInProgress = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _repo.getLeaveRequest(widget.requestId);
    setState(() {});
  }

  Future<void> _openEdit(LeaveRequestItem item) async {
    final updated =
        await context.push<bool>('/leave-requests/${item.id}/edit');
    if (updated == true && mounted) _reload();
  }

  Future<void> _confirmCancel(LeaveRequestItem item) async {
    final isApproved = item.isApproved;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isApproved ? 'Request cancellation?' : 'Cancel leave request?'),
        content: Text(
          isApproved
              ? 'Your owner must approve this cancellation before the leave is removed from your schedule.'
              : 'This will withdraw your pending leave request. You can submit a new request later if needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep request'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: isApproved
                  ? const Color(0xFF7C3AED)
                  : const Color(0xFFDC2626),
            ),
            child: Text(isApproved ? 'Request cancellation' : 'Cancel request'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _actionInProgress = true);
    try {
      await _repo.cancelLeaveRequest(item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isApproved
                ? 'Cancellation request sent to your owner.'
                : 'Leave request cancelled.',
          ),
        ),
      );
      _reload();
    } on DioException catch (error) {
      if (!mounted) return;
      final detail = error.response?.data is Map
          ? (error.response?.data as Map)['detail']
          : null;
      final message = detail is String
          ? detail
          : 'Could not cancel leave request.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  String _statusMessage(LeaveRequestItem item) {
    if (item.isApproved) {
      return item.hasPendingChanges
          ? 'Updated details are waiting for owner approval.'
          : 'This leave request was approved.';
    }
    if (item.isRejected) return 'This leave request was rejected.';
    if (item.isCancellationPending) {
      return 'Waiting for your owner to approve the cancellation.';
    }
    if (item.isCancelled) return 'This leave request was cancelled.';
    return 'Waiting for owner approval.';
  }

  IconData _statusIcon(LeaveRequestItem item) {
    if (item.isApproved) return Icons.check_circle_outline_rounded;
    if (item.isRejected) return Icons.cancel_outlined;
    if (item.isCancellationPending) return Icons.hourglass_disabled_rounded;
    if (item.isCancelled) return Icons.block_rounded;
    return Icons.hourglass_top_rounded;
  }

  Color _statusColor(String status) => switch (status) {
        'approved' => const Color(0xFF15803D),
        'rejected' => const Color(0xFFDC2626),
        'cancellation_pending' => const Color(0xFF7C3AED),
        'cancelled' => const Color(0xFF64748B),
        _ => const Color(0xFFB45309),
      };

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat.yMMMd();
    final brand = BrandColors.of(context);
    final soft = Color.lerp(brand.primary, Colors.white, 0.18) ?? brand.primary;
    return Scaffold(
      backgroundColor: EmployeeColors.scaffold,
      appBar: AppBar(
        title: const Text('Leave Request'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
      ),
      body: FutureBuilder<LeaveRequestItem>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: brand.primary),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: Text(
                'Leave request not found.',
                style: TextStyle(color: EmployeeColors.textMuted),
              ),
            );
          }
          final item = snapshot.data!;
          final statusColor = _statusColor(item.status);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [soft, brand.primary],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: brand.primary.withValues(alpha: 0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.beach_access_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.leaveTypeLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${item.leaveDays} day${item.leaveDays == 1 ? '' : 's'} · ${item.isPaid ? 'Paid' : 'Unpaid'}',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.82),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.28),
                        ),
                      ),
                      child: Text(
                        item.statusLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (item.hasPendingChanges && item.previousRequest != null) ...[
                const SizedBox(height: 14),
                _PreviousRequestCard(
                  previous: item.previousRequest!,
                  dateFmt: dateFmt,
                  accent: brand.primary,
                ),
              ],
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: EmployeeColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _DetailRow(
                      icon: Icons.calendar_month_outlined,
                      label: 'Requested dates',
                      value:
                          '${dateFmt.format(item.startDate)} – ${dateFmt.format(item.endDate)}',
                      accent: brand.primary,
                    ),
                    _DetailRow(
                      icon: Icons.schedule_rounded,
                      label: 'Leave days',
                      value:
                          '${item.leaveDays} day${item.leaveDays == 1 ? '' : 's'}',
                      accent: brand.primary,
                    ),
                    _DetailRow(
                      icon: item.isPaid
                          ? Icons.payments_outlined
                          : Icons.money_off_csred_outlined,
                      label: 'Company Policy',
                      value: item.isPaid ? 'Paid Leave' : 'Unpaid Leave',
                      accent: brand.primary,
                      trailing: item.isPaid ? 'Paid' : 'Unpaid',
                      trailingColor: item.isPaid
                          ? const Color(0xFF15803D)
                          : const Color(0xFFB45309),
                    ),
                    _DetailRow(
                      icon: Icons.notes_rounded,
                      label: 'Reason',
                      value: item.reason,
                      accent: brand.primary,
                    ),
                    _DetailRow(
                      icon: Icons.attach_file_rounded,
                      label: 'Supporting document',
                      value: item.hasSupportingDocument ? 'Attached' : 'None',
                      accent: brand.primary,
                      showDivider: false,
                    ),
                    if (item.hasSupportingDocument &&
                        item.supportingDocument != null &&
                        item.supportingDocument!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => viewSupportingDocument(
                              context,
                              documentDataUrl: item.supportingDocument,
                            ),
                            icon: const Icon(Icons.visibility_outlined),
                            label: const Text('View document'),
                            style: TextButton.styleFrom(
                              foregroundColor: brand.primary,
                            ),
                          ),
                        ),
                      ),
                    if (item.ownerRemarks != null &&
                        item.ownerRemarks!.trim().isNotEmpty)
                      _DetailRow(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'Owner remarks',
                        value: item.ownerRemarks!,
                        accent: brand.primary,
                        showDivider: false,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: statusColor.withValues(alpha: 0.18)),
                ),
                child: Row(
                  children: [
                    Icon(
                      _statusIcon(item),
                      color: statusColor,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _statusMessage(item),
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (item.canEdit || item.canCancel) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    if (item.canEdit)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _actionInProgress
                              ? null
                              : () => _openEdit(item),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: brand.primary,
                            side: BorderSide(color: brand.primary),
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text(
                            'Edit',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    if (item.canEdit && item.canCancel)
                      const SizedBox(width: 10),
                    if (item.canCancel)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _actionInProgress
                              ? null
                              : () => _confirmCancel(item),
                          style: FilledButton.styleFrom(
                            backgroundColor: item.isApproved
                                ? const Color(0xFF7C3AED)
                                : const Color(0xFFDC2626),
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: Icon(
                            item.isApproved
                                ? Icons.event_busy_outlined
                                : Icons.close_rounded,
                            size: 18,
                          ),
                          label: Text(
                            item.isApproved ? 'Request cancel' : 'Cancel',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PreviousRequestCard extends StatelessWidget {
  const _PreviousRequestCard({
    required this.previous,
    required this.dateFmt,
    required this.accent,
  });

  final LeaveRequestPreviousVersion previous;
  final DateFormat dateFmt;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded, size: 18, color: accent),
              const SizedBox(width: 8),
              Text(
                'Previous version',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            previous.leaveTypeLabel,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: EmployeeColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${dateFmt.format(previous.startDate)} – ${dateFmt.format(previous.endDate)} · ${previous.leaveDays} day${previous.leaveDays == 1 ? '' : 's'}',
            style: const TextStyle(
              fontSize: 12,
              color: EmployeeColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (previous.reason.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              previous.reason,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7280),
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    this.trailing,
    this.trailingColor,
    this.showDivider = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  final String? trailing;
  final Color? trailingColor;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null)
                Container(
                  margin: const EdgeInsets.only(left: 8, top: 2),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (trailingColor ?? accent).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    trailing!,
                    style: TextStyle(
                      color: trailingColor ?? accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (showDivider) const Divider(height: 1, color: Color(0xFFF1F5F9)),
        if (showDivider) const SizedBox(height: 12),
      ],
    );
  }
}
