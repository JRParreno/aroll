import 'dart:io';

import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:aroll_mobile/presentation/owner/payroll/owner_payroll_format.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Shared Aroll+ payslip PDF — mirrors Employee Mobile payslip layout.
class StandardPayslipPdfData {
  const StandardPayslipPdfData({
    required this.businessName,
    required this.employeeName,
    required this.workedDays,
    required this.periodLabel,
    required this.payDateLabel,
    required this.payrollStatus,
    required this.positionTitle,
    required this.employmentType,
    required this.hoursWorkedLabel,
    required this.salaryRateLabel,
    required this.salaryRateValue,
    required this.basicSalary,
    required this.leavePay,
    required this.overtimePay,
    required this.holidayPay,
    required this.restDayPremiumLabel,
    required this.restDayPay,
    required this.grossPay,
    required this.lateDeductions,
    required this.undertimeDeductions,
    required this.absentDays,
    required this.deductionsTotal,
    required this.baseNetPay,
    required this.finalNetPay,
    this.restDayName,
    this.restDayDays = 0,
    this.restDayRecords = const [],
    this.adjustments = const [],
  });

  final String businessName;
  final String employeeName;
  final String workedDays;
  final String periodLabel;
  final String payDateLabel;
  final String payrollStatus;
  final String positionTitle;
  final String employmentType;
  final String hoursWorkedLabel;
  final String salaryRateLabel;
  final String salaryRateValue;
  final String basicSalary;
  final String leavePay;
  final String overtimePay;
  final String holidayPay;
  final String restDayPremiumLabel;
  final String restDayPay;
  final String grossPay;
  final String lateDeductions;
  final String undertimeDeductions;
  final String absentDays;
  final String deductionsTotal;
  final String baseNetPay;
  final String finalNetPay;
  final String? restDayName;
  final int restDayDays;
  final List<StandardPayslipRestDayRow> restDayRecords;
  final List<StandardPayslipAdjustmentRow> adjustments;

  factory StandardPayslipPdfData.fromEmployee(EmployeePayslip payslip) {
    return StandardPayslipPdfData(
      businessName: payslip.businessName,
      employeeName: payslip.employeeName,
      workedDays: '${payslip.workedDays}',
      periodLabel:
          '${shortDate(payslip.periodStart)} - ${shortDate(payslip.periodEnd)}',
      payDateLabel: shortDate(payslip.payDate ?? payslip.periodEnd),
      payrollStatus: titleCase(payslip.payrollStatus),
      positionTitle: payslip.positionTitle ?? 'Employee',
      employmentType: titleCase(payslip.employmentType),
      hoursWorkedLabel: payslip.hoursWorked.toStringAsFixed(1),
      salaryRateLabel: salaryRateRowLabel(),
      salaryRateValue: salaryRateDisplayFromPayslip(payslip),
      basicSalary: money(payslip.regularPay),
      leavePay: money(payslip.leavePay),
      overtimePay: money(payslip.overtimePay),
      holidayPay: money(payslip.holidayPay),
      restDayPremiumLabel: payslip.restDayPremiumPercent > 0
          ? 'Rest Day Premium (${payslip.restDayPremiumPercent.toStringAsFixed(0)}%)'
          : 'Rest Day Premium',
      restDayPay: money(payslip.restDayPay),
      grossPay: money(payslip.grossPay),
      lateDeductions: money(payslip.lateDeductions),
      undertimeDeductions: money(payslip.undertimeDeductions),
      absentDays: '${payslip.absentDays}',
      deductionsTotal: money(payslip.deductions),
      baseNetPay: money(payslip.baseNetPay ?? payslip.netPay),
      finalNetPay: money(payslip.displayNetPay),
      restDayName: payslip.restDayName,
      restDayDays: payslip.restDayDays,
      restDayRecords: payslip.restDayRecords
          .map(
            (r) => StandardPayslipRestDayRow(
              dateLabel:
                  '${shortDate(r.date)}${r.weekday.isEmpty ? '' : ' · ${titleCase(r.weekday)}'}',
              timeLabel:
                  'In ${_hhmm(r.timeIn)} · Out ${_hhmm(r.timeOut)}${r.shiftName == null ? '' : ' · ${r.shiftName}'}',
              premium: money(r.premiumPay),
            ),
          )
          .toList(),
      adjustments: payslip.payrollAdjustments
          .map(
            (a) => StandardPayslipAdjustmentRow(
              label:
                  '${a.displayName}${a.kind == 'allowance' ? ' (+)' : ' (−)'}',
              amount: money(a.amount),
              description: a.description,
            ),
          )
          .toList(),
    );
  }

  factory StandardPayslipPdfData.fromOwnerMap(
    Map<String, dynamic> payslip, {
    required String businessName,
  }) {
    final periodStart = '${payslip['period_start'] ?? ''}';
    final periodEnd = '${payslip['period_end'] ?? ''}';
    final payDate = '${payslip['pay_date'] ?? periodEnd}';
    final restPct = parsePayrollAmount(payslip['rest_day_premium_percent']);
    final restRecords =
        (payslip['rest_day_records'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
    final adjustments =
        (payslip['payroll_adjustments'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

    return StandardPayslipPdfData(
      businessName: businessName,
      employeeName: '${payslip['employee_name'] ?? 'Employee'}',
      workedDays: '${parsePayrollAmount(payslip['worked_days']).toInt()}',
      periodLabel:
          '${_fmtDate(periodStart)} - ${_fmtDate(periodEnd)}',
      payDateLabel: _fmtDate(payDate),
      payrollStatus: titleCase('${payslip['payroll_status'] ?? 'current'}'),
      positionTitle: '${payslip['position_title'] ?? 'Employee'}',
      employmentType: ownerEmploymentLabel('${payslip['employment_type']}'),
      hoursWorkedLabel:
          parsePayrollAmount(payslip['hours_worked']).toStringAsFixed(1),
      salaryRateLabel: ownerSalaryRateLabel(),
      salaryRateValue: ownerSalaryRate(payslip),
      basicSalary: ownerPayrollMoney(parsePayrollAmount(payslip['regular_pay'])),
      leavePay: ownerPayrollMoney(parsePayrollAmount(payslip['leave_pay'])),
      overtimePay:
          ownerPayrollMoney(parsePayrollAmount(payslip['overtime_pay'])),
      holidayPay:
          ownerPayrollMoney(parsePayrollAmount(payslip['holiday_pay'])),
      restDayPremiumLabel: restPct > 0
          ? 'Rest Day Premium (${restPct.toStringAsFixed(0)}%)'
          : 'Rest Day Premium',
      restDayPay:
          ownerPayrollMoney(parsePayrollAmount(payslip['rest_day_pay'])),
      grossPay: ownerPayrollMoney(parsePayrollAmount(payslip['gross_pay'])),
      lateDeductions:
          ownerPayrollMoney(parsePayrollAmount(payslip['late_deductions'])),
      undertimeDeductions: ownerPayrollMoney(
        parsePayrollAmount(payslip['undertime_deductions']),
      ),
      absentDays: '${payslip['absent_days'] ?? 0}',
      deductionsTotal:
          ownerPayrollMoney(parsePayrollAmount(payslip['deductions'])),
      baseNetPay: ownerPayrollMoney(
        parsePayrollAmount(payslip['base_net_pay'] ?? payslip['net_pay']),
      ),
      finalNetPay: ownerPayrollMoney(
        parsePayrollAmount(payslip['final_net_pay'] ?? payslip['net_pay']),
      ),
      restDayName: payslip['rest_day_name'] as String?,
      restDayDays: parsePayrollAmount(payslip['rest_day_days']).toInt(),
      restDayRecords: restRecords
          .map(
            (r) {
              final weekday = '${r['weekday'] ?? ''}';
              return StandardPayslipRestDayRow(
                dateLabel:
                    '${_fmtDate('${r['date']}')}${weekday.isEmpty ? '' : ' · ${titleCase(weekday)}'}',
                timeLabel:
                    'In ${_hhmmIso('${r['time_in'] ?? ''}')} · Out ${_hhmmIso('${r['time_out'] ?? ''}')}${r['shift_name'] == null || '${r['shift_name']}'.isEmpty ? '' : ' · ${r['shift_name']}'}',
                premium: ownerPayrollMoney(
                  parsePayrollAmount(r['premium_pay']),
                ),
              );
            },
          )
          .toList(),
      adjustments: adjustments
          .map(
            (a) => StandardPayslipAdjustmentRow(
              label:
                  '${a['display_name'] ?? 'Adjustment'}${a['kind'] == 'allowance' ? ' (+)' : ' (−)'}',
              amount: ownerPayrollMoney(parsePayrollAmount(a['amount'])),
              description: a['description'] as String?,
            ),
          )
          .toList(),
    );
  }
}

class StandardPayslipRestDayRow {
  const StandardPayslipRestDayRow({
    required this.dateLabel,
    required this.timeLabel,
    required this.premium,
  });

  final String dateLabel;
  final String timeLabel;
  final String premium;
}

class StandardPayslipAdjustmentRow {
  const StandardPayslipAdjustmentRow({
    required this.label,
    required this.amount,
    this.description,
  });

  final String label;
  final String amount;
  final String? description;
}

pw.Font? _cachedRegular;
pw.Font? _cachedBold;

Future<void> _ensureFonts() async {
  if (_cachedRegular != null && _cachedBold != null) return;
  final regularData =
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
  final boldData = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
  _cachedRegular = pw.Font.ttf(regularData);
  _cachedBold = pw.Font.ttf(boldData);
}

/// Builds standard Employee-format payslip PDF bytes.
Future<List<int>> buildStandardPayslipPdfBytes(
  StandardPayslipPdfData data, {
  bool sample = false,
}) async {
  await _ensureFonts();
  final regular = _cachedRegular!;
  final bold = _cachedBold!;

  final sectionGray = PdfColor.fromInt(0xFFE5E7EB);
  final earningsColor = PdfColor.fromInt(0xFFFFE681);
  final restDayColor = PdfColor.fromInt(0xFFDBEAFE);
  final deductionsColor = PdfColor.fromInt(0xFFFFC5C5);
  final adjustmentsColor = PdfColor.fromInt(0xFFFDE68A);
  final netColor = PdfColor.fromInt(0xFFC8F7CE);
  final headerPill = PdfColor.fromInt(0xFF8D8D8D);
  final muted = PdfColor.fromInt(0xFF6B7280);
  final divider = PdfColor.fromInt(0xFFD1D5DB);
  final restCardBg = PdfColor.fromInt(0xFFF0F9FF);
  final restCardBorder = PdfColor.fromInt(0xFFBAE6FD);
  final restAccent = PdfColor.fromInt(0xFF075985);

  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );

  // Avoid MultiPage + large rounded border containers (causes gray artifacts).
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      build: (context) {
        return [
          pw.Center(
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 8,
              ),
              decoration: pw.BoxDecoration(
                color: headerPill,
                borderRadius: pw.BorderRadius.circular(20),
              ),
              child: pw.Text(
                sample ? 'SAMPLE PAYSLIP' : 'PAYSLIP',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  font: bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          if (sample) ...[
            pw.SizedBox(height: 12),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFFFF7ED),
                border: pw.Border.all(color: PdfColor.fromInt(0xFFFED7AA)),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                children: [
                  pw.Text(
                    'SAMPLE — DEMONSTRATION ONLY',
                    style: pw.TextStyle(
                      font: bold,
                      fontSize: 9,
                      color: PdfColor.fromInt(0xFF9A3412),
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.Text(
                    'NOT FOR ACTUAL SALARY PAYMENT',
                    style: pw.TextStyle(
                      font: bold,
                      fontSize: 8,
                      color: PdfColor.fromInt(0xFFC2410C),
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
          pw.SizedBox(height: 14),
          pw.Center(
            child: pw.Text(
              data.businessName,
              style: pw.TextStyle(font: bold, fontSize: 13),
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Divider(thickness: 0.8, color: divider),
          pw.SizedBox(height: 8),
          _sectionHeader('Employee Information', sectionGray, bold),
          _dataRow('Employee Name', data.employeeName, regular, bold),
          _dataRow('No. of Working Days', data.workedDays, regular, bold),
          _dataRow('Period Date', data.periodLabel, regular, bold),
          _dataRow('Pay Date', data.payDateLabel, regular, bold),
          _dataRow('Payroll Status', data.payrollStatus, regular, bold),
          _dataRow('Position', data.positionTitle, regular, bold),
          _dataRow('Employment Type', data.employmentType, regular, bold),
          _dataRow('Hours Worked', data.hoursWorkedLabel, regular, bold),
          pw.SizedBox(height: 10),
          _sectionHeader('Earnings/Income', earningsColor, bold),
          _dataRow(data.salaryRateLabel, data.salaryRateValue, regular, bold),
          _dataRow('Basic Salary', data.basicSalary, regular, bold),
          _dataRow('Leave Pay', data.leavePay, regular, bold),
          _dataRow('Overtime', data.overtimePay, regular, bold),
          _dataRow('Holiday Pay', data.holidayPay, regular, bold),
          _dataRow(
            data.restDayPremiumLabel,
            data.restDayPay,
            regular,
            bold,
          ),
          _dataRow('Gross Pay', data.grossPay, regular, bold, strong: true),
          if (data.restDayRecords.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            _sectionHeader('Rest Day Work', restDayColor, bold),
            _dataRow(
              'Rest day',
              data.restDayName == null || data.restDayName!.isEmpty
                  ? 'Owner-approved rest day work'
                  : titleCase(data.restDayName!),
              regular,
              bold,
            ),
            _dataRow('Days worked', '${data.restDayDays}', regular, bold),
            ...data.restDayRecords.map(
              (r) => pw.Padding(
                padding: const pw.EdgeInsets.only(top: 8),
                child: pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: restCardBg,
                    borderRadius: pw.BorderRadius.circular(8),
                    border: pw.Border.all(color: restCardBorder),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Expanded(
                            child: pw.Text(
                              r.dateLabel,
                              style: pw.TextStyle(font: bold, fontSize: 10),
                            ),
                          ),
                          pw.Text(
                            r.premium,
                            style: pw.TextStyle(
                              font: bold,
                              fontSize: 10,
                              color: restAccent,
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        r.timeLabel,
                        style: pw.TextStyle(
                          font: regular,
                          fontSize: 9,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          pw.SizedBox(height: 10),
          _sectionHeader('Deductions', deductionsColor, bold),
          _dataRow('Late Deduction', data.lateDeductions, regular, bold),
          _dataRow(
            'Undertime Deduction',
            data.undertimeDeductions,
            regular,
            bold,
          ),
          _dataRow('Absent Days', data.absentDays, regular, bold),
          _dataRow(
            'Attendance Deduction Total',
            data.deductionsTotal,
            regular,
            bold,
            strong: true,
          ),
          pw.SizedBox(height: 10),
          _sectionHeader('Payroll Adjustments', adjustmentsColor, bold),
          if (data.adjustments.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 8),
              child: pw.Text(
                'No payroll adjustments for this period.',
                style: pw.TextStyle(font: regular, fontSize: 10, color: muted),
              ),
            )
          else
            ...data.adjustments.map(
              (a) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _dataRow(a.label, a.amount, regular, bold),
                  if ((a.description ?? '').trim().isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 6),
                      child: pw.Text(
                        a.description!,
                        style: pw.TextStyle(
                          font: regular,
                          fontSize: 9,
                          color: muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          pw.SizedBox(height: 10),
          _sectionHeader('NET PAY', netColor, bold),
          _dataRow('Base Net Pay', data.baseNetPay, regular, bold),
          _dataRow(
            'Final Net Pay',
            data.finalNetPay,
            regular,
            bold,
            strong: true,
          ),
        ];
      },
    ),
  );

  return doc.save();
}

Future<String> saveStandardPayslipPdf(
  StandardPayslipPdfData data, {
  bool sample = false,
  String? fileNameHint,
}) async {
  final bytes = await buildStandardPayslipPdfBytes(data, sample: sample);
  final safe = (fileNameHint ?? data.employeeName)
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '-');
  final dir = await getTemporaryDirectory();
  final file = File(
    '${dir.path}/$safe-payslip-${DateTime.now().millisecondsSinceEpoch}.pdf',
  );
  await file.writeAsBytes(bytes);
  return file.path;
}

pw.Widget _sectionHeader(String title, PdfColor color, pw.Font bold) {
  return pw.Container(
    width: double.infinity,
    margin: const pw.EdgeInsets.only(bottom: 6),
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    color: color,
    child: pw.Text(
      title,
      style: pw.TextStyle(font: bold, fontSize: 11),
    ),
  );
}

pw.Widget _dataRow(
  String label,
  String value,
  pw.Font regular,
  pw.Font bold, {
  bool strong = false,
}) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 7),
    decoration: pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(
          color: PdfColor.fromInt(0xFFE5E7EB),
          width: 0.6,
        ),
      ),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 5,
          child: pw.Text(
            label,
            style: pw.TextStyle(font: regular, fontSize: 11),
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          flex: 5,
          child: pw.Text(
            value,
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              font: strong ? bold : regular,
              fontSize: 11,
            ),
          ),
        ),
      ],
    ),
  );
}

String _hhmm(DateTime? value) {
  if (value == null) return '--:--';
  return '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

String _hhmmIso(String iso) {
  if (iso.isEmpty) return '--:--';
  final parsed = DateTime.tryParse(iso);
  return _hhmm(parsed);
}

String _fmtDate(String iso) {
  if (iso.isEmpty) return '--';
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;
  return DateFormat('MMM d, yyyy').format(parsed);
}
