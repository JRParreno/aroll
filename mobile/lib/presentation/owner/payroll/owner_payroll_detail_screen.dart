import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:aroll_mobile/presentation/owner/payroll/owner_payroll_format.dart';
import 'package:aroll_mobile/presentation/owner/payroll/owner_payslip_pdf.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
class OwnerPayrollDetailScreen extends StatefulWidget {
  const OwnerPayrollDetailScreen({
    super.key,
    required this.employeeId,
  });

  final String employeeId;

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
        _repo.employeePayslip(widget.employeeId),
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
    final basicSalary = dailyRate * workedDays;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F6F8),
        elevation: 0,
        title: Text(
          payslip?['employee_name'] != null
              ? '${payslip!['employee_name']}'
              : 'Payroll Details',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : payslip == null
                  ? const Center(child: Text('Payslip not found.'))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                EmployeeAvatar(
                                  imageUrl: _profileImageUrl,
                                  name: '${payslip['employee_name'] ?? 'Employee'}',
                                  size: 60,
                                  backgroundColor: const Color(0xFFE7EEF5),
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
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        ownerEmploymentLabel(
                                          '${payslip['employment_type']}',
                                        ),
                                        style: const TextStyle(
                                          color: Color(0xFF6B7280),
                                        ),
                                      ),
                                      Text(
                                        '${payslip['position_title'] ?? 'Employee'}',
                                        style: const TextStyle(
                                          color: Color(0xFF6B7280),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _SectionCard(
                          title: 'Attendance Overview',
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
                              'Overtime Hours',
                              '${payslip['overtime_hours'] ?? 0}',
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _SectionCard(
                          title: 'Payroll Breakdown',
                          children: [
                            _DetailRow(
                              'Daily Rate',
                              ownerPayrollMoney(dailyRate),
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
                              'Gross Salary',
                              ownerPayrollMoney(
                                parsePayrollAmount(payslip['gross_pay']),
                              ),
                            ),
                            _DetailRow(
                              'Late Deductions',
                              ownerPayrollMoney(
                                parsePayrollAmount(payslip['deductions']),
                              ),
                            ),
                            _DetailRow(
                              'Other Deductions',
                              ownerPayrollMoney(0),
                            ),
                            _DetailRow(
                              'Total Deductions',
                              ownerPayrollMoney(
                                parsePayrollAmount(payslip['deductions']),
                              ),
                            ),
                            _DetailRow(
                              'Net Salary',
                              ownerPayrollMoney(
                                parsePayrollAmount(payslip['net_pay']),
                              ),
                              highlight: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _SectionCard(
                          title: 'Daily Attendance Log',
                          children: _attendanceRows(payslip, dailyRate),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _downloading ? null : _downloadPdf,
                            icon: _downloading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.download_outlined),
                            label: Text(
                              _downloading
                                  ? 'Downloading...'
                                  : 'Download Payslip PDF',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF1E466E),
                              minimumSize: const Size(0, 46),
                            ),
                          ),
                        ),
                      ],
                    ),
    );
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
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFBFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E7EB)),
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
    final timeIn = record['time_in'] as String?;
    final timeOut = record['time_out'] as String?;
    if (timeIn != null) parts.add('In: ${_shortTime(timeIn)}');
    if (timeOut != null) parts.add('Out: ${_shortTime(timeOut)}');
    return parts.isEmpty ? '--' : parts.join(' · ');
  }

  String _shortTime(String iso) {
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
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E466E),
              ),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
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
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
              color: highlight
                  ? const Color(0xFF16A34A)
                  : const Color(0xFF1F2937),
            ),
          ),
        ],
      ),
    );
  }
}
