import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/utils/business_time.dart';
import 'package:aroll_mobile/core/utils/format.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_ui.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:aroll_mobile/presentation/shared/shift_history_grouping.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// Owner Shift History — day rows from authoritative payslip attendance data.
class OwnerShiftHistoryScreen extends StatefulWidget {
  const OwnerShiftHistoryScreen({super.key});

  @override
  State<OwnerShiftHistoryScreen> createState() =>
      _OwnerShiftHistoryScreenState();
}

class _OwnerShiftHistoryScreenState extends State<OwnerShiftHistoryScreen> {
  final _repo = sl<OwnerRepository>();
  final _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  DateTime _asOf = DateTime.now();
  String _query = '';
  String? _periodStart;
  String? _periodEnd;
  String? _timezone;
  List<Map<String, dynamic>> _items = const [];
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _repo.shiftHistory(asOf: _asOf);
      if (!mounted) return;
      setState(() {
        _periodStart = data['period_start'] as String?;
        _periodEnd = data['period_end'] as String?;
        _timezone = data['timezone'] as String?;
        _items = (data['items'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load shift history. Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _pickAsOf() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _asOf,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Select a date in the pay period',
    );
    if (picked == null) return;
    setState(() => _asOf = picked);
    await _load();
  }

  Future<void> _resolveHistoricalRate(Map<String, dynamic> item) async {
    final dailyConflict = item['daily_rate_conflict'] == true;
    final recordId = '${item['attendance_record_id'] ?? ''}';
    final employeeId = '${item['employee_id'] ?? ''}';
    final workDate = '${item['date'] ?? ''}';
    if (dailyConflict) {
      if (employeeId.isEmpty || workDate.isEmpty) return;
    } else if (recordId.isEmpty) {
      return;
    }

    final basisController = TextEditingController(text: 'daily');
    final rateController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        String payBasis = 'daily';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                dailyConflict
                    ? 'Resolve Daily rate for this day'
                    : 'Set historical pay rate',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dailyConflict
                        ? 'Multiple Daily shifts on this date have different '
                            'historical rates. Choose one Daily rate for the '
                            'workday. Hourly shifts on the same date are unchanged.'
                        : 'Enter the rate that applied when this attendance was '
                            'completed. The employee\'s current rate is not used.',
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                  if (!dailyConflict) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: payBasis,
                      decoration:
                          const InputDecoration(labelText: 'Pay basis'),
                      items: const [
                        DropdownMenuItem(
                          value: 'daily',
                          child: Text('Daily'),
                        ),
                        DropdownMenuItem(
                          value: 'hourly',
                          child: Text('Hourly'),
                        ),
                        DropdownMenuItem(
                          value: 'monthly',
                          child: Text('Monthly'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          payBasis = value;
                          basisController.text = value;
                        });
                      },
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Pay basis is fixed to Daily for workday resolution.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: rateController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: dailyConflict || payBasis == 'daily'
                          ? 'Daily rate'
                          : payBasis == 'hourly'
                              ? 'Hourly rate'
                              : 'Monthly salary',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Confirm'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true || !mounted) return;
    final amount = double.tryParse(rateController.text.trim());
    if (amount == null || amount <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a positive rate.')),
      );
      return;
    }
    try {
      if (dailyConflict) {
        await _repo.resolveDailyWorkdayRate(
          employeeId: employeeId,
          workDate: workDate,
          dailyRate: amount,
        );
      } else {
        final payBasis = basisController.text;
        await _repo.resolveHistoricalRate(
          recordId: recordId,
          payBasis: payBasis,
          dailyRate: payBasis == 'daily' ? amount : null,
          hourlyRate: payBasis == 'hourly' ? amount : null,
          monthlySalary: payBasis == 'monthly' ? amount : null,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Historical pay rate saved.')),
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save historical rate.')),
      );
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_query.isEmpty) return _items;
    return _items.where((item) {
      final name = '${item['employee_name'] ?? ''}'.toLowerCase();
      final status = '${item['status'] ?? ''}'.toLowerCase();
      final shift = '${item['shift_name'] ?? ''}'.toLowerCase();
      return name.contains(_query) ||
          status.contains(_query) ||
          shift.contains(_query);
    }).toList();
  }

  Map<String, List<Map<String, dynamic>>> get _groupedByDate {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final item in _filtered) {
      final key = '${item['date'] ?? 'Unknown'}';
      map.putIfAbsent(key, () => []).add(item);
    }
    return map;
  }

  String _statusLabelForItem(Map<String, dynamic> item) {
    final status = item['status'];
    if (status == 'holiday_paid' || status == 'on_leave') {
      return shiftHistoryStatusLabelFromMap(item);
    }
    return _statusLabel(status as String?);
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'late':
        return 'Late';
      case 'absent':
        return 'Absent';
      case 'in_progress':
        return 'In progress';
      case 'complete':
        return 'Present';
      case 'on_leave':
        return 'On leave';
      case 'holiday_paid':
        return 'Paid Holiday — Not Worked';
      case 'incomplete':
        return 'Incomplete';
      default:
        return (status ?? '—').replaceAll('_', ' ');
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'complete':
      case 'holiday_paid':
        return const Color(0xFF15803D);
      case 'late':
        return const Color(0xFFB45309);
      case 'absent':
        return const Color(0xFFB91C1C);
      case 'incomplete':
      case 'in_progress':
        return const Color(0xFF1D4ED8);
      case 'on_leave':
        return const Color(0xFF6D28D9);
      default:
        return const Color(0xFF4B5563);
    }
  }

  String? get _displayTimeZone =>
      sl<AppState>().session?.timezone ?? _timezone;

  String _formatClock(String? iso) {
    return formatBusinessAttendanceTimeIso(
      iso,
      timeZone: _displayTimeZone,
      fallback: '—',
    );
  }

  String _formatHours(dynamic hoursValue, dynamic minutesValue) {
    final minutes = (minutesValue is num)
        ? minutesValue.round()
        : (((hoursValue is num) ? hoursValue.toDouble() : 0.0) * 60).round();
    if (minutes <= 0) return '0h';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return '${h}h';
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  String _formatDateHeader(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    return DateFormat('EEE, MMM d, yyyy').format(parsed);
  }

  String _periodLabel() {
    if (_periodStart == null || _periodEnd == null) return 'Current pay period';
    final start = DateTime.tryParse(_periodStart!);
    final end = DateTime.tryParse(_periodEnd!);
    if (start == null || end == null) {
      return '$_periodStart â€“ $_periodEnd';
    }
    final fmt = DateFormat('MMM d, yyyy');
    return '${fmt.format(start)} â€“ ${fmt.format(end)}';
  }

  String _rowKey(Map<String, dynamic> item) =>
      '${item['employee_id']}_${item['date']}_${item['shift_name']}_${item['status']}';

  @override
  Widget build(BuildContext context) {
    final groups = _groupedByDate;
    final dates = groups.keys.toList();

    return OwnerShell(
      selectedIndex: 1,
      title: 'Shift History',
      showBackButton: true,
      onBack: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/owner/attendance');
        }
      },
      child: _loading
          ? appLoadingView(cardCount: 4)
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF6B7280)),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          style: SetupUi.primaryButtonOf(context),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      _PeriodBanner(
                        label: _periodLabel(),
                        onPick: _pickAsOf,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search employee, status, or shift',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 22,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFFE5E7EB),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFFE5E7EB),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: SetupUi.navyOf(context),
                              width: 1.2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (dates.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Column(
                            children: [
                              Icon(
                                Icons.history_toggle_off_rounded,
                                size: 40,
                                color: Color(0xFF9CA3AF),
                              ),
                              SizedBox(height: 12),
                              Text(
                                'No shift history for this pay period.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF374151),
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Try another date within a different pay period.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        for (final date in dates) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8, top: 4),
                            child: Text(
                              _formatDateHeader(date),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF6B7280),
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          for (final block in buildOwnerDayBlocks(
                            rows: groups[date]!,
                          )) ...[
                            if (block is List<Map<String, dynamic>>) ...[
                              _OwnerMultiShiftCard(
                                items: block,
                                expanded: _expanded.contains(
                                  'multi_${block.first['employee_id']}_${block.first['date']}',
                                ),
                                statusLabelFor: _statusLabel,
                                statusColorFor: _statusColor,
                                formatClock: _formatClock,
                                formatHours: _formatHours,
                                onToggle: () {
                                  final key =
                                      'multi_${block.first['employee_id']}_${block.first['date']}';
                                  setState(() {
                                    if (_expanded.contains(key)) {
                                      _expanded.remove(key);
                                    } else {
                                      _expanded.add(key);
                                    }
                                  });
                                },
                                onResolve: _resolveHistoricalRate,
                              ),
                              const SizedBox(height: 10),
                            ] else ...[
                              Builder(
                                builder: (context) {
                                  final item =
                                      block as Map<String, dynamic>;
                                  return Column(
                                    children: [
                                      _ShiftHistoryCard(
                                        item: item,
                                        expanded: _expanded
                                            .contains(_rowKey(item)),
                                        statusLabel: _statusLabelForItem(item),
                                        statusColor: _statusColor(
                                          item['status'] as String?,
                                        ),
                                        timeInLabel: _formatClock(
                                          item['status'] == 'holiday_paid'
                                              ? item['scheduled_start'] as String?
                                              : item['time_in'] as String?,
                                        ),
                                        timeOutLabel: _formatClock(
                                          item['status'] == 'holiday_paid'
                                              ? item['scheduled_end'] as String?
                                              : item['time_out'] as String?,
                                        ),
                                        hoursLabel: _formatHours(
                                          item['hours_worked'],
                                          item['worked_minutes'],
                                        ),
                                        rateLabel: formatSalaryRate(
                                          payBasis:
                                              item['pay_basis'] as String?,
                                          dailyRate:
                                              item['daily_rate'] as num?,
                                          hourlyRate:
                                              item['hourly_rate'] as num?,
                                          monthlySalary:
                                              item['monthly_salary'] as num?,
                                        ),
                                        onToggle: () {
                                          final key = _rowKey(item);
                                          setState(() {
                                            if (_expanded.contains(key)) {
                                              _expanded.remove(key);
                                            } else {
                                              _expanded.add(key);
                                            }
                                          });
                                        },
                                        onResolve: () =>
                                            _resolveHistoricalRate(item),
                                      ),
                                      const SizedBox(height: 10),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ],
                        ],
                    ],
                  ),
                ),
    );
  }
}

class _PeriodBanner extends StatelessWidget {
  const _PeriodBanner({required this.label, required this.onPick});

  final String label;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.date_range_rounded,
                  size: 20,
                  color: SetupUi.navyOf(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pay period',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF9CA3AF),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OwnerMultiShiftCard extends StatelessWidget {
  const _OwnerMultiShiftCard({
    required this.items,
    required this.expanded,
    required this.statusLabelFor,
    required this.statusColorFor,
    required this.formatClock,
    required this.formatHours,
    required this.onToggle,
    required this.onResolve,
  });

  final List<Map<String, dynamic>> items;
  final bool expanded;
  final String Function(String?) statusLabelFor;
  final Color Function(String?) statusColorFor;
  final String Function(String?) formatClock;
  final String Function(dynamic, dynamic) formatHours;
  final VoidCallback onToggle;
  final void Function(Map<String, dynamic>) onResolve;

  static const _moneyGreen = Color(0xFF16A34A);

  @override
  Widget build(BuildContext context) {
    final name = '${items.first['employee_name'] ?? 'Employee'}';
    final dayTotal = historyDayTotalFromMaps(items);
    final finalLabel = dayTotal.unresolved
        ? 'Unresolved'
        : (dayTotal.total == null ? '—' : formatPeso(dayTotal.total!));
    String? holidayName;
    for (final item in items) {
      final value = item['holiday_name'];
      if (value is String && value.isNotEmpty) {
        holidayName = value;
        break;
      }
    }
    String? equation;
    if (!dayTotal.unresolved && dayTotal.total != null) {
      equation = historyDayEquationFromMaps(
        items,
        dayTotal.total!,
        formatPeso,
      );
    }

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
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
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${items.length} shifts on this date',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF4B5563),
                          ),
                        ),
                        if (holidayName != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            holidayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0F766E),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${items.length} Shifts',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: const Color(0xFF9CA3AF),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text(
                    'DAY TOTAL',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                      color: Color(0xFF065F46),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    finalLabel,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _moneyGreen,
                    ),
                  ),
                ],
              ),
              if (expanded) ...[
                const SizedBox(height: 12),
                if (dateLevelPayFromMaps(items) case final datePay?) ...[
                  if (datePay.dailyEntitlement != null) ...[
                    _OwnerKv(
                      label: 'Daily Entitlement',
                      value: formatPeso(datePay.dailyEntitlement!),
                      valueColor: const Color(0xFF16A34A),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _OwnerMultiShiftSection(
                    index: i,
                    item: items[i],
                    siblings: items,
                    formatClock: formatClock,
                    statusLabel: items[i]['status'] == 'holiday_paid' ||
                            items[i]['status'] == 'on_leave'
                        ? shiftHistoryStatusLabelFromMap(items[i])
                        : statusLabelFor(items[i]['status'] as String?),
                    statusColor: statusColorFor(items[i]['status'] as String?),
                    timeInLabel: formatClock(
                      (items[i]['status'] == 'holiday_paid'
                              ? items[i]['scheduled_start']
                              : items[i]['time_in'])
                          as String?,
                    ),
                    timeOutLabel: formatClock(
                      (items[i]['status'] == 'holiday_paid'
                              ? items[i]['scheduled_end']
                              : items[i]['time_out'])
                          as String?,
                    ),
                    hoursLabel: formatHours(
                      items[i]['hours_worked'],
                      items[i]['worked_minutes'],
                    ),
                    onResolve: () => onResolve(items[i]),
                  ),
                ],
                if (dateLevelAdditionalPayFromMaps(items) case final extra
                    when extra.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _OwnerSectionTitle('Additional pay'),
                        for (final line in extra)
                          _OwnerKv(
                            label: line.label,
                            value: '+${formatPeso(line.amount)}',
                            valueColor: const Color(0xFF16A34A),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(12),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _OwnerMultiShiftSection extends StatelessWidget {
  const _OwnerMultiShiftSection({
    required this.index,
    required this.item,
    required this.siblings,
    required this.statusLabel,
    required this.statusColor,
    required this.timeInLabel,
    required this.timeOutLabel,
    required this.hoursLabel,
    required this.formatClock,
    required this.onResolve,
  });

  final int index;
  final Map<String, dynamic> item;
  final List<Map<String, dynamic>> siblings;
  final String Function(String?) formatClock;
  final String statusLabel;
  final Color statusColor;
  final String timeInLabel;
  final String timeOutLabel;
  final String hoursLabel;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    final shift = '${item['shift_name'] ?? ''}'.trim();
    final historicalRequired = item['historical_rate_required'] == true ||
        '${item['payroll_status'] ?? ''}' == 'historical_rate_required';
    final rateUsed = item['rate_used'];
    final payBasisUsed = '${item['pay_basis_used'] ?? ''}';
    final displayRateLabel = historicalRequired
        ? 'Historical rate required'
        : (rateUsed != null
            ? '${formatPeso(rateUsed as num)}${payBasisUsed == 'hourly' ? '/hour' : payBasisUsed == 'monthly' ? '/month' : '/day'}'
            : '—');
    final payBasisLabel = payBasisUsed == 'hourly'
        ? 'Hourly'
        : payBasisUsed == 'monthly'
            ? 'Monthly'
            : payBasisUsed == 'daily'
                ? 'Daily'
                : (payBasisUsed.isEmpty ? '—' : payBasisUsed);
    final face = presentShiftPayFromMap(item, siblings);
    final additionalLines = buildAdditionalPayLines(
      overtimePay: item['overtime_pay'],
      overtimeMinutes: item['overtime_minutes'],
      restDayPremiumPay: face.restPay,
      holidayPay: face.holidayPay,
    );
    final deductionLines = buildDeductionLines(
      lateDeduction: item['late_deduction'],
      lateMinutes: item['late_minutes'],
      undertimeDeduction: item['undertime_deduction'],
      undertimeMinutes: item['undertime_minutes'],
    );

    String moneyOrDash(Object? value) {
      if (historicalRequired) return 'Unresolved';
      if (value == null) return '—';
      return formatPeso(value as num);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  shiftIndexLabel(index, shift.isEmpty ? null : shift),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _OwnerKv(
            label: item['status'] == 'holiday_paid' ? 'Scheduled start' : 'Time In',
            value: timeInLabel,
          ),
          _OwnerKv(
            label: item['status'] == 'holiday_paid' ? 'Scheduled end' : 'Time Out',
            value: timeOutLabel,
          ),
          if (item['status'] == 'holiday_paid')
            const _OwnerKv(label: 'Attendance', value: 'Not Worked'),
          _OwnerKv(label: 'Hours', value: hoursLabel),
          _OwnerKv(
            label: 'Scheduled',
            value:
                '${formatClock(item['scheduled_start'] as String?)} → ${formatClock(item['scheduled_end'] as String?)}',
          ),
          _OwnerKv(label: 'Pay Basis', value: payBasisLabel),
          _OwnerKv(label: 'Rate Used', value: displayRateLabel),
          if (face.showEarned)
            _OwnerKv(
              label: face.baseLabel,
              value: moneyOrDash(face.earned),
              valueColor: const Color(0xFF16A34A),
            ),
          if (additionalLines.isNotEmpty) ...[
            const SizedBox(height: 6),
            const _OwnerSectionTitle('Additional pay'),
            for (final line in additionalLines)
              _OwnerKv(
                label: line.label,
                value: line.amount > 0
                    ? '+${formatPeso(line.amount)}'
                    : '—',
                valueColor:
                    line.amount > 0 ? const Color(0xFF16A34A) : null,
              ),
          ],
          if (deductionLines.isNotEmpty) ...[
            const SizedBox(height: 6),
            const _OwnerSectionTitle('Deductions'),
            for (final line in deductionLines)
              _OwnerKv(
                label: line.label,
                value: line.amount > 0
                    ? '-${formatPeso(line.amount)}'
                    : '—',
                valueColor:
                    line.amount > 0 ? const Color(0xFFB91C1C) : null,
              ),
          ],
          if (!face.hideShiftTotal) ...[
            const SizedBox(height: 8),
            _OwnerKv(
              label: 'Shift Total',
              value: moneyOrDash(face.shiftTotal),
              valueColor: const Color(0xFF16A34A),
            ),
          ],
          if (historicalRequired) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onResolve,
                child: Text(
                  item['daily_rate_conflict'] == true
                      ? 'Resolve Daily rate for this day'
                      : 'Resolve historical rate',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShiftHistoryCard extends StatelessWidget {
  const _ShiftHistoryCard({
    required this.item,
    required this.expanded,
    required this.statusLabel,
    required this.statusColor,
    required this.timeInLabel,
    required this.timeOutLabel,
    required this.hoursLabel,
    required this.rateLabel,
    required this.onToggle,
    required this.onResolve,
  });

  final Map<String, dynamic> item;
  final bool expanded;
  final String statusLabel;
  final Color statusColor;
  final String timeInLabel;
  final String timeOutLabel;
  final String hoursLabel;
  final String rateLabel;
  final VoidCallback onToggle;
  final VoidCallback onResolve;

  static const _moneyGreen = Color(0xFF16A34A);

  @override
  Widget build(BuildContext context) {
    final name = '${item['employee_name'] ?? 'Employee'}';
    final shift = '${item['shift_name'] ?? ''}'.trim();
    final dateLabel = '${item['date'] ?? ''}';
    final historicalRequired = item['historical_rate_required'] == true ||
        '${item['payroll_status'] ?? ''}' == 'historical_rate_required';
    final dailyConflict = item['daily_rate_conflict'] == true;
    final rateUsed = item['rate_used'];
    final payBasisUsed = '${item['pay_basis_used'] ?? ''}';
    final displayRateLabel = historicalRequired
        ? 'Historical rate required'
        : (rateUsed != null
            ? '${formatPeso(rateUsed as num)}${payBasisUsed == 'hourly' ? '/hour' : payBasisUsed == 'monthly' ? '/month' : '/day'}'
            : rateLabel);
    final payBasisLabel = payBasisUsed == 'hourly'
        ? 'Hourly'
        : payBasisUsed == 'monthly'
            ? 'Monthly'
            : payBasisUsed == 'daily'
                ? 'Daily'
                : (payBasisUsed.isEmpty ? '—' : payBasisUsed);
    final face = presentShiftPayFromMap(item, [item]);
    final additionalLines = buildAdditionalPayLines(
      overtimePay: item['overtime_pay'],
      overtimeMinutes: item['overtime_minutes'],
      restDayPremiumPay: face.restPay,
      holidayPay: face.holidayPay,
    );
    final deductionLines = buildDeductionLines(
      lateDeduction: item['late_deduction'],
      lateMinutes: item['late_minutes'],
      undertimeDeduction: item['undertime_deduction'],
      undertimeMinutes: item['undertime_minutes'],
    );
    final scheduledStart = item['scheduled_start'] as String?;
    final scheduledEnd = item['scheduled_end'] as String?;
    final scheduledLabel = (scheduledStart != null || scheduledEnd != null)
        ? '${_shortClock(scheduledStart)} → ${_shortClock(scheduledEnd)}'
        : '—';

    String moneyOrDash(Object? value) {
      if (historicalRequired) return 'Unresolved';
      if (value == null) return '—';
      return formatPeso(value as num);
    }

    final collapsedNet = historicalRequired
        ? 'Unresolved'
        : (face.shiftTotal == null ? '—' : formatPeso(face.shiftTotal!));

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
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
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                            height: 1.25,
                          ),
                        ),
                        if (shift.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            shift,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                              height: 1.25,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 22,
                    color: const Color(0xFF9CA3AF),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 16,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            timeInLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            '→',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                        Flexible(
                          child: Text(
                            timeOutLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          hoursLabel,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF374151),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          collapsedNet,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _moneyGreen,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (expanded) ...[
                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
                const SizedBox(height: 10),
                const _OwnerSectionTitle('Shift summary'),
                _OwnerKv(label: 'Employee', value: name),
                if (dateLabel.isNotEmpty)
                  _OwnerKv(label: 'Date', value: dateLabel),
                _OwnerKv(label: 'Status', value: statusLabel),
                _OwnerKv(label: 'Scheduled', value: scheduledLabel),
                _OwnerKv(
                  label: item['status'] == 'holiday_paid' ? 'Scheduled' : 'Actual',
                  value: '$timeInLabel → $timeOutLabel',
                ),
                if (item['status'] == 'holiday_paid')
                  const _OwnerKv(label: 'Attendance', value: 'Not Worked'),
                _OwnerKv(label: 'Hours Worked', value: hoursLabel),
                const SizedBox(height: 10),
                const _OwnerSectionTitle('Pay summary'),
                _OwnerKv(label: 'Pay Basis', value: payBasisLabel),
                _OwnerKv(
                  label: 'Rate Used',
                  value: displayRateLabel,
                ),
                if (face.showEarned)
                  _OwnerKv(label: face.baseLabel, value: moneyOrDash(face.earned)),
                if (additionalLines.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const _OwnerSectionTitle('Additional pay'),
                  for (final line in additionalLines)
                    _OwnerKv(
                      label: line.label,
                      value: line.amount > 0
                          ? '+${formatPeso(line.amount)}'
                          : '—',
                      valueColor: line.amount > 0 ? _moneyGreen : null,
                    ),
                ],
                if (deductionLines.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const _OwnerSectionTitle('Deductions'),
                  for (final line in deductionLines)
                    _OwnerKv(
                      label: line.label,
                      value: line.amount > 0
                          ? '-${formatPeso(line.amount)}'
                          : '—',
                      valueColor: line.amount > 0
                          ? const Color(0xFFB91C1C)
                          : null,
                    ),
                ],
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(12),
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
                        collapsedNet,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _moneyGreen,
                        ),
                      ),
                    ],
                  ),
                ),
                if (historicalRequired) ...[
                  const SizedBox(height: 10),
                  const _OwnerSectionTitle('Historical rate'),
                  _OwnerKv(
                    label: dailyConflict
                        ? 'Daily Rate Conflict'
                        : 'Historical Rate Required',
                    value: 'Owner resolution needed',
                    valueColor: const Color(0xFF92400E),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: onResolve,
                      child: Text(
                        dailyConflict
                            ? 'Resolve Daily rate for this day'
                            : 'Resolve historical rate',
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _shortClock(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    return DateFormat('h:mm a').format(parsed.toLocal());
  }
}

class _OwnerSectionTitle extends StatelessWidget {
  const _OwnerSectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
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

class _OwnerKv extends StatelessWidget {
  const _OwnerKv({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: valueColor ?? const Color(0xFF111827),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
