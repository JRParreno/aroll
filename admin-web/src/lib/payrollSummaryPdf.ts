import jsPDF from "jspdf";
import autoTable from "jspdf-autotable";
import { payslipRateFieldAmounts, type SalaryRateFields } from "./salaryRate.ts";

/** Fields already stored on a finalized payslip. No amounts are recalculated. */
export type PayrollSummarySource = SalaryRateFields & {
  employee_id: string;
  employee_name: string;
  period_start: string;
  period_end: string;
  worked_days?: number | null;
  regular_pay?: number | null;
  leave_pay?: number | null;
  overtime_pay?: number | null;
  /** Attendance deductions (late + undertime). Excludes adjustment deductions. */
  deductions?: number | null;
  holiday_pay?: number | null;
  rest_day_pay?: number | null;
  payroll_adjustments_allowance_total?: number | null;
  payroll_adjustments_deduction_total?: number | null;
  gross_pay?: number | null;
  net_pay?: number | null;
  final_net_pay?: number | null;
};

export type PayrollSummaryRow = {
  employeeName: string;
  dailyRate: string;
  hourlyRate: string;
  workedDays: string;
  regularPay: string;
  overtimePay: string;
  deductions: string;
  restDayPay: string;
  holidayPay: string;
  additionalPay: string;
  grossPay: string;
  netPay: string;
};

const COLUMNS = [
  "Employee Name",
  "Daily Rate",
  "Hourly Rate",
  "Worked Days",
  "Regular Pay",
  "Overtime Pay",
  "Deductions",
  "Rest Day Pay",
  "Holiday Pay",
  "Additional Pay",
  "Gross Pay",
  "Net Pay",
] as const;

const MONTHS = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
] as const;

function amount(value: number | null | undefined) {
  const n = Number(value ?? 0);
  return Number.isFinite(n) ? n : 0;
}

export function formatPayrollMoney(value: number) {
  return new Intl.NumberFormat("en-PH", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(value);
}

export function formatPayrollReportDate(iso: string) {
  const [year, month, day] = iso.slice(0, 10).split("-");
  const monthIndex = Number(month) - 1;
  const monthLabel = MONTHS[monthIndex] ?? month;
  const dayNumber = Number(day);
  if (!year || !monthLabel || !Number.isFinite(dayNumber)) return iso.slice(0, 10);
  return `${dayNumber} ${monthLabel} ${year}`;
}

function rateText(value: number | null) {
  return value == null ? "" : formatPayrollMoney(value);
}

function workedDaysText(value: number | null | undefined) {
  const n = Number(value ?? 0);
  if (!Number.isFinite(n)) return "0";
  return Number.isInteger(n) ? String(n) : n.toFixed(2);
}

/**
 * Attendance deductions and adjustment deductions are stored separately.
 * Adding them is the total deducted from this payslip, not a new pay formula.
 * Allowances stay in Additional Pay and are not included in Gross Pay.
 */
export function payrollSummaryDeductions(source: PayrollSummarySource) {
  return amount(source.deductions) + amount(source.payroll_adjustments_deduction_total);
}

export function payrollSummaryNetPay(source: PayrollSummarySource) {
  if (source.final_net_pay != null && Number.isFinite(Number(source.final_net_pay))) {
    return Number(source.final_net_pay);
  }
  return amount(source.net_pay);
}

export function payrollSummaryRows(sources: PayrollSummarySource[]): PayrollSummaryRow[] {
  return sources.map((source) => {
    const rates = payslipRateFieldAmounts(source);
    return {
      employeeName: source.employee_name,
      dailyRate: rateText(rates.daily),
      hourlyRate: rateText(rates.hourly),
      workedDays: workedDaysText(source.worked_days),
      regularPay: formatPayrollMoney(amount(source.regular_pay)),
      overtimePay: formatPayrollMoney(amount(source.overtime_pay)),
      deductions: formatPayrollMoney(payrollSummaryDeductions(source)),
      restDayPay: formatPayrollMoney(amount(source.rest_day_pay)),
      holidayPay: formatPayrollMoney(amount(source.holiday_pay)),
      additionalPay: formatPayrollMoney(amount(source.payroll_adjustments_allowance_total)),
      grossPay: formatPayrollMoney(amount(source.gross_pay)),
      netPay: formatPayrollMoney(payrollSummaryNetPay(source)),
    };
  });
}

export function payrollSummaryFilename(periodStart: string, periodEnd: string) {
  return `Payroll_Summary_${periodStart}_to_${periodEnd}.pdf`;
}

export function downloadPayrollSummaryPdf({
  businessName,
  periodStart,
  periodEnd,
  finalizedAt,
  generatedOn,
  sources,
}: {
  businessName: string;
  periodStart: string;
  periodEnd: string;
  finalizedAt?: string | null;
  generatedOn: string;
  sources: PayrollSummarySource[];
}) {
  const rows = payrollSummaryRows(sources);
  const doc = new jsPDF({ orientation: "landscape", unit: "mm", format: "a4" });
  const pageWidth = doc.internal.pageSize.getWidth();
  const margin = 14;
  const periodLabel = `${formatPayrollReportDate(periodStart)} to ${formatPayrollReportDate(periodEnd)}`;
  const finalizedLabel = finalizedAt
    ? `Finalized on ${formatPayrollReportDate(finalizedAt)}`
    : "Finalized";

  doc.setFont("helvetica", "bold");
  doc.setFontSize(16);
  doc.setTextColor(17, 24, 39);
  doc.text(businessName || "Business", margin, 16);

  doc.setFontSize(13);
  doc.setTextColor(30, 58, 95);
  doc.text("Payroll Summary Report", margin, 23);

  doc.setFont("helvetica", "normal");
  doc.setFontSize(9);
  doc.setTextColor(75, 85, 99);
  doc.text(`Pay period: ${periodLabel}`, margin, 30);
  doc.text(finalizedLabel, margin, 35);
  doc.text(`Prepared: ${formatPayrollReportDate(generatedOn)}`, margin, 40);
  doc.text("Currency: PHP", margin, 45);

  autoTable(doc, {
    startY: 50,
    margin: { top: 16, right: margin, bottom: 14, left: margin },
    head: [COLUMNS.slice()],
    body: rows.map((row) => [
      row.employeeName,
      row.dailyRate,
      row.hourlyRate,
      row.workedDays,
      row.regularPay,
      row.overtimePay,
      row.deductions,
      row.restDayPay,
      row.holidayPay,
      row.additionalPay,
      row.grossPay,
      row.netPay,
    ]),
    showHead: "everyPage",
    rowPageBreak: "avoid",
    styles: {
      font: "helvetica",
      fontSize: 8,
      cellPadding: { top: 2.4, right: 2, bottom: 2.4, left: 2 },
      valign: "middle",
      textColor: [31, 41, 55],
      lineColor: [226, 232, 240],
      lineWidth: 0.15,
      overflow: "linebreak",
    },
    headStyles: {
      fillColor: [30, 58, 95],
      textColor: [255, 255, 255],
      font: "helvetica",
      fontStyle: "bold",
      fontSize: 7.5,
      halign: "center",
      valign: "middle",
      cellPadding: { top: 3, right: 2, bottom: 3, left: 2 },
    },
    columnStyles: {
      0: { cellWidth: 36, halign: "left" },
      1: { cellWidth: 21, halign: "right" },
      2: { cellWidth: 21, halign: "right" },
      3: { cellWidth: 16, halign: "right" },
      4: { cellWidth: 21, halign: "right" },
      5: { cellWidth: 21, halign: "right" },
      6: { cellWidth: 21, halign: "right" },
      7: { cellWidth: 21, halign: "right" },
      8: { cellWidth: 21, halign: "right" },
      9: { cellWidth: 21, halign: "right" },
      10: { cellWidth: 21, halign: "right", fontStyle: "bold" },
      11: { cellWidth: 22, halign: "right", fontStyle: "bold" },
    },
    alternateRowStyles: { fillColor: [248, 250, 252] },
    didDrawPage: () => {
      const page = doc.getNumberOfPages();
      doc.setFont("helvetica", "normal");
      doc.setFontSize(8);
      doc.setTextColor(107, 114, 128);
      doc.text(
        `Page ${page}`,
        pageWidth - margin,
        doc.internal.pageSize.getHeight() - 7,
        { align: "right" }
      );
    },
  });

  doc.save(payrollSummaryFilename(periodStart, periodEnd));
}
