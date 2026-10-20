import { describe, expect, it } from "vitest";
import {
  buildAdditionalPayLines,
  buildDeductionLines,
} from "./shiftHistoryPayBreakdown";
import { presentShiftPay, type ShiftHistoryPayItem } from "./shiftHistoryGrouping";

type SummaryItem = ShiftHistoryPayItem & {
  overtime_pay?: number | null;
  overtime_minutes?: number | null;
  late_minutes?: number | null;
  undertime_deduction?: number | null;
};

function dailyRow(overrides: Partial<SummaryItem> = {}): SummaryItem {
  return {
    employee_id: "emp-1",
    date: "2026-08-04",
    expected_salary_pay: 350,
    pay_basis_used: "daily",
    status: "late",
    earned: 315.99,
    rest_day_premium_pay: null,
    holiday_pay: 0,
    day_rest_day_pay: 0,
    day_holiday_pay: 0,
    late_deduction: 0,
    late_minutes: 0,
    undertime_deduction: 0,
    overtime_pay: 0,
    overtime_minutes: 0,
    shift_net: 350,
    reconciled_shift_total: 350,
    holiday_included_in_shift_net: false,
    ...overrides,
  };
}

function summaryLines(item: SummaryItem) {
  const face = presentShiftPay(item, [item]);
  return {
    face,
    additional: buildAdditionalPayLines({
      ...item,
      holiday_pay: face.holidayPay,
      rest_day_premium_pay: face.restPay,
      additional_pay: null,
    }),
    deductions: buildDeductionLines(item),
  };
}

describe("shift history pay summary components", () => {
  it("shows a late deduction when only lateness applies", () => {
    const { additional, deductions, face } = summaryLines(
      dailyRow({
        late_deduction: 20,
        late_minutes: 20,
        shift_net: 330,
        reconciled_shift_total: 330,
      })
    );
    expect(additional).toEqual([]);
    expect(deductions).toEqual([
      { key: "late", label: "Late (20 min)", amount: 20, kind: "deduction" },
    ]);
    expect(face.shiftTotal).toBe(330);
  });

  it("shows overtime pay when only overtime applies", () => {
    const { additional, deductions, face } = summaryLines(
      dailyRow({
        status: "complete",
        overtime_pay: 60,
        overtime_minutes: 60,
        shift_net: 410,
        reconciled_shift_total: 410,
      })
    );
    expect(additional.map((line) => line.key)).toEqual(["overtime"]);
    expect(additional[0].amount).toBe(60);
    expect(deductions).toEqual([]);
    expect(face.shiftTotal).toBe(410);
  });

  it("shows late and overtime together on the same shift", () => {
    const { additional, deductions, face } = summaryLines(
      dailyRow({
        late_deduction: 20,
        late_minutes: 20,
        overtime_pay: 60,
        overtime_minutes: 60,
        shift_net: 390,
        reconciled_shift_total: 390,
      })
    );
    expect(additional.map((line) => line.key)).toEqual(["overtime"]);
    expect(deductions.map((line) => line.key)).toEqual(["late"]);
    expect(face.earned).toBe(350);
    expect(face.shiftTotal).toBe(390);
  });

  it("shows rest-day premium only when that is the only extra", () => {
    const { additional, deductions, face } = summaryLines(
      dailyRow({
        status: "complete",
        day_rest_day_pay: 35,
        reconciled_day_total: 385,
      })
    );
    expect(additional).toEqual([
      {
        key: "rest_day",
        label: "Rest-Day Premium",
        amount: 35,
        kind: "additional",
      },
    ]);
    expect(deductions).toEqual([]);
    expect(face.restPay).toBe(35);
    expect(face.shiftTotal).toBe(385);
  });

  it("shows late, overtime, and rest-day premium together without duplicating rest", () => {
    const item = dailyRow({
      late_deduction: 20,
      late_minutes: 20,
      overtime_pay: 60,
      overtime_minutes: 60,
      day_rest_day_pay: 35,
      rest_day_premium_pay: null,
      shift_net: 390,
      reconciled_shift_total: 390,
      reconciled_day_total: 425,
    });
    const { additional, deductions, face } = summaryLines(item);
    expect(additional.map((line) => line.key)).toEqual(["overtime", "rest_day"]);
    expect(additional.filter((line) => line.key === "rest_day")).toHaveLength(1);
    expect(additional.find((line) => line.key === "rest_day")?.amount).toBe(35);
    expect(deductions.map((line) => line.key)).toEqual(["late"]);
    expect(face.shiftTotal).toBe(425);
    expect(350 + 60 + 35 - 20).toBe(face.shiftTotal);
  });

  it("omits late when the punch is inside grace (zero late minutes and pay)", () => {
    const { deductions } = summaryLines(
      dailyRow({
        status: "complete",
        late_deduction: 0,
        late_minutes: 0,
      })
    );
    expect(deductions.find((line) => line.key === "late")).toBeUndefined();
  });

  it("omits overtime pay when overtime is not payable", () => {
    const { additional } = summaryLines(
      dailyRow({
        overtime_pay: 0,
        overtime_minutes: 0,
      })
    );
    expect(additional.find((line) => line.key === "overtime")).toBeUndefined();
  });

  it("does not change or duplicate rest-day premium when late and overtime are present", () => {
    const restOnly = summaryLines(
      dailyRow({
        status: "complete",
        day_rest_day_pay: 35,
      })
    );
    const withLateOt = summaryLines(
      dailyRow({
        late_deduction: 20,
        late_minutes: 20,
        overtime_pay: 60,
        overtime_minutes: 60,
        day_rest_day_pay: 35,
        shift_net: 390,
        reconciled_shift_total: 390,
      })
    );
    expect(restOnly.face.restPay).toBe(35);
    expect(withLateOt.face.restPay).toBe(35);
    expect(
      withLateOt.additional.filter((line) => line.key === "rest_day")
    ).toHaveLength(1);
  });

  it("keeps shift total equal to entitlement plus extras minus deductions", () => {
    const { additional, deductions, face } = summaryLines(
      dailyRow({
        late_deduction: 20,
        late_minutes: 20,
        overtime_pay: 60,
        overtime_minutes: 60,
        day_rest_day_pay: 35,
        shift_net: 390,
        reconciled_shift_total: 390,
      })
    );
    const extras = additional.reduce((sum, line) => sum + line.amount, 0);
    const taken = deductions.reduce((sum, line) => sum + line.amount, 0);
    expect((face.earned ?? 0) + extras - taken).toBe(face.shiftTotal);
  });
});
