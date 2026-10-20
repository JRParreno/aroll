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
  int _balanceRefresh = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
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
      _balanceRefresh += 1;
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
          preferredSize: const Size.fromHeight(46),
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: primary,
            unselectedLabelColor: const Color(0xFF64748B),
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 13.5,
            ),
            indicatorColor: primary,
            indicatorWeight: 2,
            dividerColor: const Color(0xFFE5E7EB),
            labelPadding: const EdgeInsets.symmetric(horizontal: 14),
            tabs: const [
              Tab(text: 'Leave Allowances'),
              Tab(text: 'Pending'),
              Tab(text: 'Approved'),
              Tab(text: 'Rejected'),
              Tab(text: 'Cancellation Pending'),
              Tab(text: 'History'),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 72),
        child: FloatingActionButton.extended(
          backgroundColor: brand.button,
          foregroundColor: Colors.white,
          elevation: 1,
          onPressed: _openRequestLeave,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text(
            'Request Leave',
            style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          ),
        ),
      ),
      body: FutureBuilder<List<LeaveRequestItem>>(
        future: _future,
        builder: (context, snapshot) {
          final requestsReady =
              snapshot.connectionState != ConnectionState.waiting &&
              !snapshot.hasError;
          final all = snapshot.data ?? const <LeaveRequestItem>[];
          return TabBarView(
            controller: _tabs,
            children: [
              _LeaveAllowancesPage(
                repo: _repo,
                refreshToken: _balanceRefresh,
                accent: primary,
              ),
              if (!requestsReady && snapshot.connectionState == ConnectionState.waiting)
                for (var i = 0; i < 5; i++)
                  Center(child: CircularProgressIndicator(color: primary))
              else if (snapshot.hasError)
                for (var i = 0; i < 5; i++)
                  _EmptyState(
                    icon: Icons.wifi_off_rounded,
                    title: 'Could not load requests',
                    subtitle: 'Check your connection and try again.',
                    actionLabel: 'Retry',
                    onAction: _reload,
                    accent: primary,
                  )
              else
                for (final key in const [
                  'pending',
                  'approved',
                  'rejected',
                  'cancellation_pending',
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

class _LeaveAllowancesPage extends StatefulWidget {
  const _LeaveAllowancesPage({
    required this.repo,
    required this.refreshToken,
    required this.accent,
  });

  final EmployeeRepository repo;
  final int refreshToken;
  final Color accent;

  @override
  State<_LeaveAllowancesPage> createState() => _LeaveAllowancesPageState();
}

class _LeaveAllowancesPageState extends State<_LeaveAllowancesPage> {
  Future<LeaveBalance>? _future;
  int? _year;
  bool _yearPinned = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _LeaveAllowancesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  Future<void> _load() async {
    final next = widget.repo.getLeaveBalances(year: _yearPinned ? _year : null);
    setState(() => _future = next);
    try {
      final data = await next;
      if (!mounted || _yearPinned) return;
      setState(() => _year = data.year);
    } catch (_) {
      // FutureBuilder shows the error state.
    }
  }

  void _changeYear(int delta) {
    final current = _year ?? DateTime.now().year;
    setState(() {
      _yearPinned = true;
      _year = current + delta;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LeaveBalance>(
      future: _future,
      builder: (context, snapshot) {
        final year = snapshot.data?.year ?? _year;
        return RefreshIndicator(
          color: widget.accent,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Leave Allowances',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _changeYear(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(
                    '${year ?? ''}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                      color: Color(0xFF111827),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _changeYear(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const Text(
                'Your leave availability for this year.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 14),
              if (snapshot.connectionState == ConnectionState.waiting)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Center(
                    child: CircularProgressIndicator(color: widget.accent),
                  ),
                )
              else if (snapshot.hasError)
                _EmptyState(
                  icon: Icons.wifi_off_rounded,
                  title: 'Unable to load leave allowances.',
                  subtitle: 'Please try again.',
                  actionLabel: 'Retry',
                  onAction: _load,
                  accent: widget.accent,
                )
              else
                _AllowanceBody(
                  items: snapshot.data?.items ?? const [],
                  accent: widget.accent,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AllowanceBody extends StatelessWidget {
  const _AllowanceBody({required this.items, required this.accent});

  final List<LeaveBalanceItem> items;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final visible =
        items.where((item) => item.leaveType != 'unpaid').toList();
    final available = visible.where((item) => item.configured).toList();
    final unavailable = visible.where((item) => !item.configured).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (available.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'No leave allowances have been configured for this year.',
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Color(0xFF334155),
              ),
            ),
          ),
        for (final item in available) ...[
          _AvailableAllowanceCard(item: item, accent: accent),
          const SizedBox(height: 10),
        ],
        if (unavailable.isNotEmpty) ...[
          const SizedBox(height: 6),
          const Text(
            'Other leave types',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 8),
          for (final item in unavailable) ...[
            _UnavailableAllowanceCard(item: item),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _AvailableAllowanceCard extends StatelessWidget {
  const _AvailableAllowanceCard({required this.item, required this.accent});

  final LeaveBalanceItem item;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final allocated = item.allocatedDays ?? 0;
    final used = item.usedDays;
    final remaining = item.remainingDays ?? 0;
    final progress = allocated <= 0 ? 0.0 : (used / allocated).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.leaveTypeLabel,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Available',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF166534),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            remaining == 1 ? '1 day remaining' : '$remaining days remaining',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            allocated == 1 ? '1 day allocated' : '$allocated days allocated',
            style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
          ),
          Text(
            used == 1 ? '1 day used' : '$used days used',
            style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: const Color(0xFFE5E7EB),
              color: accent,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Used: $used / $allocated days',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}

class _UnavailableAllowanceCard extends StatelessWidget {
  const _UnavailableAllowanceCard({required this.item});

  final LeaveBalanceItem item;

  @override
  Widget build(BuildContext context) {
    final disabled = item.disabled;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.leaveTypeLabel,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            disabled ? 'Unavailable' : 'Not configured',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF92400E),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            disabled
                ? 'Currently not available for new leave requests.'
                : 'Contact your administrator if you need information about this leave type.',
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: Color(0xFF64748B),
            ),
          ),
        ],
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
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => context.push('/leave-requests/${item.id}'),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: EmployeeColors.border),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.beach_access_outlined,
                        color: accent,
                        size: 18,
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
                                    fontWeight: FontWeight.w600,
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
                                    fontWeight: FontWeight.w400,
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
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
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
                fontWeight: FontWeight.w600,
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
              OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  side: BorderSide(color: accent.withValues(alpha: 0.35)),
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
