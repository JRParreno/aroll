import jsPDF from "jspdf";
import { payslipRateFieldAmounts } from "@/lib/salaryRate";
import type { EmployeePayslip } from "@/lib/api";
import {
  PAYSLIP_SAMPLE_LINE_1,
  PAYSLIP_SAMPLE_LINE_2,
} from "@/lib/tenantMode";

/** Shared Aroll+ payslip PDF — mirrors Employee Mobile payslip layout. */

function money(value: number) {
  const amount = new Intl.NumberFormat("en-PH", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(value);
  return `₱${amount}`;
}

/** Narrow receipt width in points (~4.17 in). Height is fitted to content. */
export const PAYSLIP_RECEIPT_WIDTH_PT = 300;

export type PayslipReceiptRow = { label: string; value: string };

/** Authoritative downloaded-payslip rows used by the receipt renderer. */
export function payslipReceiptEarningsRows(
  payslip: EmployeePayslip
): PayslipReceiptRow[] {
  const restPct = Number(payslip.rest_day_premium_percent ?? 0);
  const rates = payslipRateFieldAmounts(payslip);
  return [
    { label: "Daily Rate", value: rateOrBlank(rates.daily) },
    { label: "Hourly Rate", value: rateOrBlank(rates.hourly) },
    { label: "Basic Salary", value: money(payslip.regular_pay ?? 0) },
    { label: "Leave Pay", value: money(payslip.leave_pay ?? 0) },
    { label: "Overtime", value: money(payslip.overtime_pay) },
    { label: "Holiday Pay", value: money(payslip.holiday_pay) },
    {
      label:
        restPct > 0
          ? `Rest Day Premium (${restPct}%)`
          : "Rest Day Premium",
      value: money(payslip.rest_day_pay ?? 0),
    },
    { label: "Gross Pay", value: money(payslip.gross_pay) },
  ];
}

function rateOrBlank(amount: number | null): string {
  return amount == null ? "" : money(amount);
}

function titleCase(value: string) {
  return value
    .replaceAll("_", " ")
    .split(" ")
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function formatPeriodDate(iso: string) {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

function hexToRgb(hex: string): [number, number, number] {
  const raw = hex.replace("#", "").trim();
  const full =
    raw.length === 3
      ? raw
          .split("")
          .map((c) => c + c)
          .join("")
      : raw.padEnd(6, "0").slice(0, 6);
  const n = Number.parseInt(full, 16);
  if (Number.isNaN(n)) return [229, 231, 235];
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

function arrayBufferToBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

let cachedRegularB64: string | null = null;
let cachedBoldB64: string | null = null;

async function ensureNotoFonts(doc: jsPDF): Promise<void> {
  if (!cachedRegularB64 || !cachedBoldB64) {
    const [regularBuf, boldBuf] = await Promise.all([
      fetch("/fonts/NotoSans-Regular.ttf").then((r) => {
        if (!r.ok) throw new Error("Missing NotoSans-Regular.ttf");
        return r.arrayBuffer();
      }),
      fetch("/fonts/NotoSans-Bold.ttf").then((r) => {
        if (!r.ok) throw new Error("Missing NotoSans-Bold.ttf");
        return r.arrayBuffer();
      }),
    ]);
    cachedRegularB64 = arrayBufferToBase64(regularBuf);
    cachedBoldB64 = arrayBufferToBase64(boldBuf);
  }
  doc.addFileToVFS("NotoSans-Regular.ttf", cachedRegularB64);
  doc.addFont("NotoSans-Regular.ttf", "NotoSans", "normal");
  doc.addFileToVFS("NotoSans-Bold.ttf", cachedBoldB64);
  doc.addFont("NotoSans-Bold.ttf", "NotoSans", "bold");
  doc.setFont("NotoSans", "normal");
}

export type StandardPayslipPdfOptions = {
  payslip: EmployeePayslip;
  businessName: string;
  sample?: boolean;
};

/**
 * Downloads the standard Employee-format payslip PDF.
 * Used by Owner Web (and any Employee Web caller).
 */
function renderStandardPayslip(
  doc: jsPDF,
  {
    payslip,
    businessName,
    sample = false,
  }: StandardPayslipPdfOptions
): number {
  const pageWidth = doc.internal.pageSize.getWidth();
  const pageHeight = doc.internal.pageSize.getHeight();
  const marginX = 16;
  const contentWidth = pageWidth - marginX * 2;
  let y = 16;

  const ensureSpace = (needed: number) => {
    if (y + needed > pageHeight - 16) {
      y += needed;
    }
  };

  const setFont = (bold = false, size = 9) => {
    doc.setFont("NotoSans", bold ? "bold" : "normal");
    doc.setFontSize(size);
  };

  const sectionHeader = (title: string, color: string) => {
    ensureSpace(22);
    y += 6;
    const [r, g, b] = hexToRgb(color);
    doc.setFillColor(r, g, b);
    doc.rect(marginX, y, contentWidth, 15, "F");
    setFont(true, 9);
    doc.setTextColor(31, 41, 55);
    doc.text(title, marginX + 6, y + 10);
    y += 18;
  };

  const dataRow = (label: string, value: string, strong = false) => {
    ensureSpace(16);
    setFont(false, 9);
    doc.setTextColor(31, 41, 55);
    const labelLines = doc.splitTextToSize(label, contentWidth * 0.52);
    const valueLines =
      value === ""
        ? [""]
        : doc.splitTextToSize(value, contentWidth * 0.44);
    const lines = Math.max(labelLines.length, valueLines.length);
    const rowH = Math.max(15, lines * 11 + 3);

    setFont(false, 9);
    doc.text(labelLines, marginX + 2, y + 10);
    setFont(strong, 9);
    if (value !== "") {
      doc.text(valueLines, marginX + contentWidth - 2, y + 10, {
        align: "right",
      });
    }
    doc.setDrawColor(229, 231, 235);
    doc.setLineWidth(0.5);
    doc.line(marginX, y + rowH - 2, marginX + contentWidth, y + rowH - 2);
    y += rowH;
  };

  // Title pill
  {
    ensureSpace(28);
    const [r, g, b] = hexToRgb("#8D8D8D");
    const pillW = 120;
    const pillX = (pageWidth - pillW) / 2;
    doc.setFillColor(r, g, b);
    doc.roundedRect(pillX, y, pillW, 18, 9, 9, "F");
    setFont(true, 10);
    doc.setTextColor(255, 255, 255);
    doc.text(sample ? "SAMPLE PAYSLIP" : "PAYSLIP", pageWidth / 2, y + 15, {
      align: "center",
    });
    y += 34;
  }

  if (sample) {
    ensureSpace(40);
    doc.setFillColor(255, 247, 237);
    doc.setDrawColor(254, 215, 170);
    doc.roundedRect(marginX, y, contentWidth, 34, 6, 6, "FD");
    setFont(true, 9);
    doc.setTextColor(154, 52, 18);
    doc.text(PAYSLIP_SAMPLE_LINE_1, pageWidth / 2, y + 13, { align: "center" });
    doc.setTextColor(194, 65, 12);
    doc.text(PAYSLIP_SAMPLE_LINE_2, pageWidth / 2, y + 26, { align: "center" });
    y += 46;
  }

  setFont(true, 11);
  doc.setTextColor(31, 41, 55);
  doc.text(businessName, pageWidth / 2, y, { align: "center" });
  y += 10;
  doc.setDrawColor(209, 213, 219);
  doc.setLineWidth(0.8);
  doc.line(marginX, y, marginX + contentWidth, y);
  y += 8;

  const payDate = payslip.period_end;

  sectionHeader("Employee Information", "#E5E7EB");
  dataRow("Employee Name", payslip.employee_name);
  dataRow("No. of Working Days", `${payslip.worked_days}`);
  dataRow(
    "Period Date",
    `${formatPeriodDate(payslip.period_start)} - ${formatPeriodDate(payslip.period_end)}`
  );
  dataRow("Pay Date", formatPeriodDate(payDate));
  dataRow("Payroll Status", "Current");
  dataRow("Position", payslip.position_title ?? "Employee");
  dataRow("Employment Type", titleCase(payslip.employment_type));
  dataRow("Hours Worked", Number(payslip.hours_worked ?? 0).toFixed(1));
  if (payslip.has_unresolved_historical_rate) {
    ensureSpace(28);
    doc.setFillColor(255, 251, 235);
    doc.setDrawColor(253, 230, 138);
    doc.roundedRect(marginX, y, contentWidth, 24, 4, 4, "FD");
    setFont(true, 8);
    doc.setTextColor(146, 64, 14);
    doc.text(
      "Note: Completed attendance with unresolved historical pay rate. Totals exclude unresolved days.",
      marginX + 6,
      y + 15
    );
    y += 32;
  }

  sectionHeader("Earnings/Income", "#FFE681");
  for (const row of payslipReceiptEarningsRows(payslip)) {
    dataRow(row.label, row.value, row.label === "Gross Pay");
  }

  sectionHeader("Deductions", "#FFC5C5");
  dataRow("Late Deduction", money(payslip.late_deductions ?? 0));
  dataRow("Undertime Deduction", money(payslip.undertime_deductions ?? 0));
  dataRow("Absent Days", `${payslip.absent_days}`);
  dataRow("Attendance Deduction Total", money(payslip.deductions), true);

  sectionHeader("Payroll Adjustments", "#FDE68A");
  if ((payslip.payroll_adjustments?.length ?? 0) === 0) {
    ensureSpace(18);
    setFont(false, 10);
    doc.setTextColor(107, 114, 128);
    doc.text("No payroll adjustments for this period.", marginX + 2, y + 10);
    y += 18;
  } else {
    for (const item of payslip.payroll_adjustments ?? []) {
      dataRow(
        `${item.display_name}${item.kind === "allowance" ? " (+)" : " (−)"}`,
        money(item.amount)
      );
      if (item.description) {
        ensureSpace(14);
        setFont(false, 9);
        doc.setTextColor(107, 114, 128);
        doc.text(item.description, marginX + 2, y + 8);
        y += 14;
      }
    }
  }

  sectionHeader("NET PAY", "#C8F7CE");
  dataRow("Base Net Pay", money(payslip.base_net_pay ?? payslip.net_pay));
  dataRow(
    "Final Net Pay",
    money(payslip.final_net_pay ?? payslip.net_pay),
    true
  );

  return y;
}

function createReceiptDoc(height: number): jsPDF {
  return new jsPDF({
    unit: "pt",
    format: [PAYSLIP_RECEIPT_WIDTH_PT, height],
  });
}

export async function downloadStandardPayslipPdf({
  payslip,
  businessName,
  sample = false,
}: StandardPayslipPdfOptions): Promise<void> {
  const probe = createReceiptDoc(4000);
  await ensureNotoFonts(probe);
  const contentBottom = renderStandardPayslip(probe, {
    payslip,
    businessName,
    sample,
  });
  const height = Math.max(contentBottom + 18, 360);
  const doc = createReceiptDoc(height);
  await ensureNotoFonts(doc);
  renderStandardPayslip(doc, { payslip, businessName, sample });
  doc.save(
    `${payslip.employee_name.replace(/\s+/g, "-").toLowerCase()}-payslip.pdf`
  );
}

/** Builds receipt-style payslip PDF bytes for tests. */
export async function buildStandardPayslipPdfBytes(
  options: StandardPayslipPdfOptions
): Promise<Uint8Array> {
  const probe = createReceiptDoc(4000);
  await ensureNotoFonts(probe);
  const contentBottom = renderStandardPayslip(probe, options);
  const height = Math.max(contentBottom + 18, 360);
  const doc = createReceiptDoc(height);
  await ensureNotoFonts(doc);
  renderStandardPayslip(doc, options);
  return doc.output("arraybuffer") as unknown as Uint8Array;
}
