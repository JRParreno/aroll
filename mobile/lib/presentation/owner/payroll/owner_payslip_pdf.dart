import 'package:aroll_mobile/presentation/shared/standard_payslip_pdf.dart';

/// Owner Mobile PDF — same standard Employee payslip format.
Future<String> generateOwnerPayslipPdf({
  required Map<String, dynamic> payslip,
  required String businessName,
  bool sample = false,
}) {
  return saveStandardPayslipPdf(
    StandardPayslipPdfData.fromOwnerMap(
      payslip,
      businessName: businessName,
    ),
    sample: sample,
    fileNameHint: '${payslip['employee_name'] ?? 'employee'}',
  );
}
