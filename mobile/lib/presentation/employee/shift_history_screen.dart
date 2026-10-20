import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/theme/business_brand_theme.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:aroll_mobile/presentation/shared/shift_history_grouping.dart';
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
    if (status == 'holiday_paid') return 'Paid Holiday — Not Worked';
    if (status == 'on_leave') {
      final amount = item.shiftNet ?? item.earned;
      if (amount != null && amount > 0) return 'Paid Leave';
      if (amount != null) return 'Unpaid Leave';
      return 'On Leave';
    }
    if (status == 'absent') return 'Absent';
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
                    ...() {
                      final entries = buildEmployeeShiftHistoryEntries(
                        items: items,
                        dateOf: (e) => e.date,
                        shiftName: (e) => e.shiftName,
                        scheduledStart: (e) => e.shiftStart,
                      );
                      return entries.map((entry) {
                        if (entry is List<EmployeeShiftHistoryItem>) {
                          final multi = entry;
                          EmployeeShiftHistoryItem? focusChild;
                          for (final e in multi) {
                            if (e.id == _highlightedItemId) {
                              focusChild = e;
                              break;
                            }
                          }
                          final keyItem = focusChild ?? multi.first;
                          return Padding(
                            key: _keyForItem(keyItem),
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _MultiShiftHistoryCard(
                              items: multi,
                              remarkFor: remarkLabel,
                              highlighted:
                                  multi.any((e) => e.id == _highlightedItemId),
                              onRequestCorrection: _openCorrection,
                            ),
                          );
                        }
                        final item = entry as EmployeeShiftHistoryItem;
                        return Padding(
                          key: _keyForItem(item),
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _HistoryCard(
                            item: item,
                            remark: remarkLabel(item),
                            highlighted: _highlightedItemId == item.id,
                            onRequestCorrection: () => _openCorrection(item),
                          ),
                        );
                      });
                    }(),
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

class _MultiShiftHistoryCard extends StatelessWidget {
  const _MultiShiftHistoryCard({
    required this.items,
    required this.remarkFor,
    required this.onRequestCorrection,
    this.highlighted = false,
  });

  final List<EmployeeShiftHistoryItem> items;
  final String Function(EmployeeShiftHistoryItem) remarkFor;
  final void Function(EmployeeShiftHistoryItem) onRequestCorrection;
  final bool highlighted;

  static const _moneyGreen = Color(0xFF16A34A);

  String _hoursWorkedLabel(EmployeeShiftHistoryItem item) {
    final worked = item.workedMinutes;
    if (worked != null && worked > 0) {
      final hours = worked / 60.0;
      if ((hours - hours.round()).abs() < 0.05) {
        return '${hours.round()} hrs';
      }
      return '${hours.toStringAsFixed(1)} hrs';
    }
    return '--';
  }

  String _rateUsedLabel(EmployeeShiftHistoryItem item) {
    if (item.historicalRateRequired || item.dailyRateConflict) {
      return 'Historical Rate Required';
    }
    if (item.rateUsed == null) return '—';
    final basis = (item.payBasisUsed ?? '').toLowerCase();
    final suffix = basis == 'hourly'
        ? '/hour'
        : basis == 'monthly'
            ? '/month'
            : '/day';
    return '${money(item.rateUsed!)}$suffix';
  }

  String _earnedLabel(
    EmployeeShiftHistoryItem item,
    List<EmployeeShiftHistoryItem> siblings,
  ) {
    if (item.historicalRateRequired || item.dailyRateConflict) {
      return 'Unresolved';
    }
    final face = presentShiftPayFromMap(
      _shiftPayMap(item),
      siblings.map(_shiftPayMap).toList(),
    );
    if (!face.showEarned || face.earned == null) return '—';
    return money(face.earned!);
  }

  String _payBasisLabel(EmployeeShiftHistoryItem item) {
    final basis = (item.payBasisUsed ?? '').toLowerCase();
    if (basis == 'hourly') return 'Hourly';
    if (basis == 'monthly') return 'Monthly';
    if (basis == 'daily') return 'Daily';
    return item.payBasisUsed?.isNotEmpty == true ? item.payBasisUsed! : '—';
  }

  @override
  Widget build(BuildContext context) {
    final useReconciled =
        items.isNotEmpty && items.every((e) => e.hasReconciledDayTotal);
    final netSum = useReconciled
        ? null
        : sumAuthoritativeShiftNet(
            items.map(
              (e) => (
                shiftNet: e.shiftNet,
                historicalRateRequired:
                    e.historicalRateRequired || e.dailyRateConflict,
              ),
            ),
          );
    final reconciledTotal = useReconciled ? items.first.reconciledDayTotal : null;
    final unresolved = items.any(
      (e) => e.historicalRateRequired || e.dailyRateConflict,
    );
    final finalLabel = unresolved
        ? 'Unresolved'
        : useReconciled
            ? (reconciledTotal == null ? '—' : money(reconciledTotal))
            : (netSum!.unresolved
                ? 'Unresolved'
                : (netSum.total == null ? '—' : money(netSum.total!)));
    final equation = !unresolved &&
            useReconciled &&
            reconciledTotal != null
        ? historyDayEquationFromMaps(
            items.map(_shiftPayMap).toList(),
            reconciledTotal,
            money,
          )
        : (!useReconciled &&
                netSum != null &&
                !netSum.unresolved &&
                netSum.parts.length >= 2 &&
                netSum.total != null
            ? '${netSum.parts.map(money).join(' + ')} = ${money(netSum.total!)}'
            : null);

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
          Container(height: 3, color: const Color(0xFF0F766E)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('MMMM d, yyyy').format(items.first.date),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: EmployeeColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${items.length} shifts',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: EmployeeColors.textMuted,
                  ),
                ),
                const SizedBox(height: 10),
                if (dateLevelPayFromMaps(items.map(_shiftPayMap).toList())
                    case final datePay?) ...[
                  if (datePay.dailyEntitlement != null)
                    _KvRow(
                      label: 'Daily Entitlement',
                      value: money(datePay.dailyEntitlement!),
                      valueColor: const Color(0xFF16A34A),
                    ),
                  if (datePay.restDayPremium != null)
                    _KvRow(
                      label: 'Rest-Day Premium',
                      value: money(datePay.restDayPremium!),
                      valueColor: const Color(0xFF16A34A),
                    ),
                  if (datePay.holidayPay != null)
                    _KvRow(
                      label: 'Holiday Pay',
                      value: money(datePay.holidayPay!),
                      valueColor: const Color(0xFF16A34A),
                    ),
                  const SizedBox(height: 10),
                ],
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _MultiShiftSection(
                    title: shiftIndexLabel(i, items[i].shiftName),
                    remark: remarkFor(items[i]),
                    hoursLabel: _hoursWorkedLabel(items[i]),
                    payBasisLabel: _payBasisLabel(items[i]),
                    rateLabel: _rateUsedLabel(items[i]),
                    earnedLabel: _earnedLabel(items[i], items),
                    showEarned: presentShiftPayFromMap(
                      _shiftPayMap(items[i]),
                      items.map(_shiftPayMap).toList(),
                    ).showEarned,
                    item: items[i],
                    siblings: items,
                    onRequestCorrection: () =>
                        onRequestCorrection(items[i]),
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'DAY TOTAL',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              color: Color(0xFF065F46),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            finalLabel,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: _moneyGreen,
                            ),
                          ),
                        ],
                      ),
                      if (equation != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          equation,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF047857),
                          ),
                        ),
                      ],
                    ],
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

class _MultiShiftSection extends StatefulWidget {
  const _MultiShiftSection({
    required this.title,
    required this.remark,
    required this.hoursLabel,
    required this.payBasisLabel,
    required this.rateLabel,
    required this.earnedLabel,
    required this.showEarned,
    required this.item,
    required this.siblings,
    required this.onRequestCorrection,
  });

  final String title;
  final String remark;
  final String hoursLabel;
  final String payBasisLabel;
  final String rateLabel;
  final String earnedLabel;
  final bool showEarned;
  final EmployeeShiftHistoryItem item;
  final List<EmployeeShiftHistoryItem> siblings;
  final VoidCallback onRequestCorrection;

  @override
  State<_MultiShiftSection> createState() => _MultiShiftSectionState();
}

class _MultiShiftSectionState extends State<_MultiShiftSection> {
  bool _payDetailsOpen = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final brand = BrandColors.of(context);
    final rowFace = presentShiftPayFromMap(
      _shiftPayMap(item),
      widget.siblings.map(_shiftPayMap).toList(),
    );
    final hasPay = item.historicalRateRequired ||
        item.dailyRateConflict ||
        item.rateUsed != null ||
        item.earned != null ||
        item.expectedSalaryPay != null ||
        item.payBasisUsed != null;
    final isIncomplete = item.status.toLowerCase() == 'incomplete';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8EEF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: EmployeeColors.textPrimary,
                  ),
                ),
              ),
              EmployeeStatusChip(
                label: widget.remark,
                color: statusColor(item.status),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _KvRow(
            label: item.status == 'holiday_paid' ? 'Scheduled start' : 'Time In',
            value: item.status == 'holiday_paid'
                ? (item.shiftStart ?? '—')
                : timeOnly(item.timeIn),
          ),
          const SizedBox(height: 4),
          _KvRow(
            label: item.status == 'holiday_paid' ? 'Scheduled end' : 'Time Out',
            value: item.status == 'holiday_paid'
                ? (item.shiftEnd ?? '—')
                : timeOnly(item.timeOut),
            emphasizeMissing:
                item.status != 'holiday_paid' && isIncomplete && item.timeOut == null,
          ),
          if (item.status == 'holiday_paid') ...[
            const SizedBox(height: 4),
            const _KvRow(label: 'Attendance', value: 'Not Worked'),
          ],
          const SizedBox(height: 4),
          _KvRow(
            label: 'Scheduled',
            value: '${item.shiftStart ?? '—'} – ${item.shiftEnd ?? '—'}',
          ),
          const SizedBox(height: 4),
          _KvRow(label: 'Hours Worked', value: widget.hoursLabel),
          if (hasPay) ...[
            const SizedBox(height: 4),
            _KvRow(label: 'Pay Basis', value: widget.payBasisLabel),
            const SizedBox(height: 4),
            _KvRow(label: 'Rate Used', value: widget.rateLabel),
            if (widget.showEarned) ...[
              const SizedBox(height: 4),
              _KvRow(
                label: presentShiftPayFromMap(
                  _shiftPayMap(item),
                  widget.siblings.map(_shiftPayMap).toList(),
                ).baseLabel,
                value: widget.earnedLabel,
                valueColor: const Color(0xFF16A34A),
                emphasize: true,
              ),
            ],
            if (rowFace.holidayPay != null) ...[
              const SizedBox(height: 4),
              _KvRow(
                label: 'Holiday Pay',
                value: money(rowFace.holidayPay!),
                valueColor: const Color(0xFF16A34A),
              ),
            ],
            if (!rowFace.hideShiftTotal && rowFace.shiftTotal != null) ...[
              const SizedBox(height: 4),
              _KvRow(
                label: 'Shift Total',
                value: money(rowFace.shiftTotal!),
                valueColor: const Color(0xFF16A34A),
                emphasize: true,
              ),
            ],
            const SizedBox(height: 4),
            InkWell(
              onTap: () => setState(() => _payDetailsOpen = !_payDetailsOpen),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(
                      'Pay Details',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: brand.primary,
                      ),
                    ),
                    Icon(
                      _payDetailsOpen
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: brand.primary,
                    ),
                  ],
                ),
              ),
            ),
            if (_payDetailsOpen)
              _EmployeePayDetails(item: item, siblings: widget.siblings),
          ],
          if (item.canRequestCorrection &&
              item.correctionStatus != 'approved' &&
              item.correctionStatus != 'pending') ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.onRequestCorrection,
                icon: Icon(
                  Icons.edit_calendar_outlined,
                  size: 16,
                  color: brand.primary,
                ),
                label: Text(
                  isIncomplete
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
    );
  }
}

class _HistoryCard extends StatefulWidget {
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

  @override
  State<_HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<_HistoryCard> {
  bool _payDetailsOpen = false;

  EmployeeShiftHistoryItem get item => widget.item;
  String get remark => widget.remark;

  static const _moneyGreen = Color(0xFF16A34A);

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

  String get _hoursWorkedLabel {
    final worked = item.workedMinutes;
    if (worked != null && worked > 0) {
      final hours = worked / 60.0;
      if ((hours - hours.round()).abs() < 0.05) {
        return '${hours.round()} hrs';
      }
      return '${hours.toStringAsFixed(1)} hrs';
    }
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

  bool get _hasPayProjection =>
      item.historicalRateRequired ||
      item.dailyRateConflict ||
      item.rateUsed != null ||
      item.earned != null ||
      item.expectedSalaryPay != null ||
      item.shiftNet != null ||
      item.payBasisUsed != null;

  String get _rateUsedLabel {
    if (item.historicalRateRequired || item.dailyRateConflict) {
      return 'Historical Rate Required';
    }
    if (item.rateUsed == null) return '—';
    final basis = (item.payBasisUsed ?? '').toLowerCase();
    final suffix = basis == 'hourly'
        ? '/hour'
        : basis == 'monthly'
            ? '/month'
            : '/day';
    return '${money(item.rateUsed!)}$suffix';
  }

  ShiftPayFace get _face => presentShiftPayFromMap(
        _shiftPayMap(item),
        [_shiftPayMap(item)],
      );

  String get _earnedLabel {
    if (item.historicalRateRequired || item.dailyRateConflict) {
      return 'Unresolved';
    }
    if (!_face.showEarned || _face.earned == null) return '—';
    return money(_face.earned!);
  }

  String get _shiftNetLabel {
    if (item.historicalRateRequired || item.dailyRateConflict) {
      return 'Unresolved';
    }
    if (_face.hideShiftTotal) return 'Included in this day';
    if (_face.shiftTotal == null) return '—';
    return money(_face.shiftTotal!);
  }

  @override
  Widget build(BuildContext context) {
    final statusColorValue = _statusColor;
    final brand = BrandColors.of(context);

    return Container(
      decoration: BoxDecoration(
        color: widget.highlighted ? const Color(0xFFFFFBEB) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.highlighted
              ? const Color(0xFFF59E0B)
              : EmployeeColors.border,
          width: widget.highlighted ? 1.3 : 1,
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
                _InfoBlock(
                  children: [
                    _KvRow(
                      label: item.status == 'holiday_paid'
                          ? 'Scheduled start'
                          : 'Time In',
                      value: item.status == 'holiday_paid'
                          ? (item.shiftStart ?? '—')
                          : timeOnly(item.timeIn),
                    ),
                    _KvRow(
                      label: item.status == 'holiday_paid'
                          ? 'Scheduled end'
                          : 'Time Out',
                      value: item.status == 'holiday_paid'
                          ? (item.shiftEnd ?? '—')
                          : timeOnly(item.timeOut),
                      emphasizeMissing: item.status != 'holiday_paid' &&
                          _isIncomplete &&
                          item.timeOut == null,
                    ),
                    if (item.status == 'holiday_paid')
                      const _KvRow(label: 'Attendance', value: 'Not Worked'),
                    _KvRow(label: 'Hours Worked', value: _hoursWorkedLabel),
                  ],
                ),
                if (_hasPayProjection) ...[
                  const SizedBox(height: 8),
                  _InfoBlock(
                    tint: item.historicalRateRequired || item.dailyRateConflict
                        ? const Color(0xFFFFFBEB)
                        : const Color(0xFFF0FDF4),
                    borderColor:
                        item.historicalRateRequired || item.dailyRateConflict
                            ? const Color(0xFFFDE68A)
                            : const Color(0xFFBBF7D0),
                    children: [
                      _KvRow(label: 'Rate Used', value: _rateUsedLabel),
                      if (_face.showEarned)
                        _KvRow(label: _face.baseLabel, value: _earnedLabel),
                      if (_face.holidayPay != null)
                        _KvRow(
                          label: 'Holiday Pay',
                          value: money(_face.holidayPay!),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Row(
                      children: [
                        const Text(
                          'SHIFT TOTAL',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: Color(0xFF065F46),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _shiftNetLabel,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: _moneyGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  InkWell(
                    onTap: () =>
                        setState(() => _payDetailsOpen = !_payDetailsOpen),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Text(
                            'Pay Details',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: brand.primary,
                            ),
                          ),
                          Icon(
                            _payDetailsOpen
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 18,
                            color: brand.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_payDetailsOpen) _EmployeePayDetails(item: item),
                ],
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
                            'Time Out missing. Submit a correction to complete this attendance.',
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
                      onPressed: widget.onRequestCorrection,
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

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.children,
    this.tint = const Color(0xFFF8FAFC),
    this.borderColor = const Color(0xFFE8EEF4),
  });

  final List<Widget> children;
  final Color tint;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: 5),
              const Divider(height: 1, color: Color(0xFFE8EEF4)),
              const SizedBox(height: 5),
            ],
            children[i],
          ],
        ],
      ),
    );
  }
}

class _KvRow extends StatelessWidget {
  const _KvRow({
    required this.label,
    required this.value,
    this.emphasizeMissing = false,
    this.valueColor,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasizeMissing;
  final Color? valueColor;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final showMissing = emphasizeMissing &&
        (value == '--' || value == '—' || value.trim().isEmpty);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: emphasize ? 12 : 11.5,
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
              color: EmployeeColors.textMuted,
            ),
          ),
        ),
        Text(
          showMissing ? 'Missing' : value,
          style: TextStyle(
            fontSize: emphasize ? 13 : 12,
            fontWeight: FontWeight.w700,
            color: showMissing
                ? const Color(0xFFD97706)
                : (valueColor ?? EmployeeColors.textPrimary),
          ),
        ),
      ],
    );
  }
}

class _EmployeePayDetails extends StatelessWidget {
  const _EmployeePayDetails({
    required this.item,
    this.siblings = const [],
  });

  final EmployeeShiftHistoryItem item;
  final List<EmployeeShiftHistoryItem> siblings;

  static const _moneyGreen = Color(0xFF16A34A);

  String get _payBasisLabel {
    final basis = (item.payBasisUsed ?? '').toLowerCase();
    if (basis == 'hourly') return 'Hourly';
    if (basis == 'monthly') return 'Monthly';
    if (basis == 'daily') return 'Daily';
    return basis.isEmpty ? '—' : basis;
  }

  String get _rateUsedLabel {
    if (item.historicalRateRequired || item.dailyRateConflict) {
      return 'Historical Rate Required';
    }
    if (item.rateUsed == null) return '—';
    final basis = (item.payBasisUsed ?? '').toLowerCase();
    final suffix = basis == 'hourly'
        ? '/hour'
        : basis == 'monthly'
            ? '/month'
            : '/day';
    return '${money(item.rateUsed!)}$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final unresolved =
        item.historicalRateRequired || item.dailyRateConflict;
    final face = presentShiftPayFromMap(
      _shiftPayMap(item),
      (siblings.isEmpty ? [item] : siblings).map(_shiftPayMap).toList(),
    );
    final additionalLines = buildAdditionalPayLines(
      overtimePay: item.overtimePay,
      overtimeMinutes: item.overtimeMinutes,
      restDayPremiumPay: face.restPay,
      holidayPay: face.holidayPay,
    );
    final deductionLines = buildDeductionLines(
      lateDeduction: item.lateDeduction,
      lateMinutes: item.lateMinutes,
      undertimeDeduction: item.undertimeDeduction,
      undertimeMinutes: item.undertimeMinutes,
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8EEF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('Pay summary'),
          _KvRow(label: 'Pay Basis', value: _payBasisLabel),
          _KvRow(label: 'Rate Used', value: _rateUsedLabel),
          if (face.showEarned && face.earned != null && !unresolved)
            _KvRow(label: face.baseLabel, value: money(face.earned!)),
          if (additionalLines.isNotEmpty) ...[
            const SizedBox(height: 8),
            const _SectionLabel('Additional pay'),
            for (final line in additionalLines)
              _KvRow(
                label: line.label,
                value: line.amount > 0 ? '+${money(line.amount)}' : '—',
                valueColor: line.amount > 0 ? _moneyGreen : null,
              ),
          ],
          if (deductionLines.isNotEmpty) ...[
            const SizedBox(height: 8),
            const _SectionLabel('Deductions'),
            for (final line in deductionLines)
              _KvRow(
                label: line.label,
                value: line.amount > 0 ? '-${money(line.amount)}' : '—',
                valueColor:
                    line.amount > 0 ? const Color(0xFFB91C1C) : null,
              ),
          ],
          if (item.historicalRateRequired || item.dailyRateConflict) ...[
            const SizedBox(height: 8),
            const _SectionLabel('Historical rate'),
            _KvRow(
              label: item.dailyRateConflict
                  ? 'Daily Rate Conflict'
                  : 'Historical Rate Required',
              value: 'Owner resolution needed',
              valueColor: const Color(0xFF92400E),
            ),
          ],
          const SizedBox(height: 8),
          const Divider(height: 1, color: Color(0xFFE8EEF4)),
          const SizedBox(height: 6),
          _KvRow(
            label: 'Shift Total',
            value: unresolved
                ? 'Unresolved'
                : (face.hideShiftTotal
                    ? 'Included in this day'
                    : (face.shiftTotal == null
                        ? '—'
                        : money(face.shiftTotal!))),
            valueColor: unresolved ? const Color(0xFF92400E) : _moneyGreen,
            emphasize: true,
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: Color(0xFF6B7280),
        ),
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
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (item.correctionReviewNote != null &&
              item.correctionReviewNote!.trim().isNotEmpty) ...[
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

Map<String, dynamic> _shiftPayMap(EmployeeShiftHistoryItem item) {
  return {
    'pay_basis_used': item.payBasisUsed,
    'status': item.status,
    'holiday_included_in_shift_net': item.holidayIncludedInShiftNet,
    'historical_rate_required': item.historicalRateRequired,
    'expected_salary_pay': item.expectedSalaryPay,
    'earned': item.earned,
    'holiday_pay': item.holidayPay,
    'rest_day_premium_pay': item.restDayPremiumPay,
    'day_holiday_pay': item.dayHolidayPay,
    'day_rest_day_pay': item.dayRestDayPay,
    'day_entitlement': item.dayEntitlement,
    'shift_net': item.shiftNet,
    'reconciled_shift_total': item.reconciledShiftTotal,
    'late_deduction': item.lateDeduction,
  };
}
