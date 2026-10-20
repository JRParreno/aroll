import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/theme/business_brand_theme.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:aroll_mobile/presentation/shared/supporting_document_viewer.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

Color _leaveNavy(BuildContext context) {
  final brand = BrandColors.of(context);
  return brand.saved ? brand.tonePrimary : const Color(0xFF1F456B);
}

Color _leaveSoft(BuildContext context) {
  final brand = BrandColors.of(context);
  return brand.saved ? brand.toneSecondary : const Color(0xFF3B6D96);
}

Color _leaveWell(BuildContext context) {
  final brand = BrandColors.of(context);
  return brand.saved ? brand.toneWell : const Color(0xFFEFF4F9);
}

class OwnerLeaveManagementScreen extends StatefulWidget {
  const OwnerLeaveManagementScreen({super.key});

  @override
  State<OwnerLeaveManagementScreen> createState() =>
      _OwnerLeaveManagementScreenState();
}

class _OwnerLeaveManagementScreenState extends State<OwnerLeaveManagementScreen>
    with SingleTickerProviderStateMixin {
  final _repo = sl<OwnerRepository>();
  late final TabController _tabs;
  Future<List<Map<String, dynamic>>>? _future;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) _reload();
    });
    _future = _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String get _statusKey {
    switch (_tabs.index) {
      case 1:
        return 'cancellation_pending';
      case 2:
        return 'approved';
      case 3:
        return 'rejected';
      case 4:
        return 'all';
      default:
        return 'pending';
    }
  }

  Future<List<Map<String, dynamic>>> _load() async {
    if (_tabs.index == 0) {
      final results = await Future.wait([
        _repo.leaveRequests(status: 'pending'),
        _repo.leaveRequests(status: 'cancellation_pending'),
      ]);
      final merged = [
        ...results[0],
        ...results[1],
      ];
      merged.sort((a, b) {
        final aDate =
            DateTime.tryParse('${a['created_at']}') ?? DateTime(1970);
        final bDate =
            DateTime.tryParse('${b['created_at']}') ?? DateTime(1970);
        return bDate.compareTo(aDate);
      });
      return merged;
    }
    return _repo.leaveRequests(status: _statusKey);
  }

  Future<void> _reload() async {
    final next = _load();
    setState(() {
      _future = next;
    });
    try {
      await next;
    } catch (_) {
      // FutureBuilder shows the error state.
    }
  }

  @override
  Widget build(BuildContext context) {
    return OwnerShell(
      selectedIndex: 0,
      showBackButton: true,
      title: 'Leave Management',
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: _leaveNavy(context),
              unselectedLabelColor: const Color(0xFF64748B),
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13.5,
              ),
              indicatorColor: _leaveNavy(context),
              indicatorWeight: 2,
              dividerColor: const Color(0xFFE5E7EB),
              labelPadding: const EdgeInsets.symmetric(horizontal: 14),
              tabs: const [
                Tab(text: 'Pending'),
                Tab(text: 'Cancel Pending'),
                Tab(text: 'Approved'),
                Tab(text: 'Rejected'),
                Tab(text: 'History'),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _EmptyState(
                    icon: Icons.wifi_off_rounded,
                    title: 'Could not load requests',
                    subtitle: 'Check your connection and try again.',
                    actionLabel: 'Retry',
                    onAction: _reload,
                  );
                }
                final items = snapshot.data ?? const [];
                if (items.isEmpty) {
                  return _EmptyState(
                    icon: Icons.event_available_outlined,
                    title: _emptyTitle(_statusKey),
                    subtitle: _emptySubtitle(_statusKey),
                  );
                }
                final dateFmt = DateFormat.MMMd();
                return RefreshIndicator(
                  color: _leaveNavy(context),
                  onRefresh: _reload,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final start = DateTime.tryParse('${item['start_date']}');
                      final end = DateTime.tryParse('${item['end_date']}');
                      final status = '${item['status']}';
                      final name = '${item['employee_name'] ?? 'Employee'}';
                      final profileImage =
                          item['employee_profile_image_url'] as String?;
                      final leaveType =
                          '${item['leave_type_label'] ?? item['leave_type']}';
                      final days = item['leave_days'];
                      final paid = item['is_paid'] == true;
                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        elevation: 0,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () async {
                            await context.push('/owner/leave/${item['id']}');
                            if (mounted) await _reload();
                          },
                          child: Ink(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: AppColors.border),
                              boxShadow: appCardShadow,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  EmployeeAvatar(
                                    imageUrl: profileImage,
                                    name: name,
                                    size: 44,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 15,
                                                  color: AppColors.textPrimary,
                                                ),
                                              ),
                                            ),
                                            _StatusChip(status: status),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: [
                                            _MetaChip(
                                              icon: Icons.beach_access_rounded,
                                              label: leaveType,
                                              color: _leaveSoft(context),
                                            ),
                                            _MetaChip(
                                              icon: Icons.schedule_rounded,
                                              label: '$days day${days == 1 ? '' : 's'}',
                                              color: const Color(0xFF475569),
                                            ),
                                            _MetaChip(
                                              icon: paid
                                                  ? Icons.payments_outlined
                                                  : Icons.money_off_csred_outlined,
                                              label: paid ? 'Paid' : 'Unpaid',
                                              color: paid
                                                  ? const Color(0xFF15803D)
                                                  : const Color(0xFFB45309),
                                            ),
                                          ],
                                        ),
                                        if ('${item['other_leave_specification'] ?? ''}'
                                            .trim()
                                            .isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            'Other Leave Type: ${'${item['other_leave_specification']}'.trim()}',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Color(0xFF334155),
                                            ),
                                          ),
                                        ],
                                        if (start != null && end != null) ...[
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.calendar_month_outlined,
                                                size: 15,
                                                color: AppColors.textMuted
                                                    .withValues(alpha: 0.9),
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  '${dateFmt.format(start)} – ${dateFmt.format(end)}',
                                                  style: appMutedStyle()
                                                      .copyWith(fontSize: 12),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 10),
                                    child: Icon(
                                      Icons.chevron_right_rounded,
                                      color: AppColors.textMuted
                                          .withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _emptyTitle(String status) {
    switch (status) {
      case 'approved':
        return 'No approved leave yet';
      case 'rejected':
        return 'No rejected leave yet';
      case 'all':
        return 'No leave history yet';
      default:
        return 'No pending requests';
    }
  }

  String _emptySubtitle(String status) {
    switch (status) {
      case 'approved':
        return 'Approved leave requests will show up here.';
      case 'rejected':
        return 'Rejected leave requests will show up here.';
      case 'all':
        return 'Submitted leave requests will appear in history.';
      default:
        return 'You’re all caught up. New leave requests will land here.';
    }
  }
}

class OwnerLeaveDetailScreen extends StatefulWidget {
  const OwnerLeaveDetailScreen({super.key, required this.requestId});

  final String requestId;

  @override
  State<OwnerLeaveDetailScreen> createState() => _OwnerLeaveDetailScreenState();
}

class _OwnerLeaveDetailScreenState extends State<OwnerLeaveDetailScreen> {
  final _repo = sl<OwnerRepository>();
  final _remarks = TextEditingController();
  final _overrideReason = TextEditingController();
  late Future<Map<String, dynamic>> _future;
  bool _busy = false;
  bool? _payrollIsPaid;
  bool _policyIsPaid = true;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final item = await _repo.leaveRequest(widget.requestId);
    final policyPaid = item['policy_is_paid'] as bool? ??
        item['is_paid'] as bool? ??
        true;
    _policyIsPaid = policyPaid;
    _payrollIsPaid ??= policyPaid;
    return item;
  }

  @override
  void dispose() {
    _remarks.dispose();
    _overrideReason.dispose();
    super.dispose();
  }

  Future<void> _review({
    required bool approve,
    required bool cancellation,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final remarks =
          _remarks.text.trim().isEmpty ? null : _remarks.text.trim();
      if (cancellation) {
        if (approve) {
          await _repo.approveLeaveCancellation(
            requestId: widget.requestId,
            remarks: remarks,
          );
        } else {
          await _repo.rejectLeaveCancellation(
            requestId: widget.requestId,
            remarks: remarks,
          );
        }
      } else if (approve) {
        final selectedPaid = _payrollIsPaid ?? _policyIsPaid;
        await _repo.approveLeaveRequest(
          requestId: widget.requestId,
          remarks: remarks,
          isPaid: selectedPaid,
          overrideReason: selectedPaid != _policyIsPaid
              ? (_overrideReason.text.trim().isEmpty
                  ? null
                  : _overrideReason.text.trim())
              : null,
        );
      } else {
        await _repo.rejectLeaveRequest(
          requestId: widget.requestId,
          remarks: remarks,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cancellation
                ? (approve
                    ? 'Leave cancellation approved'
                    : 'Leave cancellation rejected')
                : (approve
                    ? 'Leave request approved'
                    : 'Leave request rejected'),
          ),
        ),
      );
      Navigator.pop(context);
    } on DioException catch (error) {
      if (!mounted) return;
      final detail = error.response?.data is Map
          ? (error.response?.data as Map)['detail']
          : null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            detail is String ? detail : 'Could not update leave request.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat.yMMMd();
    return OwnerShell(
      selectedIndex: 0,
      showBackButton: true,
      title: 'Leave Request',
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData) {
            return _EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Request not found',
              subtitle: 'This leave request may have been removed.',
            );
          }
          final item = snapshot.data!;
          final start = DateTime.tryParse('${item['start_date']}');
          final end = DateTime.tryParse('${item['end_date']}');
          final status = '${item['status']}';
          final pending = status == 'pending';
          final cancellationPending = status == 'cancellation_pending';
          final previous = item['previous_request'];
          final hasPendingChanges =
              item['has_pending_changes'] == true && previous is Map;
          final name = '${item['employee_name'] ?? 'Employee'}';
          final position = '${item['employee_position'] ?? 'No role'}';
          final profileImage =
              item['employee_profile_image_url'] as String?;
          final paid = item['is_paid'] == true;
          final policyPaid = item['policy_is_paid'] as bool? ?? paid;
          final selectedPaid = _payrollIsPaid ?? policyPaid;
          final hasDoc = item['has_supporting_document'] == true;
          final document = item['supporting_document'] as String?;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_leaveSoft(context), _leaveNavy(context)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    EmployeeAvatar(
                      imageUrl: profileImage,
                      name: name,
                      size: 52,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            position,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _StatusChip(status: status, onDark: true),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (hasPendingChanges) ...[
                const SizedBox(height: 14),
                _ComparisonCard(
                  title: 'Previous Request',
                  data: Map<String, dynamic>.from(previous),
                  dateFmt: dateFmt,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: Icon(Icons.arrow_downward_rounded, color: _leaveNavy(context)),
                  ),
                ),
                _ComparisonCard(
                  title: 'Updated Request',
                  data: item,
                  dateFmt: dateFmt,
                  highlight: true,
                ),
                if (hasDoc && document != null && document.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => viewSupportingDocument(
                        context,
                        documentDataUrl: document,
                      ),
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('View document'),
                      style: TextButton.styleFrom(foregroundColor: _leaveNavy(context)),
                    ),
                  ),
                ],
              ] else ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                    boxShadow: appCardShadow,
                  ),
                  child: Column(
                    children: [
                      _DetailRow(
                        icon: Icons.beach_access_rounded,
                        label: 'Leave type',
                        value: '${item['leave_type_label']}',
                      ),
                      if ('${item['other_leave_specification'] ?? ''}'
                          .trim()
                          .isNotEmpty)
                        _DetailRow(
                          icon: Icons.label_outline_rounded,
                          label: 'Other Leave Type',
                          value:
                              '${item['other_leave_specification']}'.trim(),
                        ),
                      _DetailRow(
                        icon: Icons.policy_outlined,
                        label: 'Company Policy',
                        value: policyPaid ? 'Paid Leave' : 'Unpaid Leave',
                        trailing: policyPaid ? 'Paid' : 'Unpaid',
                        trailingColor: policyPaid
                            ? const Color(0xFF15803D)
                            : const Color(0xFFB45309),
                      ),
                      if (!pending)
                        _DetailRow(
                          icon: Icons.payments_outlined,
                          label: 'Payroll Treatment',
                          value: paid ? 'Paid Leave' : 'Unpaid Leave',
                        ),
                      _DetailRow(
                        icon: Icons.calendar_month_outlined,
                        label: 'Requested dates',
                        value: start != null && end != null
                            ? '${dateFmt.format(start)} – ${dateFmt.format(end)}'
                            : '${item['start_date']} – ${item['end_date']}',
                      ),
                      _DetailRow(
                        icon: Icons.schedule_rounded,
                        label: 'Leave days',
                        value: '${item['leave_days']} day(s)',
                      ),
                      _DetailRow(
                        icon: Icons.notes_rounded,
                        label: 'Reason',
                        value: '${item['reason']}',
                      ),
                      _DetailRow(
                        icon: Icons.attach_file_rounded,
                        label: 'Supporting document',
                        value: hasDoc ? 'Attached' : 'None',
                        showDivider: false,
                      ),
                      if (hasDoc && document != null && document.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => viewSupportingDocument(
                                context,
                                documentDataUrl: document,
                              ),
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('View document'),
                              style: TextButton.styleFrom(
                                foregroundColor: _leaveNavy(context),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (pending || cancellationPending) ...[
                if (pending) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Payroll Treatment',
                    style: appSectionTitleStyle().copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Defaults to company policy. Change only if needed.',
                    style: appMutedStyle().copyWith(fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  RadioListTile<bool>(
                    value: true,
                    groupValue: selectedPaid,
                    onChanged: (value) =>
                        setState(() => _payrollIsPaid = value),
                    title: const Text('Paid Leave'),
                    contentPadding: EdgeInsets.zero,
                    activeColor: _leaveNavy(context),
                  ),
                  RadioListTile<bool>(
                    value: false,
                    groupValue: selectedPaid,
                    onChanged: (value) =>
                        setState(() => _payrollIsPaid = value),
                    title: const Text('Unpaid Leave'),
                    contentPadding: EdgeInsets.zero,
                    activeColor: _leaveNavy(context),
                  ),
                  if (selectedPaid != policyPaid) ...[
                    const SizedBox(height: 4),
                    TextField(
                      controller: _overrideReason,
                      decoration: InputDecoration(
                        hintText: 'Reason for override (optional)',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.all(14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              BorderSide(color: _leaveNavy(context), width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 16),
                Text(
                  cancellationPending
                      ? 'Cancellation review'
                      : 'Decision notes',
                  style: appSectionTitleStyle().copyWith(fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  cancellationPending
                      ? 'Approve to cancel this approved leave, or reject to keep it.'
                      : 'Optional remarks are shared with the employee.',
                  style: appMutedStyle().copyWith(fontSize: 12),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _remarks,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'Add a short note (optional)',
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.all(14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: _leaveNavy(context), width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF15803D),
                    minimumSize: const Size.fromHeight(46),
                    elevation: 0,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _busy
                      ? null
                      : () => _review(
                            approve: true,
                            cancellation: cancellationPending,
                          ),
                  child: Text(
                    _busy
                        ? 'Saving…'
                        : cancellationPending
                            ? 'Approve Cancellation'
                            : 'Approve',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB91C1C),
                    side: const BorderSide(color: Color(0xFFFECACA)),
                    minimumSize: const Size.fromHeight(44),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _busy
                      ? null
                      : () => _review(
                            approve: false,
                            cancellation: cancellationPending,
                          ),
                  child: Text(
                    _busy
                        ? 'Saving…'
                        : cancellationPending
                            ? 'Reject Cancellation'
                            : 'Reject',
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({
    required this.title,
    required this.data,
    required this.dateFmt,
    this.highlight = false,
  });

  final String title;
  final Map<String, dynamic> data;
  final DateFormat dateFmt;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final start = DateTime.tryParse('${data['start_date']}');
    final end = DateTime.tryParse('${data['end_date']}');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFEFF6FF) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlight ? const Color(0xFF93C5FD) : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Color(0xFF1F456B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${data['leave_type_label'] ?? data['leave_type']}',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          if ('${data['other_leave_specification'] ?? ''}'.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Other Leave Type: ${'${data['other_leave_specification']}'.trim()}',
            ),
          ],
          const SizedBox(height: 4),
          Text(
            start != null && end != null
                ? '${dateFmt.format(start)} – ${dateFmt.format(end)}'
                : '${data['start_date']} – ${data['end_date']}',
          ),
          Text('${data['leave_days']} day(s)'),
          const SizedBox(height: 6),
          Text('${data['reason']}'),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, this.onDark = false});

  final String status;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: onDark
            ? Colors.white.withValues(alpha: 0.16)
            : style.$1.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: onDark
            ? Border.all(color: Colors.white.withValues(alpha: 0.28))
            : null,
      ),
      child: Text(
        style.$2,
        style: TextStyle(
          color: onDark ? Colors.white : style.$1,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  (Color, String) _styleFor(String value) {
    switch (value) {
      case 'approved':
        return (const Color(0xFF15803D), 'Approved');
      case 'rejected':
        return (const Color(0xFFDC2626), 'Rejected');
      case 'cancellation_pending':
        return (const Color(0xFF7C3AED), 'Cancel Pending');
      case 'cancelled':
        return (const Color(0xFF64748B), 'Cancelled');
      default:
        return (const Color(0xFFB45309), 'Pending');
    }
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
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
    this.trailing,
    this.trailingColor,
    this.showDivider = true,
  });

  final IconData icon;
  final String label;
  final String value;
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
                  color: _leaveWell(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: _leaveSoft(context)),
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
                        fontWeight: FontWeight.w500,
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
                    color: (trailingColor ?? BrandColors.of(context).tonePrimary)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    trailing!,
                    style: TextStyle(
                      color: trailingColor ?? BrandColors.of(context).tonePrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
        if (showDivider) const SizedBox(height: 12),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _leaveWell(context),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon, size: 34, color: _leaveSoft(context)),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: appMutedStyle().copyWith(fontSize: 13, height: 1.4),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1F456B),
                  side: const BorderSide(color: Color(0xFFD7E0EA)),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
