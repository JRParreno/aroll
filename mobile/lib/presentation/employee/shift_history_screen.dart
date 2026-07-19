import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ShiftHistoryScreen extends StatefulWidget {
  const ShiftHistoryScreen({super.key});

  @override
  State<ShiftHistoryScreen> createState() => _ShiftHistoryScreenState();
}

class _ShiftHistoryScreenState extends State<ShiftHistoryScreen> {
  late Future<List<EmployeeShiftHistoryItem>> _future;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<EmployeeShiftHistoryItem>> _load() async {
    return sl<EmployeeRepository>().getShiftHistory();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  List<EmployeeShiftHistoryItem> _filtered(
    List<EmployeeShiftHistoryItem> items,
  ) {
    if (_query.trim().isEmpty) return items;
    final needle = _query.toLowerCase();
    return items.where((item) {
      final haystack = [
        item.shiftName,
        item.status,
        item.holidayName,
        item.correctionStatus,
        shortDate(item.date),
        employeeAttendanceHistoryLabel(item.status),
      ].whereType<String>().join(' ').toLowerCase();
      return haystack.contains(needle);
    }).toList();
  }

  Future<void> _openCorrection(EmployeeShiftHistoryItem item) async {
    final result = await context.push<bool>(
      '/shift-history/correction',
      extra: item,
    );
    if (result == true && mounted) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return EmployeeScaffold(
      title: 'Shift History',
      selectedIndex: 1,
      showBack: true,
      child: FutureBuilder<List<EmployeeShiftHistoryItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return loadingView();
          }
          if (snapshot.hasError) return errorView(snapshot.error);

          final items = _filtered(snapshot.data ?? []);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                _HistoryHeader(totalCount: snapshot.data?.length ?? 0),
                const SizedBox(height: 12),
                EmployeeCard(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: employeeInputDecoration(
                      hintText: 'Search by shift, date, or status',
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (items.isEmpty)
                  EmployeeEmptyState(
                    title: snapshot.data?.isEmpty ?? true
                        ? 'No shift history yet'
                        : 'No matching records',
                    description: snapshot.data?.isEmpty ?? true
                        ? 'Completed shifts and attendance results will appear here after you work assigned schedules.'
                        : 'Try a different search term.',
                    icon: Icons.history_rounded,
                    inCard: true,
                  )
                else
                  ...items.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _HistoryCard(
                        item: item,
                        onRequestCorrection: () => _openCorrection(item),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({required this.totalCount});

  final int totalCount;

  @override
  Widget build(BuildContext context) {
    return EmployeeCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: EmployeeColors.iconWell,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.history_rounded,
              color: EmployeeColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Past shifts',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  totalCount == 0
                      ? 'Forgot a punch? You can request a correction here.'
                      : '$totalCount record${totalCount == 1 ? '' : 's'} · request a correction if you forgot to clock in or out',
                  style: const TextStyle(
                    color: EmployeeColors.textMuted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.item,
    required this.onRequestCorrection,
  });

  final EmployeeShiftHistoryItem item;
  final VoidCallback onRequestCorrection;

  @override
  Widget build(BuildContext context) {
    final label = employeeAttendanceHistoryLabel(item.status);
    final color = statusColor(item.status);
    final missingLabel = item.needsClockIn && item.needsClockOut
        ? 'Missing clock-in and clock-out'
        : item.needsClockIn
            ? 'Missing clock-in'
            : item.needsClockOut
                ? 'Missing clock-out'
                : null;

    return EmployeeCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dayName(item.date),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: EmployeeColors.textBody,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      shortDate(item.date),
                      style: const TextStyle(
                        color: EmployeeColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              EmployeeStatusChip(label: label, color: color),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.work_outline_rounded,
                size: 18,
                color: EmployeeColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.shiftName ?? 'Shift',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          EmployeeInfoRow(
            icon: Icons.schedule_rounded,
            text:
                'Work time: ${item.shiftStart ?? '--'} - ${item.shiftEnd ?? '--'}',
          ),
          if (item.timeIn != null || item.timeOut != null) ...[
            const SizedBox(height: 6),
            EmployeeInfoRow(
              icon: Icons.login_rounded,
              text: 'Clock in: ${timeOnly(item.timeIn)}',
            ),
            const SizedBox(height: 6),
            EmployeeInfoRow(
              icon: Icons.logout_rounded,
              text: 'Clock out: ${timeOnly(item.timeOut)}',
            ),
          ] else if (missingLabel != null) ...[
            const SizedBox(height: 6),
            EmployeeInfoRow(
              icon: Icons.warning_amber_rounded,
              text: missingLabel,
            ),
          ],
          if (item.holidayName != null && item.holidayName!.isNotEmpty) ...[
            const SizedBox(height: 6),
            EmployeeInfoRow(
              icon: Icons.celebration_outlined,
              text: 'Holiday: ${item.holidayName}',
            ),
          ],
          if (item.correctionStatus != null) ...[
            const SizedBox(height: 10),
            _CorrectionStatusBanner(item: item),
          ],
          if (item.canRequestCorrection) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onRequestCorrection,
                icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                label: const Text('Request correction'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: EmployeeColors.primaryDark,
                  side: const BorderSide(color: EmployeeColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CorrectionStatusBanner extends StatelessWidget {
  const _CorrectionStatusBanner({required this.item});

  final EmployeeShiftHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final status = item.correctionStatus ?? '';
    final Color bg;
    final Color fg;
    final String title;
    switch (status) {
      case 'pending':
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFF92400E);
        title = 'Correction pending approval';
      case 'approved':
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF166534);
        title = 'Correction approved';
      case 'rejected':
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFB91C1C);
        title = 'Correction rejected';
      default:
        bg = EmployeeColors.chipFill;
        fg = EmployeeColors.textMuted;
        title = 'Correction: $status';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          if (item.correctionReviewNote != null &&
              item.correctionReviewNote!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              item.correctionReviewNote!,
              style: TextStyle(color: fg, fontSize: 12, height: 1.3),
            ),
          ],
        ],
      ),
    );
  }
}
