import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  payrollSummaryDeductions,
  payrollSummaryFilename,
  payrollSummaryNetPay,
  payrollSummaryRows,
  type PayrollSummarySource,
} from "./payrollSummaryPdf.ts";

const period = {
  period_start: "2026-10-01",
  period_end: "2026-10-15",
};

function source(overrides: Partial<PayrollSummarySource> = {}): PayrollSummarySource {
  return {
    employee_id: "emp-1",
    employee_name: "Ana Cruz",
    pay_basis: "daily",
    daily_rate: 500,
    hourly_rate: 80,
    worked_days: 10,
    regular_pay: 5000,
    leave_pay: 0,
    overtime_pay: 200,
    deductions: 50,
    holiday_pay: 0,
    rest_day_pay: 150,
    payroll_adjustments_allowance_total: 100,
    payroll_adjustments_deduction_total: 25,
    gross_pay: 5350,
    net_pay: 5300,
    final_net_pay: 5375,
    ...period,
    ...overrides,
  };
}

describe("payroll summary report mapping", () => {
  it("names the file from the selected period dates", () => {
    assert.equal(
      payrollSummaryFilename("2026-10-01", "2026-10-15"),
      "Payroll_Summary_2026-10-01_to_2026-10-15.pdf"
    );
  });

  it("keeps every employee and maps finalized payslip fields once", () => {
    const rows = payrollSummaryRows([
      source(),
      source({
        employee_id: "emp-2",
        employee_name: "Ben Santos",
        worked_days: 0,
        regular_pay: 0,
        overtime_pay: 0,
        deductions: 0,
        holiday_pay: 0,
        rest_day_pay: 0,
        payroll_adjustments_allowance_total: 0,
        payroll_adjustments_deduction_total: 0,
        gross_pay: 0,
        net_pay: 0,
        final_net_pay: 0,
      }),
    ]);

    assert.equal(rows.length, 2);
    assert.equal("employeeId" in rows[0], false);
    assert.equal(rows[0].employeeName, "Ana Cruz");
    assert.equal(rows[0].dailyRate, "500.00");
    assert.equal(rows[0].hourlyRate, "");
    assert.equal(rows[0].workedDays, "10");
    assert.equal(rows[0].regularPay, "5,000.00");
    assert.equal(rows[0].overtimePay, "200.00");
    assert.equal(rows[0].deductions, "75.00");
    assert.equal(rows[0].restDayPay, "150.00");
    assert.equal(rows[0].holidayPay, "0.00");
    assert.equal(rows[0].additionalPay, "100.00");
    assert.equal(rows[0].grossPay, "5,350.00");
    assert.equal(rows[0].netPay, "5,375.00");
    assert.equal(rows[1].employeeName, "Ben Santos");
    assert.equal(rows[1].overtimePay, "0.00");
    assert.equal(rows[1].additionalPay, "0.00");
  });

  it("shows only the stored rate for the employee's pay basis", () => {
    const [hourly] = payrollSummaryRows([
      source({ pay_basis: "hourly", daily_rate: 500, hourly_rate: 80 }),
    ]);
    assert.equal(hourly.dailyRate, "");
    assert.equal(hourly.hourlyRate, "80.00");
  });

  it("does not fold allowances into gross or attendance deductions", () => {
    const row = source();
    assert.equal(payrollSummaryDeductions(row), 75);
    assert.equal(payrollSummaryNetPay(row), 5375);
    assert.notEqual(row.gross_pay, payrollSummaryNetPay(row));
  });
});
