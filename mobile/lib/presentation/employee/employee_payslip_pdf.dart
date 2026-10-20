import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/presentation/shared/standard_payslip_pdf.dart';

/// Employee Mobile PDF — uses the shared Employee payslip format.
Future<String> generateEmployeePayslipPdf({
  required EmployeePayslip payslip,
  bool sample = false,
}) {
  return saveStandardPayslipPdf(
    StandardPayslipPdfData.fromEmployee(payslip),
    sample: sample,
    fileNameHint: payslip.employeeName,
  );
}
