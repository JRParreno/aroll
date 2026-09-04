import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/owner/payroll/owner_payroll_format.dart';
import 'package:aroll_mobile/presentation/owner/payroll/owner_payslip_pdf.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:aroll_mobile/presentation/shared/tenant_mode_banner.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

class OwnerPayrollDetailScreen extends StatefulWidget {
  const OwnerPayrollDetailScreen({
    super.key,
    required this.employeeId,
    this.asOf,
  });

  final String employeeId;
  final DateTime? asOf;

  @override
  State<OwnerPayrollDetailScreen> createState() =>
      _OwnerPayrollDetailScreenState();
}

class _OwnerPayrollDetailScreenState extends State<OwnerPayrollDetailScreen> {
  final _repo = sl<OwnerRepository>();

  bool _loading = true;
  bool _downloading = false;
  String? _error;
  Map<String, dynamic>? _payslip;
  String? _profileImageUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repo.employeePayslip(widget.employeeId, asOf: widget.asOf),
        _repo.employees(),
      ]);
      final payslip = results[0] as Map<String, dynamic>;
      final employees = results[1] as List<Map<String, dynamic>>;
      Map<String, dynamic>? employee;
      for (final row in employees) {
        if ('${row['id']}' == widget.employeeId) {
          employee = row;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _payslip = payslip;
        _profileImageUrl = employee?['profile_image_url'] as String?;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load payroll details.';
      });
    }
  }

  Future<void> _downloadPdf() async {
    final payslip = _payslip;
    if (payslip == null) return;
    setState(() => _downloading = true);
    try {
      final businessName =
          sl<AppState>().session?.businessName ?? 'Business';
      final path = await generateOwnerPayslipPdf(
        payslip: payslip,
        businessName: businessName,
        sample: sl<AppState>().session?.isDemo == true,
      );
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: 'application/pdf')],
          subject: 'Payslip PDF',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to download payslip PDF.')),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final payslip = _payslip;
    final dailyRate = parsePayrollAmount(payslip?['daily_rate']);
    final workedDays = parsePayrollAmount(payslip?['worked_days']).toInt();
    final basicSalary = parsePayrollAmount(payslip?['regular_pay']);

    return OwnerShell(
      selectedIndex: 0,
      showBackButton: true,
      title: payslip?['employee_name'] != null
          ? '${payslip!['employee_name']}'
          : 'Payroll Details',
      child: _loading
          ? appLoadingView(cardCount: 4)
          : _error != null
              ? OwnerErrorState(onRetry: _load)
              : payslip == null
                  ? const OwnerEmptyState(
                      'Payslip not found',
                      description:
                          'This payroll record may no longer be available.',
                      icon: Icons.receipt_long_outlined,
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      children: [
                        if (sl<AppState>().session?.isDemo == true) ...[
                          const PayslipSampleBanner(),
                          const SizedBox(height: 12),
                        ],
                        OwnerCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    EmployeeAvatar(
                                      imageUrl: _profileImageUrl,
                                      name:
                                          '${payslip['employee_name'] ?? 'Employee'}',
                                      size: 60,
                                      backgroundColor: AppColors.iconWell,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${payslip['employee_name']}',
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            ownerEmploymentLabel(
                                              '${payslip['employment_type']}',
                                            ),
                                            style: appMutedStyle(),
                                          ),
                                          Text(
                                            '${payslip['position_title'] ?? 'Employee'}',
                                            style: appMutedStyle(),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            '${ownerPayrollShortDate('${payslip['period_start']}')} – ${ownerPayrollShortDate('${payslip['period_end']}')}',
                                            style: appMutedStyle().copyWith(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.primaryDark,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
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
                                      ownerPayrollMoney(
                                        parsePayrollAmount(
                                          payslip['final_net_pay'] ??
                                              payslip['net_pay'],
                                        ),
                                      ),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF16A34A),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _SectionCard(
                          title: 'Attendance Overview',
                          icon: Icons.event_available_outlined,
                          children: [
                            _DetailRow(
                              'Worked Days',
                              '${payslip['worked_days'] ?? 0}',
                            ),
                            _DetailRow(
                              'Absent Days',
                              '${payslip['absent_days'] ?? 0}',
                            ),
                            _DetailRow(
                              'Paid Leave',
                              '${payslip['paid_leave_days'] ?? 0}',
                            ),
                            _DetailRow(
                              'Unpaid Leave',
                              '${payslip['unpaid_leave_days'] ?? 0}',
                            ),
                            _DetailRow(
                              'Overtime Hours',
                              '${payslip['overtime_hours'] ?? 0}',
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _SectionCard(
                          title: 'Payroll Breakdown',
                          icon: Icons.receipt_long_outlined,
                          children: [
                            _DetailRow(
                              ownerSalaryRateLabel(),
                              ownerSalaryRate(payslip),
                            ),
                            _DetailRow(
                              'Basic Salary',
                              ownerPayrollMoney(basicSalary),
                            ),
                            _DetailRow(
                              'Overtime Pay',
                              ownerPayrollMoney(
                                parsePayrollAmount(payslip['overtime_pay']),
                              ),
                            ),
                            _DetailRow(
                              'Holiday Pay',
                              ownerPayrollMoney(
                                parsePayrollAmount(payslip['holiday_pay']),
                              ),
                            ),
                            _DetailRow(
                              payslip['rest_day_premium_percent'] != null &&
                                      parsePayrollAmount(
                                            payslip['rest_day_premium_percent'],
                                          ) >
                                          0
                                  ? 'Rest Day Premium (${parsePayrollAmount(payslip['rest_day_premium_percent']).toStringAsFixed(0)}%)'
                                  : 'Rest Day Premium',
                              ownerPayrollMoney(
                                parsePayrollAmount(payslip['rest_day_pay']),
                              ),
                            ),
                            _DetailRow(
                              'Gross Salary',
                              ownerPayrollMoney(
                                parsePayrollAmount(payslip['gross_pay']),
                              ),
                            ),
                            _DetailRow(
                              'Late Deduction',
                              ownerPayrollMoney(
                                parsePayrollAmount(payslip['late_deductions']),
                              ),
                            ),
                            _DetailRow(
                              'Undertime Deduction',
                              ownerPayrollMoney(
                                parsePayrollAmount(
                                  payslip['undertime_deductions'],
                                ),
                              ),
                            ),
                            _DetailRow(
                              'Attendance Deduction Total',
                              ownerPayrollMoney(
                                parsePayrollAmount(payslip['deductions']),
                              ),
                            ),
                            _DetailRow(
                              'Base Net Pay',
                              ownerPayrollMoney(
                                parsePayrollAmount(
                                  payslip['base_net_pay'] ?? payslip['net_pay'],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _SectionCard(
                          title: 'Payroll Adjustments',
                          icon: Icons.tune_outlined,
                          children: [
                            ..._adjustmentRows(payslip),
                            if (payslip['adjustments_editable'] == true) ...[
                              const SizedBox(height: 10),
                              AppPrimaryButton(
                                label: 'Add Deduction',
                                icon: Icons.add_rounded,
                                onPressed: () => _openAdjustmentSheet(),
                              ),
                            ] else
                              const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: Text(
                                  'This pay period has ended. Adjustments are read-only.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 10),
                            _DetailRow(
                              'Final Net Pay',
                              ownerPayrollMoney(
                                parsePayrollAmount(
                                  payslip['final_net_pay'] ??
                                      payslip['net_pay'],
                                ),
                              ),
                              highlight: true,
                            ),
                          ],
                        ),
                        if (((payslip['rest_day_records'] as List<dynamic>?) ??
                                const [])
                            .isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _SectionCard(
                            title: 'Rest Day Work',
                            icon: Icons.beach_access_outlined,
                            children: _restDayRows(payslip),
                          ),
                        ],
                        const SizedBox(height: 12),
                        _SectionCard(
                          title: 'Daily Attendance Log',
                          icon: Icons.list_alt_rounded,
                          children: _attendanceRows(payslip, dailyRate),
                        ),
                        const SizedBox(height: 16),
                        AppPrimaryButton(
                          label: _downloading
                              ? 'Downloading...'
                              : 'Download Payslip PDF',
                          loading: _downloading,
                          icon: Icons.download_outlined,
                          onPressed: _downloading ? null : _downloadPdf,
                        ),
                      ],
                    ),
    );
  }

  List<Widget> _adjustmentRows(Map<String, dynamic> payslip) {
    final items = (payslip['payroll_adjustments'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final editable = payslip['adjustments_editable'] == true;
    if (items.isEmpty) {
      return const [
        Text(
          'No payroll adjustments for this period.',
          style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
        ),
      ];
    }
    return [
      for (final item in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item['display_name'] ?? 'Adjustment'}'
                      '${item['kind'] == 'allowance' ? ' (+)' : ' (−)'}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if ('${item['description'] ?? ''}'.trim().isNotEmpty)
                      Text(
                        '${item['description']}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    Text(
                      ownerPayrollMoney(parsePayrollAmount(item['amount'])),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (editable) ...[
                IconButton(
                  tooltip: 'Edit',
                  onPressed: () => _openAdjustmentSheet(existing: item),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                ),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: () => _deleteAdjustment('${item['id']}'),
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
              ],
            ],
          ),
        ),
    ];
  }

  Future<void> _deleteAdjustment(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove adjustment?'),
        content: const Text(
          'This deduction/allowance will be removed from the payroll slip.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.deletePayrollAdjustment(id);
      await _load();
    } catch (_) {
      if (!mounted) return;
      showAppSnack(
        context,
        message: 'Unable to remove adjustment.',
        isError: true,
      );
    }
  }

  Future<void> _openAdjustmentSheet({Map<String, dynamic>? existing}) async {
    final types = await _repo.payrollAdjustmentTypes();
    if (!mounted) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _AdjustmentFormSheet(
        existing: existing,
        deductionTypes:
            (types['deduction_types'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>()
                .toList(),
        allowanceTypes:
            (types['allowance_types'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>()
                .toList(),
        onSubmit: (payload) async {
          if (existing != null) {
            await _repo.updatePayrollAdjustment(
              '${existing['id']}',
              kind: payload.kind,
              typeKey: payload.typeKey,
              customName: payload.customName,
              description: payload.description,
              amount: payload.amount,
            );
          } else {
            await _repo.createPayrollAdjustment(
              widget.employeeId,
              kind: payload.kind,
              typeKey: payload.typeKey,
              customName: payload.customName,
              description: payload.description,
              amount: payload.amount,
              asOf: widget.asOf,
            );
          }
        },
      ),
    );
    if (saved == true) await _load();
  }

  List<Widget> _restDayRows(Map<String, dynamic> payslip) {
    final records = (payslip['rest_day_records'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final restDayName = '${payslip['rest_day_name'] ?? ''}';
    return [
      _DetailRow(
        'Rest day type',
        restDayName.isEmpty ? 'Owner-approved rest day work' : titleCase(restDayName),
      ),
      _DetailRow('Days worked', '${payslip['rest_day_days'] ?? records.length}'),
      ...records.map((record) {
        final weekday = '${record['weekday'] ?? ''}';
        final unauthorized = record['authorized'] == false;
        return Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: unauthorized
                ? const Color(0xFFFFFBEB)
                : const Color(0xFFF0F9FF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: unauthorized
                  ? const Color(0xFFFDE68A)
                  : const Color(0xFFBAE6FD),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (unauthorized)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Not permitted',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF92400E),
                    ),
                  ),
                ),
              _DetailRow(
                'Date',
                '${ownerPayrollDisplayDate('${record['date']}')}${weekday.isEmpty ? '' : ' · ${titleCase(weekday)}'}',
              ),
              _DetailRow(
                'Time In',
                _shortTime('${record['time_in'] ?? ''}'),
              ),
              _DetailRow(
                'Time Out',
                _shortTime('${record['time_out'] ?? ''}'),
              ),
              if ('${record['shift_name'] ?? ''}'.isNotEmpty)
                _DetailRow('Shift', '${record['shift_name']}'),
              _DetailRow(
                'Premium',
                ownerPayrollMoney(parsePayrollAmount(record['premium_pay'])),
                highlight: true,
              ),
            ],
          ),
        );
      }),
    ];
  }

  List<Widget> _attendanceRows(
    Map<String, dynamic> payslip,
    double dailyRate,
  ) {
    final records = (payslip['attendance_records'] as List<dynamic>? ??
            const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (records.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'No attendance records for this period.',
            style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
          ),
        ),
      ];
    }

    return records.map((record) {
      final status = '${record['status'] ?? ''}';
      final absent = status == 'absent';
      final remarks = _attendanceRemarks(record);
      final earned = absent ? 0.0 : dailyRate;
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.fieldFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailRow(
              'Date',
              ownerPayrollDisplayDate('${record['date']}'),
            ),
            _DetailRow('Status', ownerStatusLabel(status)),
            _DetailRow('Remarks', remarks),
            _DetailRow(
              'Salary Earned',
              ownerPayrollMoney(earned),
            ),
          ],
        ),
      );
    }).toList();
  }

  String _attendanceRemarks(Map<String, dynamic> record) {
    final parts = <String>[];
    final holiday = record['holiday_name'] as String?;
    if (holiday != null && holiday.isNotEmpty) {
      parts.add(holiday);
    }
    if (record['is_rest_day'] == true) {
      parts.add('Rest day');
    }
    final timeIn = record['time_in'] as String?;
    final timeOut = record['time_out'] as String?;
    if (timeIn != null) parts.add('In: ${_shortTime(timeIn)}');
    if (timeOut != null) parts.add('Out: ${_shortTime(timeOut)}');
    return parts.isEmpty ? '--' : parts.join(' · ');
  }

  String _shortTime(String iso) {
    if (iso.isEmpty) return '--:--';
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    return '${parsed.hour.toString().padLeft(2, '0')}:'
        '${parsed.minute.toString().padLeft(2, '0')}';
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.children,
    this.icon,
  });

  final String title;
  final List<Widget> children;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return OwnerCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.iconWell,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 16, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value, {this.highlight = false});

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
                color: highlight ? AppColors.success : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdjustmentPayload {
  const _AdjustmentPayload({
    required this.kind,
    required this.typeKey,
    this.customName,
    this.description,
    required this.amount,
  });

  final String kind;
  final String typeKey;
  final String? customName;
  final String? description;
  final double amount;
}

class _AdjustmentFormSheet extends StatefulWidget {
  const _AdjustmentFormSheet({
    required this.deductionTypes,
    required this.allowanceTypes,
    required this.onSubmit,
    this.existing,
  });

  final List<Map<String, dynamic>> deductionTypes;
  final List<Map<String, dynamic>> allowanceTypes;
  final Map<String, dynamic>? existing;
  final Future<void> Function(_AdjustmentPayload payload) onSubmit;

  @override
  State<_AdjustmentFormSheet> createState() => _AdjustmentFormSheetState();
}

class _AdjustmentFormSheetState extends State<_AdjustmentFormSheet> {
  late String _kind;
  late String _typeKey;
  late final TextEditingController _customName;
  late final TextEditingController _description;
  late final TextEditingController _amount;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _kind = '${existing?['kind'] ?? 'deduction'}';
    _typeKey = '${existing?['type_key'] ?? (widget.deductionTypes.isNotEmpty ? widget.deductionTypes.first['key'] : 'other')}';
    _customName = TextEditingController(text: '${existing?['custom_name'] ?? ''}');
    _description =
        TextEditingController(text: '${existing?['description'] ?? ''}');
    _amount = TextEditingController(
      text: existing == null ? '' : '${existing['amount'] ?? ''}',
    );
  }

  @override
  void dispose() {
    _customName.dispose();
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _types =>
      _kind == 'allowance' ? widget.allowanceTypes : widget.deductionTypes;

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (_typeKey.trim().isEmpty) {
      setState(() => _error = 'Deduction type is required.');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Amount must be greater than zero.');
      return;
    }
    if (_typeKey == 'other' && _customName.text.trim().isEmpty) {
      setState(() => _error = 'Enter a custom name for Other.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        _AdjustmentPayload(
          kind: _kind,
          typeKey: _typeKey,
          customName: _typeKey == 'other' ? _customName.text.trim() : null,
          description: _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
          amount: amount,
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Unable to save adjustment.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.existing == null ? 'Add Deduction' : 'Edit Adjustment',
              style: appSectionTitleStyle(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _kind,
              decoration: appInputDecoration(labelText: 'Kind'),
              items: const [
                DropdownMenuItem(value: 'deduction', child: Text('Deduction')),
                DropdownMenuItem(value: 'allowance', child: Text('Allowance')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _kind = value;
                  final types = _types;
                  _typeKey = types.isNotEmpty ? '${types.first['key']}' : 'other';
                });
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _types.any((t) => '${t['key']}' == _typeKey)
                  ? _typeKey
                  : (_types.isNotEmpty ? '${_types.first['key']}' : null),
              decoration: appInputDecoration(labelText: 'Type'),
              items: [
                for (final type in _types)
                  DropdownMenuItem(
                    value: '${type['key']}',
                    child: Text('${type['label']}'),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _typeKey = value);
              },
            ),
            if (_typeKey == 'other') ...[
              const SizedBox(height: 10),
              TextField(
                controller: _customName,
                decoration: appInputDecoration(
                  labelText: 'Custom name',
                  hintText: 'e.g. Lost company property',
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _description,
              decoration: appInputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: appInputDecoration(labelText: 'Amount'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
            const SizedBox(height: 14),
            AppPrimaryButton(
              label: widget.existing == null ? 'Add Adjustment' : 'Save Changes',
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
