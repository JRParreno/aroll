import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/theme/business_brand_theme.dart';
import 'package:aroll_mobile/domain/entities/leave_request.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class LeaveRequestsScreen extends StatefulWidget {
  const LeaveRequestsScreen({super.key});

  @override
  State<LeaveRequestsScreen> createState() => _LeaveRequestsScreenState();
}

class _LeaveRequestsScreenState extends State<LeaveRequestsScreen>
    with SingleTickerProviderStateMixin {
  final _repo = sl<EmployeeRepository>();
  late final TabController _tabs;
  Future<List<LeaveRequestItem>>? _future;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _future = _repo.getLeaveRequests();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final next = _repo.getLeaveRequests();
    setState(() {
      _future = next;
    });
    try {
      await next;
    } catch (_) {
      // FutureBuilder shows the error state.
    }
  }

  Future<void> _openRequestLeave() async {
    final created = await context.push<bool>('/leave-requests/new');
    if (created == true && mounted) await _reload();
  }

  List<LeaveRequestItem> _filter(
    List<LeaveRequestItem> all,
    String status,
  ) {
    if (status == 'history') return all;
    return all.where((item) => item.status == status).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final brand = BrandColors.of(context);
    final primary = brand.primary;
    final soft = Color.lerp(primary, Colors.white, 0.18) ?? primary;
    return Scaffold(
      backgroundColor: EmployeeColors.scaffold,
      appBar: AppBar(
        title: const Text('Leave Requests'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: brand.iconWell,
                borderRadius: BorderRadius.circular(14),
              ),
              child: TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: Colors.white,
                unselectedLabelColor: const Color(0xFF64748B),
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.22),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                tabs: const [
                  Tab(text: 'Pending'),
                  Tab(text: 'Approved'),
                  Tab(text: 'Cancelling'),
                  Tab(text: 'Rejected'),
                  Tab(text: 'History'),
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 72),
        child: FloatingActionButton.extended(
          backgroundColor: brand.button,
          foregroundColor: Colors.white,
          elevation: 3,
          onPressed: _openRequestLeave,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Request Leave'),
        ),
      ),
      body: FutureBuilder<List<LeaveRequestItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: primary),
            );
          }
          if (snapshot.hasError) {
            return _EmptyState(
              icon: Icons.wifi_off_rounded,
              title: 'Could not load requests',
              subtitle: 'Check your connection and try again.',
              actionLabel: 'Retry',
              onAction: _reload,
              accent: primary,
            );
          }
          final all = snapshot.data ?? const [];
          return TabBarView(
            controller: _tabs,
            children: [
              for (final key in const [
                'pending',
                'approved',
                'cancellation_pending',
                'rejected',
                'history',
              ])
                RefreshIndicator(
                  color: primary,
                  onRefresh: _reload,
                  child: _LeaveList(
                    items: _filter(all, key),
                    statusKey: key,
                    accent: soft,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _LeaveList extends StatelessWidget {
  const _LeaveList({
    required this.items,
    required this.statusKey,
    required this.accent,
  });

  final List<LeaveRequestItem> items;
  final String statusKey;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.55,
            child: _EmptyState(
              icon: Icons.event_available_outlined,
              title: _emptyTitle(statusKey),
              subtitle: _emptySubtitle(statusKey),
              accent: accent,
            ),
          ),
        ],
      );
    }
    final dateFmt = DateFormat.MMMd();
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = items[index];
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => context.push('/leave-requests/${item.id}'),
            child: Ink(
              decoration: BoxDecoration(
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
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.beach_access_rounded,
                        color: accent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.leaveTypeLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: EmployeeColors.textPrimary,
                                  ),
                                ),
                              ),
                              _StatusChip(status: item.status),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _MetaChip(
                                icon: Icons.schedule_rounded,
                                label:
                                    '${item.leaveDays} day${item.leaveDays == 1 ? '' : 's'}',
                                color: const Color(0xFF475569),
                              ),
                              _MetaChip(
                                icon: item.isPaid
                                    ? Icons.payments_outlined
                                    : Icons.money_off_csred_outlined,
                                label: item.isPaid ? 'Paid' : 'Unpaid',
                                color: item.isPaid
                                    ? const Color(0xFF15803D)
                                    : const Color(0xFFB45309),
                              ),
                              if (item.hasSupportingDocument)
                                _MetaChip(
                                  icon: Icons.attach_file_rounded,
                                  label: 'Document',
                                  color: accent,
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(
                                Icons.calendar_month_outlined,
                                size: 15,
                                color: EmployeeColors.textMuted
                                    .withValues(alpha: 0.9),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${dateFmt.format(item.startDate)} – ${dateFmt.format(item.endDate)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: EmployeeColors.textMuted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (item.reason.trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              item.reason,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF6B7280),
                                height: 1.35,
                              ),
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
                        color: EmployeeColors.textMuted.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _emptyTitle(String status) {
    switch (status) {
      case 'approved':
        return 'No approved leave yet';
      case 'rejected':
        return 'No rejected leave yet';
      case 'cancellation_pending':
        return 'No cancellation requests';
      case 'history':
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
      case 'cancellation_pending':
        return 'Requests to cancel approved leave will appear here while waiting for owner approval.';
      case 'history':
        return 'All of your submitted leave requests will appear here, including cancelled requests.';
      default:
        return 'Need time off? Submit a leave request and track its approval here.';
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'approved' => ('Approved', const Color(0xFF15803D)),
      'rejected' => ('Rejected', const Color(0xFFDC2626)),
      'cancellation_pending' => ('Cancellation Pending', const Color(0xFF7C3AED)),
      'cancelled' => ('Cancelled', const Color(0xFF64748B)),
      _ => ('Pending', const Color(0xFFB45309)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
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
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
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
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon, size: 34, color: accent),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: EmployeeColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: EmployeeColors.textMuted,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(backgroundColor: accent),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
