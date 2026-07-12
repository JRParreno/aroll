import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

class EmployeePayslipScreen extends StatefulWidget {
  const EmployeePayslipScreen({super.key});

  @override
  State<EmployeePayslipScreen> createState() => _EmployeePayslipScreenState();
}

class _EmployeePayslipScreenState extends State<EmployeePayslipScreen> {
  bool _downloading = false;

  Future<void> _download() async {
    setState(() => _downloading = true);
    try {
      final path = await sl<EmployeeRepository>().downloadPayslipPdf();
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
        const SnackBar(content: Text('Unable to download payslip.')),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return EmployeeScaffold(
      title: 'Salary Slip',
      selectedIndex: 3,
      showBack: true,
      child: FutureBuilder<EmployeePayslip>(
        future: sl<EmployeeRepository>().getPayslip(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return loadingView();
          }
          if (snapshot.hasError) return errorView(snapshot.error);
          final payslip = snapshot.data!;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              EmployeeCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 34, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8D8D8D),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'SALARY SLIP',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: Text(
                        payslip.businessName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const Divider(height: 24),
                    const _SectionTitle('Employee Information'),
                    _Row('Employee Name', payslip.employeeName),
                    _Row('No. of Working Days', '${payslip.workedDays}'),
                    _Row(
                      'Period Date',
                      '${shortDate(payslip.periodStart)} - ${shortDate(payslip.periodEnd)}',
                    ),
                    _Row('Position', payslip.positionTitle ?? 'Employee'),
                    _Row('Employment Type', titleCase(payslip.employmentType)),
                    const SizedBox(height: 12),
                    const _SectionTitle('Earnings/Income',
                        color: Color(0xFFFFE681)),
                    _Row('Salary Rate (daily)', money(payslip.dailyRate)),
                    _Row(
                      'Basic Salary',
                      money(payslip.dailyRate * payslip.workedDays),
                    ),
                    _Row('Overtime', money(payslip.overtimePay)),
                    _Row('Holiday Pay', money(payslip.holidayPay)),
                    _Row('Total Earnings', money(payslip.grossPay),
                        strong: true),
                    const SizedBox(height: 12),
                    const _SectionTitle('Deductions', color: Color(0xFFFFC5C5)),
                    _Row('Late/Undertime', money(payslip.deductions)),
                    _Row('Absent Days', '${payslip.absentDays}'),
                    _Row('Total Deductions', money(payslip.deductions),
                        strong: true),
                    const SizedBox(height: 12),
                    const _SectionTitle('NET PAY', color: Color(0xFFC8F7CE)),
                    _Row('Net Pay', money(payslip.netPay), strong: true),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _downloading ? null : _download,
                child: Text(
                    _downloading ? 'Downloading...' : 'Download Payslip (PDF)'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label, {this.color = const Color(0xFFE5E7EB)});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      color: color,
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.strong = false});

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
