import 'dart:io';

import 'package:aroll_mobile/presentation/owner/payroll/owner_payroll_format.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<String> generateOwnerPayslipPdf({
  required Map<String, dynamic> payslip,
  required String businessName,
}) async {
  final doc = pw.Document();
  final employeeName = '${payslip['employee_name'] ?? 'Employee'}';
  final workedDays = parsePayrollAmount(payslip['worked_days']).toInt();
  final basicSalary = parsePayrollAmount(payslip['regular_pay']);
  final overtimePay = parsePayrollAmount(payslip['overtime_pay']);
  final holidayPay = parsePayrollAmount(payslip['holiday_pay']);
  final restDayPay = parsePayrollAmount(payslip['rest_day_pay']);
  final grossPay = parsePayrollAmount(payslip['gross_pay']);
  final deductions = parsePayrollAmount(payslip['deductions']);
  final lateDeductions = parsePayrollAmount(payslip['late_deductions']);
  final undertimeDeductions =
      parsePayrollAmount(payslip['undertime_deductions']);
  final baseNetPay = parsePayrollAmount(
    payslip['base_net_pay'] ?? payslip['net_pay'],
  );
  final finalNetPay = parsePayrollAmount(
    payslip['final_net_pay'] ?? payslip['net_pay'],
  );
  final adjustments =
      (payslip['payroll_adjustments'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
  final periodStart = '${payslip['period_start'] ?? ''}';
  final periodEnd = '${payslip['period_end'] ?? ''}';
  final restDayRecords =
      (payslip['rest_day_records'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        pw.Center(
          child: pw.Text(
            'Payslip',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Center(child: pw.Text(businessName, style: const pw.TextStyle(fontSize: 12))),
        pw.SizedBox(height: 16),
        pw.Text('Employee Information',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        _pdfRow('Employee Name', employeeName),
        _pdfRow('Position', '${payslip['position_title'] ?? 'Employee'}'),
        _pdfRow('Employment Type', ownerEmploymentLabel('${payslip['employment_type']}')),
        _pdfRow('Period', '$periodStart to $periodEnd'),
        _pdfRow('Worked Days', '$workedDays'),
        pw.SizedBox(height: 12),
        pw.Text('Earnings/Income', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        _pdfRow(ownerSalaryRateLabel(), ownerSalaryRate(payslip)),
        _pdfRow('Basic Salary', ownerPayrollMoney(basicSalary)),
        _pdfRow('Overtime Pay', ownerPayrollMoney(overtimePay)),
        _pdfRow('Holiday Pay', ownerPayrollMoney(holidayPay)),
        _pdfRow('Rest Day Premium', ownerPayrollMoney(restDayPay)),
        _pdfRow('Gross Salary', ownerPayrollMoney(grossPay)),
        if (restDayRecords.isNotEmpty) ...[
          pw.SizedBox(height: 12),
          pw.Text('Rest Day Work',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          ...restDayRecords.map((record) {
            final date = '${record['date'] ?? ''}';
            final weekday = '${record['weekday'] ?? ''}';
            final label = weekday.isEmpty ? date : '$date ($weekday)';
            return _pdfRow(
              label,
              ownerPayrollMoney(parsePayrollAmount(record['premium_pay'])),
            );
          }),
        ],
        pw.SizedBox(height: 12),
        pw.Text('Deductions', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        _pdfRow('Late Deduction', ownerPayrollMoney(lateDeductions)),
        _pdfRow('Undertime Deduction', ownerPayrollMoney(undertimeDeductions)),
        _pdfRow('Attendance Deduction Total', ownerPayrollMoney(deductions)),
        pw.SizedBox(height: 12),
        pw.Text('Payroll Adjustments',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        if (adjustments.isEmpty)
          _pdfRow('Adjustments', 'None')
        else
          ...adjustments.map((item) {
            final kind = '${item['kind'] ?? 'deduction'}';
            final name = '${item['display_name'] ?? 'Adjustment'}';
            return _pdfRow(
              '$name${kind == 'allowance' ? ' (+)' : ' (−)'}',
              ownerPayrollMoney(parsePayrollAmount(item['amount'])),
            );
          }),
        pw.SizedBox(height: 12),
        pw.Text('Net Pay', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        _pdfRow('Base Net Pay', ownerPayrollMoney(baseNetPay)),
        _pdfRow('Final Net Pay', ownerPayrollMoney(finalNetPay)),
      ],
    ),
  );

  final safeName =
      employeeName.toLowerCase().replaceAll(RegExp(r'\s+'), '-');
  final dir = await getTemporaryDirectory();
  final file = File(
    '${dir.path}/$safeName-payslip-${DateTime.now().millisecondsSinceEpoch}.pdf',
  );
  await file.writeAsBytes(await doc.save());
  return file.path;
}

pw.Widget _pdfRow(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Expanded(child: pw.Text(label, style: const pw.TextStyle(fontSize: 10))),
        pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
      ],
    ),
  );
}
