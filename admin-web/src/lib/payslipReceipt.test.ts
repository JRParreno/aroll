import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { EmployeePayslip } from "@/lib/api";
import { payslipRateFieldAmounts } from "@/lib/salaryRate";
import {
  PAYSLIP_RECEIPT_WIDTH_PT,
  buildStandardPayslipPdfBytes,
  payslipReceiptEarningsRows,
} from "@/lib/standardPayslipPdf";

function slip(overrides: Partial<EmployeePayslip> = {}): EmployeePayslip {
  return {
    employee_id: "e1",
    employee_name: "Sample Emp",
    position_title: "Cashier",
    employment_type: "full_time",
    period_start: "2026-08-01",
    period_end: "2026-08-15",
    daily_rate: 350,
    pay_basis: "daily",
    hourly_rate: null,
    worked_days: 2,
    hours_worked: 8,
    overtime_minutes: 0,
    overtime_hours: 0,
    overtime_pay: 0,
    regular_pay: 700,
    leave_pay: 0,
    holiday_pay: 0,
    rest_day_pay: 35,
    rest_day_premium_percent: 10,
    rest_day_records: [
      {
        date: "2026-08-02",
        weekday: "sunday",
        status: "complete",
        time_in: "2026-08-02T10:00:00Z",
        time_out: "2026-08-02T18:00:00Z",
        shift_name: "Evening",
        premium_percent: 10,
        premium_pay: 35,
      },
    ],
    deductions: 0,
    late_deductions: 0,
    undertime_deductions: 0,
    absent_days: 0,
    gross_pay: 735,
    net_pay: 735,
    ...overrides,
  };
}

describe("downloaded payslip receipt content", () => {
  it("keeps rest-day earnings and omits rest-day attendance details", () => {
    const rows = payslipReceiptEarningsRows(slip());
    expect(rows.find((row) => row.label.startsWith("Rest Day Premium"))?.value).toBe(
      "₱35.00"
    );
    expect(rows.some((row) => row.label === "Gross Pay")).toBe(true);
    expect(rows.some((row) => row.label.includes("Rest Day Work"))).toBe(false);
    expect(rows.some((row) => row.value.includes("2026-08-02"))).toBe(false);
    expect(rows.some((row) => row.label === "Days worked")).toBe(false);
  });

  it("shows daily rate and leaves hourly blank", () => {
    const amounts = payslipRateFieldAmounts(
      slip({ pay_basis: "daily", daily_rate: 350, hourly_rate: 80 })
    );
    expect(amounts.daily).toBe(350);
    expect(amounts.hourly).toBeNull();
    const rows = payslipReceiptEarningsRows(
      slip({ pay_basis: "daily", daily_rate: 350, hourly_rate: 80 })
    );
    expect(rows.find((row) => row.label === "Daily Rate")?.value).toBe("₱350.00");
    expect(rows.find((row) => row.label === "Hourly Rate")?.value).toBe("");
  });

  it("shows hourly rate and leaves daily blank", () => {
    const amounts = payslipRateFieldAmounts(
      slip({ pay_basis: "hourly", daily_rate: 650, hourly_rate: 100 })
    );
    expect(amounts.daily).toBeNull();
    expect(amounts.hourly).toBe(100);
    const rows = payslipReceiptEarningsRows(
      slip({ pay_basis: "hourly", daily_rate: 650, hourly_rate: 100 })
    );
    expect(rows.find((row) => row.label === "Hourly Rate")?.value).toBe("₱100.00");
    expect(rows.find((row) => row.label === "Daily Rate")?.value).toBe("");
  });

  it("shows both rates when the basis is not exclusive", () => {
    const amounts = payslipRateFieldAmounts({
      pay_basis: "",
      daily_rate: 350,
      hourly_rate: 100,
    });
    expect(amounts.daily).toBe(350);
    expect(amounts.hourly).toBe(100);
  });

  it("leaves missing rates blank instead of inventing a value", () => {
    const amounts = payslipRateFieldAmounts({
      pay_basis: "daily",
      daily_rate: null,
      hourly_rate: null,
    });
    expect(amounts.daily).toBeNull();
    expect(amounts.hourly).toBeNull();
    const rows = payslipReceiptEarningsRows(
      slip({ daily_rate: 0 as unknown as number, hourly_rate: null })
    );
    expect(rows.find((row) => row.label === "Daily Rate")?.value).toBe("");
    expect(rows.find((row) => row.label === "Hourly Rate")?.value).toBe("");
  });

  it("uses a narrow receipt width", () => {
    expect(PAYSLIP_RECEIPT_WIDTH_PT).toBeLessThan(400);
    expect(PAYSLIP_RECEIPT_WIDTH_PT).toBeGreaterThan(200);
  });

  it("generates a receipt-sized PDF without rest-day attendance dates", async () => {
    const regular = readFileSync(
      resolve(__dirname, "../../public/fonts/NotoSans-Regular.ttf")
    );
    const bold = readFileSync(
      resolve(__dirname, "../../public/fonts/NotoSans-Bold.ttf")
    );
    vi.stubGlobal("fetch", async (input: RequestInfo) => {
      const url = String(input);
      const file = url.includes("Bold") ? bold : regular;
      return {
        ok: true,
        arrayBuffer: async () =>
          file.buffer.slice(file.byteOffset, file.byteOffset + file.byteLength),
      } as Response;
    });

    const bytes = await buildStandardPayslipPdfBytes({
      payslip: slip(),
      businessName: "Cafe",
    });
    const latin1 = Buffer.from(bytes).toString("latin1");
    expect(latin1.startsWith("%PDF")).toBe(true);
    expect(latin1).not.toContain("Rest Day Work");
    expect(latin1).not.toContain("2026-08-02");
    expect(latin1).not.toMatch(/\/MediaBox\s*\[\s*0\s+0\s+612\s+792\s*\]/);
    const media = latin1.match(
      /\/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]/
    );
    expect(media).not.toBeNull();
    expect(Number(media?.[1])).toBeCloseTo(PAYSLIP_RECEIPT_WIDTH_PT, 0);
    expect(Number(media?.[2])).toBeGreaterThan(300);
  });
});

afterEach(() => {
  vi.unstubAllGlobals();
});
