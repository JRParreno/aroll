import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/theme/business_brand_theme.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/tenant_mode.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/owner/payroll/owner_payroll_format.dart';
import 'package:aroll_mobile/presentation/owner/payroll/pay_period_navigation.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OwnerPayrollListScreen extends StatefulWidget {
  const OwnerPayrollListScreen({super.key});

  @override
  State<OwnerPayrollListScreen> createState() => _OwnerPayrollListScreenState();
}

class _OwnerPayrollListScreenState extends State<OwnerPayrollListScreen> {
  final _repo = sl<OwnerRepository>();

  bool _loading = true;
  bool _finalizing = false;
  String? _error;
  String? _finalizeMessage;
  String _selectedEmployeeId = '';
  late DateTime _asOf;
  String? _periodStart;
  String? _periodEnd;
  String? _payrollStatus;
  List<Map<String, dynamic>> _items = const [];
  List<Map<String, dynamic>> _employees = const [];
  Map<String, String> _profileImages = const {};
  int _incompleteCount = 0;
  int _unresolvedHistoricalCount = 0;
  bool _canFinalize = false;
  bool _isFinalized = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _asOf = DateTime(now.year, now.month, now.day);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repo.payroll(asOf: _asOf),
        _repo.employees(),
      ]);
      final payroll = results[0] as Map<String, dynamic>;
      final employees = results[1] as List<Map<String, dynamic>>;
      final images = <String, String>{};
      for (final employee in employees) {
        final id = '${employee['id']}';
        final image = employee['profile_image_url'] as String?;
        if (image != null && image.isNotEmpty) {
          images[id] = image;
        }
      }
      if (!mounted) return;
      setState(() {
        _items = (payroll['items'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList();
        _periodStart = payroll['period_start'] as String?;
        _periodEnd = payroll['period_end'] as String?;
        _payrollStatus = payroll['payroll_status'] as String?;
        _employees = employees;
        _profileImages = images;
        _incompleteCount =
            (payroll['incomplete_attendance_count'] as num?)?.toInt() ?? 0;
        _unresolvedHistoricalCount =
            (payroll['unresolved_historical_rate_count'] as num?)?.toInt() ??
                0;
        _canFinalize = payroll['can_finalize'] == true;
        _isFinalized = payroll['is_finalized'] == true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load payroll summary.';
      });
    }
  }

  Future<void> _finalize() async {
    if (_finalizing ||
        _isFinalized ||
        _incompleteCount > 0 ||
        _unresolvedHistoricalCount > 0 ||
        !_canFinalize) {
      return;
    }
    setState(() {
      _finalizing = true;
      _finalizeMessage = null;
    });
    try {
      await _repo.finalizePayroll(asOf: _asOf);
      if (!mounted) return;
      setState(() {
        _finalizing = false;
        _finalizeMessage = 'Payroll period finalized successfully.';
      });
      await _load();
    } catch (e) {
      if (!mounted) return;
      String message =
          'Payroll cannot be finalized. Resolve attendance issues first.';
      try {
        final response = (e as dynamic).response?.data;
        if (response is Map && response['detail'] is Map) {
          final msg = '${response['detail']['message'] ?? ''}';
          if (msg.isNotEmpty) message = msg;
        }
      } catch (_) {}
      setState(() {
        _finalizing = false;
        _finalizeMessage = message;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredItems {
    return _items.where((item) {
      if (_selectedEmployeeId.isNotEmpty &&
          '${item['employee_id']}' != _selectedEmployeeId) {
        return false;
      }
      return true;
    }).toList();
  }

  void _openPreviousPeriod() {
    final start = parsePayrollIsoDate(_periodStart);
    if (start == null) return;
    setState(() => _asOf = previousPeriodAsOf(start));
    _load();
  }

  void _openNextPeriod() {
    final end = parsePayrollIsoDate(_periodEnd);
    if (end == null || !canOpenNextPayPeriod(_payrollStatus)) return;
    setState(() => _asOf = nextPeriodAsOf(end));
    _load();
  }

  Future<void> _jumpToDate() async {
    final today = DateTime.now();
    final last = DateTime(today.year, today.month, today.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _asOf.isAfter(last) ? last : _asOf,
      firstDate: DateTime(2000),
      lastDate: last,
    );
    if (picked == null) return;
    setState(() => _asOf = DateTime(picked.year, picked.month, picked.day));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return OwnerShell(
      selectedIndex: 0,
      showBackButton: true,
      title: sl<AppState>().session?.isDemo == true
          ? TenantModeCopy.samplePayroll
          : 'Payroll Summary',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          constraints: const BoxConstraints(
            minWidth: AppSizes.minTap,
            minHeight: AppSizes.minTap,
          ),
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded, size: AppSizes.iconLg),
        ),
      ],
      child: _loading
          ? appLoadingView(cardCount: 4)
          : _error != null
              ? AppErrorState(
                  message: _error!,
                  onRetry: _load,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      _FilterCard(
                        employees: _employees,
                        selectedEmployeeId: _selectedEmployeeId,
                        periodStart: _periodStart,
                        periodEnd: _periodEnd,
                        canGoNext: canOpenNextPayPeriod(_payrollStatus),
                        onEmployeeChanged: (value) =>
                            setState(() => _selectedEmployeeId = value ?? ''),
                        onPrevious: _periodStart == null
                            ? null
                            : _openPreviousPeriod,
                        onNext: canOpenNextPayPeriod(_payrollStatus)
                            ? _openNextPeriod
                            : null,
                        onJumpToDate: _jumpToDate,
                      ),
                      const SizedBox(height: 14),
                      if (_incompleteCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFFDE68A)),
                            ),
                            child: Text(
                              'Payroll cannot be finalized because there are '
                              'employees with incomplete attendance '
                              '($_incompleteCount). Resolve all attendance '
                              'corrections first. You can still preview payslips.',
                              style: const TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF92400E),
                              ),
                            ),
                          ),
                        )
                      else if (_unresolvedHistoricalCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFFDE68A)),
                            ),
                            child: Text(
                              'Payroll cannot be finalized because a completed '
                              'attendance has an unresolved historical pay rate '
                              '($_unresolvedHistoricalCount). Resolve the '
                              'historical rate before finalizing.',
                              style: const TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF92400E),
                              ),
                            ),
                          ),
                        ),
                      if (_finalizeMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            _finalizeMessage!,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: (_incompleteCount > 0 ||
                                      _unresolvedHistoricalCount > 0)
                                  ? const Color(0xFFB91C1C)
                                  : const Color(0xFF166534),
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: (_finalizing ||
                                    _isFinalized ||
                                    _incompleteCount > 0 ||
                                    _unresolvedHistoricalCount > 0 ||
                                    !_canFinalize)
                                ? null
                                : _finalize,
                            child: Text(
                              _finalizing
                                  ? 'Finalizing…'
                                  : _isFinalized
                                      ? (sl<AppState>().session?.isDemo == true
                                          ? 'Sample finalized'
                                          : 'Payroll Finalized')
                                      : (sl<AppState>().session?.isDemo == true
                                          ? 'Finalize sample payroll'
                                          : 'Finalize Payroll'),
                            ),
                          ),
                        ),
                      ),
                      if (_filteredItems.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            '${_filteredItems.length} employee'
                            '${_filteredItems.length == 1 ? '' : 's'}',
                            style: appMutedStyle().copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (_filteredItems.isEmpty)
                        OwnerEmptyState(
                          _items.isEmpty
                              ? 'No payroll records for this pay period.'
                              : 'No employees match this filter.',
                          description: _items.isEmpty
                              ? 'This period has no payroll records yet.'
                              : 'Try another employee. The selected pay period stays the same.',
                          icon: Icons.payments_outlined,
                        )
                      else
                        ..._filteredItems.map(
                          (item) => _EmployeePayrollCard(
                            item: item,
                            profileImageUrl:
                                _profileImages['${item['employee_id']}'],
                            onViewDetails: () => context.push(
                              '/owner/payroll/${item['employee_id']}'
                              '?as_of=${_dateParam(_asOf)}',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

String _dateParam(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

class _FilterCard extends StatelessWidget {
  const _FilterCard({
    required this.employees,
    required this.selectedEmployeeId,
    required this.periodStart,
    required this.periodEnd,
    required this.canGoNext,
    required this.onEmployeeChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onJumpToDate,
  });

  final List<Map<String, dynamic>> employees;
  final String selectedEmployeeId;
  final String? periodStart;
  final String? periodEnd;
  final bool canGoNext;
  final ValueChanged<String?> onEmployeeChanged;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onJumpToDate;

  @override
  Widget build(BuildContext context) {
    return OwnerCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: BrandColors.of(context).toneWell,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.filter_list_rounded,
                  color: BrandColors.of(context).tonePrimary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Filters', style: appSectionTitleStyle()),
                    Text(
                      'Choose employee and pay period',
                      style: appMutedStyle().copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: selectedEmployeeId,
            isExpanded: true,
            isDense: true,
            decoration: appInputDecoration(
              hintText: 'Select employee',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
            ),
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('All employees'),
              ),
              ...employees.map(
                (employee) => DropdownMenuItem(
                  value: '${employee['id']}',
                  child: Text('${employee['full_name']}'),
                ),
              ),
            ],
            onChanged: (value) => onEmployeeChanged(value ?? ''),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPrevious,
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: const Text('Previous'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canGoNext ? onNext : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                  label: const Text('Next'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onJumpToDate,
              icon: const Icon(Icons.calendar_month_outlined),
              label: const Text('Jump to date'),
            ),
          ),
          if (periodStart != null && periodEnd != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: BrandColors.of(context).toneWell,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.date_range_outlined,
                    size: 16,
                    color: BrandColors.of(context).tonePrimary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Period ${ownerPayrollShortDate(periodStart)} – ${ownerPayrollShortDate(periodEnd)}',
                      style: appMutedStyle().copyWith(
                        fontSize: 12,
                        color: BrandColors.of(context).toneButton,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmployeePayrollCard extends StatelessWidget {
  const _EmployeePayrollCard({
    required this.item,
    required this.onViewDetails,
    this.profileImageUrl,
  });

  final Map<String, dynamic> item;
  final VoidCallback onViewDetails;
  final String? profileImageUrl;

  @override
  Widget build(BuildContext context) {
    final netPay = ownerPayrollMoney(
      parsePayrollAmount(item['final_net_pay'] ?? item['total_salary']),
    );

    return OwnerCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.zero,
      onTap: onViewDetails,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    EmployeeAvatar(
                      imageUrl: profileImageUrl,
                      name: '${item['employee_name'] ?? 'Employee'}',
                      size: 48,
                      backgroundColor: BrandColors.of(context).toneWell,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item['employee_name'] ?? 'Employee'}',
                            style: appSectionTitleStyle(),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${item['position_title'] ?? 'Employee'}',
                            style: appMutedStyle().copyWith(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _PayrollMetricRow(
                  icon: Icons.calendar_month_outlined,
                  label: 'Worked Days',
                  value: '${item['worked_days'] ?? 0} Days',
                ),
                _PayrollMetricRow(
                  icon: Icons.payments_outlined,
                  label: ownerSalaryRateLabel(),
                  value: ownerSalaryRate(item),
                ),
                _PayrollMetricRow(
                  icon: Icons.remove_circle_outline,
                  label: 'Deductions',
                  value: ownerPayrollMoney(
                    parsePayrollAmount(item['deductions']),
                  ),
                ),
                _PayrollMetricRow(
                  icon: Icons.schedule_outlined,
                  label: 'Overtime Pay',
                  value: ownerPayrollMoney(
                    parsePayrollAmount(item['overtime_pay']),
                  ),
                ),
                _PayrollMetricRow(
                  icon: Icons.tune_outlined,
                  label: 'Payroll Adjustments',
                  value: ownerPayrollMoney(
                    parsePayrollAmount(item['payroll_adjustments_total']),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF0FDF4),
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(18),
              ),
            ),
            child: Row(
              children: [
                const Text(
                  'Final Net Pay',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF166534),
                  ),
                ),
                const Spacer(),
                Text(
                  netPay,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF16A34A),
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

class _PayrollMetricRow extends StatelessWidget {
  const _PayrollMetricRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
