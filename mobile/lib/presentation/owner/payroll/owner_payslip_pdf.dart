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
  final dailyRate = parsePayrollAmount(payslip['daily_rate']);
  final workedDays = parsePayrollAmount(payslip['worked_days']).toInt();
  final basicSalary = dailyRate * workedDays;
  final overtimePay = parsePayrollAmount(payslip['overtime_pay']);
  final holidayPay = parsePayrollAmount(payslip['holiday_pay']);
  final restDayPay = parsePayrollAmount(payslip['rest_day_pay']);
  final grossPay = parsePayrollAmount(payslip['gross_pay']);
  final deductions = parsePayrollAmount(payslip['deductions']);
  final netPay = parsePayrollAmount(payslip['net_pay']);
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
        _pdfRow('Daily Rate', ownerPayrollMoney(dailyRate)),
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
        _pdfRow('Late Deductions', ownerPayrollMoney(deductions)),
        _pdfRow('Total Deductions', ownerPayrollMoney(deductions)),
        pw.SizedBox(height: 12),
        pw.Text('Net Pay', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        _pdfRow('Net Salary', ownerPayrollMoney(netPay)),
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
