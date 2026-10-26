/**
 * Presentation-only Shift History pay-component lines.
 * Maps existing authoritative attendance-row fields — does not recalculate payroll.
 *
 * Holiday pay is shown only when the backend sent `holiday_pay`.
 * Do not derive it from a rate or multiplier.
 * Payroll adjustment allowances / deductions stay period-level and are not shown here.
 */

export type ShiftPayLine = {
  key: string;
  label: string;
  amount: number;
  kind: "additional" | "deduction";
};

function asPositiveAmount(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  if (value <= 0) return null;
  return value;
}

function asNonNegativeMinutes(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  if (value <= 0) return null;
  return value;
}

/** Authoritative minute count for a label.
 * Whole values drop the decimal. Fractional values keep two places.
 */
export function formatMinuteCount(minutes: number): string {
  const rounded = Math.round(minutes * 100) / 100;
  if (rounded % 1 === 0) return String(rounded);
  return rounded.toFixed(2);
}

/** Payslip late row. The peso amount stays on the value column from the API. */
export function latePayslipLabel(
  lateMinutes: number | null | undefined,
  ratePerMinute: number | null | undefined
): string {
  const minutes = Number(lateMinutes);
  if (!Number.isFinite(minutes) || minutes === 0) return "Late Deduction";
  const rate = Number(ratePerMinute ?? 0);
  const rateText = Number.isFinite(rate) ? rate.toFixed(2) : "0.00";
  return `Late (${formatMinuteCount(minutes)} min × ₱${rateText})`;
}

export type ShiftPayBreakdownSource = {
  overtime_pay?: number | null;
  overtime_minutes?: number | null;
  rest_day_premium_pay?: number | null;
  /** Owner API alias of rest premium only — used when rest_day_premium_pay is absent. */
  additional_pay?: number | null;
  holiday_pay?: number | null;
  late_deduction?: number | null;
  late_minutes?: number | null;
  undertime_deduction?: number | null;
  undertime_minutes?: number | null;
};

/** Positive components that explain (but never replace) authoritative Shift Net. */
export function buildAdditionalPayLines(
  source: ShiftPayBreakdownSource
): ShiftPayLine[] {
  const lines: ShiftPayLine[] = [];
  const otPay = asPositiveAmount(source.overtime_pay);
  if (otPay != null) {
    const mins = asNonNegativeMinutes(source.overtime_minutes);
    lines.push({
      key: "overtime",
      label:
        mins != null
          ? `Overtime (${Math.round(mins)} min)`
          : "Overtime",
      amount: otPay,
      kind: "additional",
    });
  }

  const holiday = asPositiveAmount(source.holiday_pay);
  if (holiday != null) {
    lines.push({
      key: "holiday",
      label: "Holiday Pay",
      amount: holiday,
      kind: "additional",
    });
  }

  const rest =
    asPositiveAmount(source.rest_day_premium_pay) ??
    asPositiveAmount(source.additional_pay);
  if (rest != null) {
    lines.push({
      key: "rest_day",
      label: "Rest-Day Premium",
      amount: rest,
      kind: "additional",
    });
  }

  return lines;
}

/**
 * Negative components from authoritative late/undertime fields only.
 * Does not emit aggregate `shift_deductions` (would double-count late+undertime).
 */
export function buildDeductionLines(
  source: ShiftPayBreakdownSource
): ShiftPayLine[] {
  const lines: ShiftPayLine[] = [];
  const latePay = asPositiveAmount(source.late_deduction);
  const lateMins = asNonNegativeMinutes(source.late_minutes);
  if (latePay != null || lateMins != null) {
    lines.push({
      key: "late",
      label:
        lateMins != null
          ? `Late (${formatMinuteCount(lateMins)} min)`
          : "Late",
      amount: latePay ?? 0,
      kind: "deduction",
    });
  }

  const utPay = asPositiveAmount(source.undertime_deduction);
  const utMins = asNonNegativeMinutes(source.undertime_minutes);
  if (utPay != null || utMins != null) {
    lines.push({
      key: "undertime",
      label:
        utMins != null
          ? `Undertime (${Math.round(utMins)} min)`
          : "Undertime",
      amount: utPay ?? 0,
      kind: "deduction",
    });
  }

  return lines;
}
