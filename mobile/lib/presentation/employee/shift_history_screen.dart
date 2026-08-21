import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/theme/business_brand_theme.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class ShiftHistoryScreen extends StatefulWidget {
  const ShiftHistoryScreen({
    super.key,
    this.focusAttendanceRecordId,
    this.focusAssignmentId,
  });

  /// When opened from the incomplete-attendance banner, jump to this shift.
  final String? focusAttendanceRecordId;
  final String? focusAssignmentId;

  @override
  State<ShiftHistoryScreen> createState() => _ShiftHistoryScreenState();
}

class _ShiftHistoryScreenState extends State<ShiftHistoryScreen> {
  late Future<List<EmployeeShiftHistoryItem>> _future;
  final _searchController = TextEditingController();
  final _listScrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeys = {};
  String _query = '';
  String? _remarksFilter; // null = all
  int? _monthFilter; // 1-12, null = all
  int? _yearFilter; // null = all
  String? _highlightedItemId;
  bool _didHandleFocus = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _listScrollController.dispose();
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

  GlobalKey _keyForItem(EmployeeShiftHistoryItem item) {
    return _itemKeys.putIfAbsent(item.id, GlobalKey.new);
  }

  EmployeeShiftHistoryItem? _findFocusItem(
    List<EmployeeShiftHistoryItem> items,
  ) {
    final attendanceId = widget.focusAttendanceRecordId?.trim();
    final assignmentId = widget.focusAssignmentId?.trim();
    if ((attendanceId == null || attendanceId.isEmpty) &&
        (assignmentId == null || assignmentId.isEmpty)) {
      return null;
    }

    for (final item in items) {
      if (attendanceId != null &&
          attendanceId.isNotEmpty &&
          (item.attendanceRecordId == attendanceId || item.id == attendanceId)) {
        return item;
      }
    }
    for (final item in items) {
      if (assignmentId != null &&
          assignmentId.isNotEmpty &&
          item.assignmentId == assignmentId) {
        return item;
      }
    }
    return null;
  }

  /// One-time highlight/scroll when opened from the home incomplete banner.
  /// Never auto-navigates away — correction opens only via the card button.
  void _handleFocusIfNeeded(List<EmployeeShiftHistoryItem> items) {
    if (_didHandleFocus) return;
    final focusItem = _findFocusItem(items);
    _didHandleFocus = true;
    if (focusItem == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      setState(() {
        _highlightedItemId = focusItem.id;
        _query = '';
        _searchController.clear();
        _remarksFilter = null;
        _monthFilter = null;
        _yearFilter = null;
      });

      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!mounted) return;

      final key = _itemKeys[focusItem.id];
      final targetContext = key?.currentContext;
      if (targetContext != null && targetContext.mounted) {
        await Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 350),
          alignment: 0.15,
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  /// Presentation-only remark label from existing attendance fields.
  static String remarkLabel(EmployeeShiftHistoryItem item) {
    final status = item.status.toLowerCase();
    if (status == 'incomplete') {
      return 'Incomplete';
    }
    if (status == 'absent') return 'Absent';
    if (status == 'on_leave') return 'On Leave';
    if (status == 'overtime' || status == 'over_time') return 'Over Time';
    if (status == 'undertime' || status == 'under_time') return 'Under Time';
    if (status == 'late') return 'Late';
    if (item.overtimeMinutes > 0) return 'Over Time';
    if (status == 'complete' || status == 'on_time') return 'On Time';
    return employeeAttendanceHistoryLabel(item.status);
  }

  List<EmployeeShiftHistoryItem> _filtered(
    List<EmployeeShiftHistoryItem> items,
  ) {
    return items.where((item) {
      if (_monthFilter != null && item.date.month != _monthFilter) {
        return false;
      }
      if (_yearFilter != null && item.date.year != _yearFilter) {
        return false;
      }
      if (_remarksFilter != null &&
          remarkLabel(item).toLowerCase() != _remarksFilter!.toLowerCase()) {
        return false;
      }
      if (_query.trim().isEmpty) return true;
      final needle = _query.toLowerCase();
      final haystack = [
        item.shiftName,
        item.status,
        item.holidayName,
        item.correctionStatus,
        shortDate(item.date),
        remarkLabel(item),
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: FutureBuilder<List<EmployeeShiftHistoryItem>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return loadingView();
            }
            if (snapshot.hasError) return errorView(snapshot.error);

            final allItems = snapshot.data ?? [];
            _handleFocusIfNeeded(allItems);
            final items = _filtered(allItems);
            final months = allItems.map((e) => e.date.month).toSet().toList()
              ..sort();
            final years = allItems.map((e) => e.date.year).toSet().toList()
              ..sort((a, b) => b.compareTo(a));
            final remarks = allItems.map(remarkLabel).toSet().toList()..sort();

            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                controller: _listScrollController,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                children: [
                  _HistoryTopBar(
                    onBack: () => employeeNavigateBack(context),
                  ),
                  const SizedBox(height: 12),
                  _FilterCard(
                    searchController: _searchController,
                    query: _query,
                    remarks: remarks,
                    months: months,
                    years: years,
                    remarksFilter: _remarksFilter,
                    monthFilter: _monthFilter,
                    yearFilter: _yearFilter,
                    onQueryChanged: (value) => setState(() => _query = value),
                    onRemarksChanged: (value) =>
                        setState(() => _remarksFilter = value),
                    onMonthChanged: (value) =>
                        setState(() => _monthFilter = value),
                    onYearChanged: (value) =>
                        setState(() => _yearFilter = value),
                  ),
                  const SizedBox(height: 14),
                  if (items.isEmpty)
                    EmployeeEmptyState(
                      title: allItems.isEmpty
                          ? 'No shift history yet'
                          : 'No matching records',
                      description: allItems.isEmpty
                          ? 'Completed shifts and attendance results will appear here after you work assigned schedules.'
                          : 'Try a different search or filter.',
                      icon: Icons.history_rounded,
                      inCard: true,
                    )
                  else
                    ...items.map(
                      (item) => Padding(
                        key: _keyForItem(item),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _HistoryCard(
                          item: item,
                          remark: remarkLabel(item),
                          highlighted: _highlightedItemId == item.id,
                          onRequestCorrection: () => _openCorrection(item),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: const EmployeeBottomNav(selectedIndex: 1),
    );
  }
}

class _HistoryTopBar extends StatelessWidget {
  const _HistoryTopBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          tooltip: 'Back',
          icon: const Icon(
            Icons.arrow_back_rounded,
            size: 22,
            color: EmployeeColors.textPrimary,
          ),
        ),
        const Expanded(
          child: EmployeePageTitle('Shift History'),
        ),
      ],
    );
  }
}

class _FilterCard extends StatelessWidget {
  const _FilterCard({
    required this.searchController,
    required this.query,
    required this.remarks,
    required this.months,
    required this.years,
    required this.remarksFilter,
    required this.monthFilter,
    required this.yearFilter,
    required this.onQueryChanged,
    required this.onRemarksChanged,
    required this.onMonthChanged,
    required this.onYearChanged,
  });

  final TextEditingController searchController;
  final String query;
  final List<String> remarks;
  final List<int> months;
  final List<int> years;
  final String? remarksFilter;
  final int? monthFilter;
  final int? yearFilter;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String?> onRemarksChanged;
  final ValueChanged<int?> onMonthChanged;
  final ValueChanged<int?> onYearChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EmployeeColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: searchController,
                  onChanged: onQueryChanged,
                  decoration: _fieldDecoration(
                    context,
                    hintText: 'Search',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StringFilterDropdown(
                  value: remarksFilter,
                  hint: 'Remarks',
                  items: remarks,
                  onChanged: onRemarksChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _IntFilterDropdown(
                  value: monthFilter,
                  hint: 'Month',
                  items: months,
                  labelBuilder: (month) => DateFormat('MMMM').format(
                    DateTime(2026, month),
                  ),
                  onChanged: onMonthChanged,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _IntFilterDropdown(
                  value: yearFilter,
                  hint: 'Year',
                  items: years,
                  labelBuilder: (year) => '$year',
                  onChanged: onYearChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Date',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: EmployeeColors.textMuted,
                  ),
                ),
              ),
              Text(
                'Remarks',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: EmployeeColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

InputDecoration _fieldDecoration(
  BuildContext context, {
  String? hintText,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  final brand = BrandColors.of(context);
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: EmployeeColors.border),
  );
  return InputDecoration(
    hintText: hintText,
    hintStyle: const TextStyle(
      color: EmployeeColors.textMuted,
      fontSize: 13,
      fontWeight: FontWeight.w500,
    ),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: Colors.white,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: BorderSide(color: brand.primary, width: 1.5),
    ),
  );
}

class _StringFilterDropdown extends StatelessWidget {
  const _StringFilterDropdown({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  final String? value;
  final String hint;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return _FilterMenuButton(
      label: value ?? hint,
      muted: value == null,
      entries: [
        (label: hint, selected: value == null, onTap: () => onChanged(null)),
        for (final item in items)
          (
            label: item,
            selected: value == item,
            onTap: () => onChanged(item),
          ),
      ],
    );
  }
}

class _IntFilterDropdown extends StatelessWidget {
  const _IntFilterDropdown({
    required this.value,
    required this.hint,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
  });

  final int? value;
  final String hint;
  final List<int> items;
  final String Function(int value) labelBuilder;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return _FilterMenuButton(
      label: value == null ? hint : labelBuilder(value!),
      muted: value == null,
      entries: [
        (label: hint, selected: value == null, onTap: () => onChanged(null)),
        for (final item in items)
          (
            label: labelBuilder(item),
            selected: value == item,
            onTap: () => onChanged(item),
          ),
      ],
    );
  }
}

class _FilterMenuButton extends StatelessWidget {
  const _FilterMenuButton({
    required this.label,
    required this.muted,
    required this.entries,
  });

  final String label;
  final bool muted;
  final List<({String label, bool selected, VoidCallback onTap})> entries;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () async {
          final box = context.findRenderObject() as RenderBox?;
          final overlay =
              Overlay.of(context).context.findRenderObject() as RenderBox?;
          if (box == null || overlay == null) return;
          final position = RelativeRect.fromRect(
            Rect.fromPoints(
              box.localToGlobal(Offset.zero, ancestor: overlay),
              box.localToGlobal(
                box.size.bottomRight(Offset.zero),
                ancestor: overlay,
              ),
            ),
            Offset.zero & overlay.size,
          );
          final selected = await showMenu<int>(
            context: context,
            position: position,
            items: [
              for (var i = 0; i < entries.length; i++)
                PopupMenuItem<int>(
                  value: i,
                  child: Text(
                    entries[i].label,
                    style: TextStyle(
                      fontWeight: entries[i].selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: entries[i].selected
                          ? BrandColors.of(context).primary
                          : EmployeeColors.textBody,
                    ),
                  ),
                ),
            ],
          );
          if (selected != null) entries[selected].onTap();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: EmployeeColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: muted
                        ? EmployeeColors.textMuted
                        : EmployeeColors.textBody,
                    fontSize: 13,
                    fontWeight: muted ? FontWeight.w500 : FontWeight.w600,
                  ),
                ),
              ),
              const Icon(
                Icons.unfold_more_rounded,
                size: 18,
                color: EmployeeColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.item,
    required this.remark,
    required this.onRequestCorrection,
    this.highlighted = false,
  });

  final EmployeeShiftHistoryItem item;
  final String remark;
  final VoidCallback onRequestCorrection;
  final bool highlighted;

  Color get _statusColor {
    final normalized = remark.toLowerCase();
    if (normalized == 'incomplete') return const Color(0xFFD97706);
    if (normalized == 'on time') return const Color(0xFF16A34A);
    if (normalized == 'under time' || normalized == 'late') {
      return const Color(0xFFEA580C);
    }
    if (normalized == 'over time') return const Color(0xFF2563EB);
    if (normalized == 'absent') return const Color(0xFFDC2626);
    if (normalized == 'on leave') return const Color(0xFF0284C7);
    return statusColor(item.status);
  }

  String get _shiftRange {
    final start = item.shiftStart ?? '--';
    final end = item.shiftEnd ?? '--';
    return '$start – $end';
  }

  String get _totalHours {
    if (item.timeIn != null && item.timeOut != null) {
      final minutes = item.timeOut!.difference(item.timeIn!).inMinutes;
      if (minutes > 0) {
        final hours = minutes / 60.0;
        if ((hours - hours.round()).abs() < 0.05) {
          return '${hours.round()} hrs';
        }
        return '${hours.toStringAsFixed(1)} hrs';
      }
    }
    return '--';
  }

  bool get _isIncomplete => item.status.toLowerCase() == 'incomplete';

  @override
  Widget build(BuildContext context) {
    final statusColorValue = _statusColor;
    final brand = BrandColors.of(context);

    return Container(
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFFFFFBEB) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlighted
              ? const Color(0xFFF59E0B)
              : EmployeeColors.border,
          width: highlighted ? 1.3 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 3, color: statusColorValue),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
                            DateFormat('MMM d, yyyy').format(item.date),
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: EmployeeColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.shiftName?.trim().isNotEmpty == true
                                ? '${item.shiftName} · $_shiftRange'
                                : _shiftRange,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: EmployeeColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    EmployeeStatusChip(
                      label: remark,
                      color: statusColorValue,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE8EEF4)),
                  ),
                  child: Column(
                    children: [
                      _MetricRow(
                        label: 'Time In',
                        value: timeOnly(item.timeIn),
                      ),
                      const SizedBox(height: 5),
                      const Divider(height: 1, color: Color(0xFFE8EEF4)),
                      const SizedBox(height: 5),
                      _MetricRow(
                        label: 'Time Out',
                        value: timeOnly(item.timeOut),
                        emphasizeMissing: _isIncomplete && item.timeOut == null,
                      ),
                      const SizedBox(height: 5),
                      const Divider(height: 1, color: Color(0xFFE8EEF4)),
                      const SizedBox(height: 5),
                      _MetricRow(
                        label: 'Total Hours',
                        value: _totalHours,
                      ),
                    ],
                  ),
                ),
                if (item.holidayName != null &&
                    item.holidayName!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Holiday: ${item.holidayName}',
                    style: const TextStyle(
                      color: EmployeeColors.textMuted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (_isIncomplete) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: Color(0xFFD97706),
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Clock-out missing. Submit a correction to complete this attendance.',
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF92400E),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (item.correctionStatus != null) ...[
                  const SizedBox(height: 8),
                  _CorrectionStatusBanner(item: item),
                ],
                if (item.canRequestCorrection &&
                    item.correctionStatus != 'approved' &&
                    item.correctionStatus != 'pending') ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onRequestCorrection,
                      icon: Icon(
                        Icons.edit_calendar_outlined,
                        size: 16,
                        color: brand.primary,
                      ),
                      label: Text(
                        _isIncomplete
                            ? 'Fix incomplete attendance'
                            : 'Request correction',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: brand.primary,
                        backgroundColor: brand.iconWell,
                        side: BorderSide(
                          color: brand.primary.withValues(alpha: 0.22),
                        ),
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    this.emphasizeMissing = false,
  });

  final String label;
  final String value;
  final bool emphasizeMissing;

  @override
  Widget build(BuildContext context) {
    final showMissing =
        emphasizeMissing && (value == '--' || value.trim().isEmpty);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: EmployeeColors.textMuted,
            ),
          ),
        ),
        Text(
          showMissing ? 'Missing' : value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: showMissing
                ? const Color(0xFFD97706)
                : EmployeeColors.textPrimary,
          ),
        ),
      ],
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
