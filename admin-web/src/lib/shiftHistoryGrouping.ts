/**
 * Presentation-only helpers for Shift History same-day multi-shift grouping.
 * Does not recalculate payroll — only groups existing rows and sums existing
 * authoritative `shift_net` values for FINAL SHIFT NET.
 */

export type ShiftHistoryGroupable = {
  employee_id: string;
  date: string;
  shift_name?: string | null;
  scheduled_start?: string | null;
  earned?: number | null;
  shift_net?: number | null;
  historical_rate_required?: boolean;
};

export type EmployeeDayBlock<T extends ShiftHistoryGroupable> =
  | { kind: "single"; item: T }
  | { kind: "multi"; items: T[] };

export type ShiftNetSum = {
  unresolved: boolean;
  total: number | null;
  parts: number[];
};

function sortSameDayShifts<T extends ShiftHistoryGroupable>(items: T[]): T[] {
  return [...items].sort((a, b) => {
    const as = a.scheduled_start ?? a.shift_name ?? "";
    const bs = b.scheduled_start ?? b.shift_name ?? "";
    return String(as).localeCompare(String(bs));
  });
}

/** Finite number only — rejects null/undefined/NaN/Infinity/non-numbers. */
export function asFiniteShiftNet(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return null;
  }
  return value;
}

/** Group rows for one work date by employee. Multi only when count >= 2. */
export function buildEmployeeDayBlocks<T extends ShiftHistoryGroupable>(
  rows: T[]
): EmployeeDayBlock<T>[] {
  const byEmployee = new Map<string, T[]>();
  const order: string[] = [];
  for (const item of rows) {
    const id = item.employee_id;
    if (!byEmployee.has(id)) {
      byEmployee.set(id, []);
      order.push(id);
    }
    byEmployee.get(id)!.push(item);
  }
  return order.map((id) => {
    const items = sortSameDayShifts(byEmployee.get(id)!);
    if (items.length >= 2) return { kind: "multi" as const, items };
    return { kind: "single" as const, item: items[0]! };
  });
}

/**
 * FINAL SHIFT NET for a same-day multi-shift group.
 * Sums existing authoritative per-shift `shift_net` only.
 * Missing/invalid shift_net → total null (unavailable); never 0 or earned.
 */
export function sumAuthoritativeShiftNet(
  items: Array<{
    shift_net?: number | null;
    historical_rate_required?: boolean;
  }>
): ShiftNetSum {
  if (items.some((i) => i.historical_rate_required)) {
    return { unresolved: true, total: null, parts: [] };
  }
  if (items.length === 0) {
    return { unresolved: false, total: null, parts: [] };
  }
  const parts: number[] = [];
  for (const i of items) {
    const net = asFiniteShiftNet(i.shift_net);
    if (net == null) {
      // Do not partial-sum or fall back to earned / 0.
      return { unresolved: false, total: null, parts: [] };
    }
    parts.push(net);
  }
  return {
    unresolved: false,
    total: parts.reduce((a, b) => a + b, 0),
    parts,
  };
}

export type ShiftHistoryPayItem = ShiftHistoryGroupable & {
  status?: string | null;
  pay_basis_used?: string | null;
  expected_salary_pay?: number | null;
  earned?: number | null;
  holiday_included_in_shift_net?: boolean | null;
  historical_rate_required?: boolean;
  holiday_pay?: number | null;
  rest_day_premium_pay?: number | null;
  day_rest_day_pay?: number | null;
  day_holiday_pay?: number | null;
  day_entitlement?: number | null;
  late_deduction?: number | null;
  reconciled_shift_total?: number | null;
  reconciled_day_total?: number | null;
};

export type HistoryDayTotal = {
  unresolved: boolean;
  total: number | null;
  /** True when the backend sent reconciled_day_total (including an explicit null). */
  fromReconciliation: boolean;
  equation: string | null;
};

function hasReconciledDayTotal(
  item: ShiftHistoryPayItem
): boolean {
  return Object.prototype.hasOwnProperty.call(item, "reconciled_day_total");
}

/** Per-shift amount to display. Falls back to shift_net when no reconciliation field exists. */
export function displayedShiftNet(item: {
  reconciled_shift_total?: number | null;
  shift_net?: number | null;
  net_pay?: number | null;
  earned?: number | null;
}): number | null {
  if (typeof item.reconciled_shift_total === "number" && Number.isFinite(item.reconciled_shift_total)) {
    return item.reconciled_shift_total;
  }
  const fallback = item.shift_net ?? item.net_pay ?? item.earned;
  return typeof fallback === "number" && Number.isFinite(fallback) ? fallback : null;
}

/**
 * Day total for Shift History.
 * Uses the backend reconciled total when present so a daily entitlement and a
 * date-level holiday premium are counted once. Older snapshots without the
 * field keep the previous sum of shift_net.
 */
export function historyDayTotal(
  items: ShiftHistoryPayItem[],
  money: (value: number) => string
): HistoryDayTotal {
  if (items.some((item) => item.historical_rate_required)) {
    return {
      unresolved: true,
      total: null,
      fromReconciliation: false,
      equation: null,
    };
  }
  if (items.length > 0 && items.every(hasReconciledDayTotal)) {
    const raw = items[0]!.reconciled_day_total;
    const total =
      typeof raw === "number" && Number.isFinite(raw) ? raw : null;
    return {
      unresolved: false,
      total,
      fromReconciliation: true,
      equation: total == null ? null : historyDayEquation(items, total, money),
    };
  }
  const legacy = sumAuthoritativeShiftNet(items);
  const equation =
    !legacy.unresolved && legacy.parts.length >= 2 && legacy.total != null
      ? `${legacy.parts.map((part) => money(part)).join(" + ")} = ${money(legacy.total)}`
      : null;
  return {
    unresolved: legacy.unresolved,
    total: legacy.total,
    fromReconciliation: false,
    equation,
  };
}

function historyDayEquation(
  items: ShiftHistoryPayItem[],
  total: number,
  money: (value: number) => string
): string | null {
  if (workedDailyStampCount(items) >= 2) return null;
  const parts: string[] = [];
  let sum = 0;
  for (const item of items) {
    const face = presentShiftPay(item, items);
    if (face.hideShiftTotal || face.shiftTotal == null) return null;
    parts.push(money(face.shiftTotal));
    sum += face.shiftTotal;
  }
  if (parts.length < 2) return null;
  const rounded = Math.round(sum * 100) / 100;
  const canonical = Math.round(total * 100) / 100;
  if (Math.abs(rounded - canonical) > 0.02) return null;
  return `${parts.join(" + ")} = ${money(total)}`;
}

function finiteAmount(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  return Math.round(value * 100) / 100;
}

/** Worked daily completion stamp. Not leave, and not an unworked holiday credit. */
export function isWorkedDailyStamp(item: ShiftHistoryPayItem): boolean {
  if (item.historical_rate_required) return false;
  if (item.holiday_included_in_shift_net) return false;
  if ((item.status ?? "") === "on_leave") return false;
  if ((item.status ?? "") === "holiday_paid") return false;
  return (
    (item.pay_basis_used ?? "").toLowerCase() === "daily" &&
    finiteAmount(item.expected_salary_pay) != null
  );
}

export function workedDailyStampCount(items: ShiftHistoryPayItem[]): number {
  return items.filter(isWorkedDailyStamp).length;
}

export type ShiftPayFace = {
  showEarned: boolean;
  earned: number | null;
  baseLabel: string;
  /** Row rest for an hourly stamp, or the once-per-date rest on a single daily stamp. */
  restPay: number | null;
  /** Null means do not show a Holiday Pay line. */
  holidayPay: number | null;
  shiftTotal: number | null;
  /** Several daily stamps share one entitlement. Do not show a per-shift total. */
  hideShiftTotal: boolean;
};

export type DateLevelPay = {
  dailyEntitlement: number | null;
  restDayPremium: number | null;
  holidayPay: number | null;
};

function positiveAmount(value: number | null): number | null {
  if (value == null || value <= 0) return null;
  return value;
}

/** Date-level lines when two worked daily stamps share one entitlement. */
export function dateLevelPay(items: ShiftHistoryPayItem[]): DateLevelPay | null {
  if (workedDailyStampCount(items) < 2) return null;
  const daily = items.find(isWorkedDailyStamp);
  if (!daily) return null;
  return {
    dailyEntitlement: positiveAmount(finiteAmount(daily.expected_salary_pay)),
    restDayPremium: positiveAmount(finiteAmount(items[0]?.day_rest_day_pay)),
    holidayPay: positiveAmount(finiteAmount(items[0]?.day_holiday_pay)),
  };
}

export type DateAdditionalPayLine = {
  key: string;
  label: string;
  amount: number;
};

/**
 * Date-level additions for two or more daily stamps.
 * Empty for hourly, single-daily, and mixed dates. Does not change Day Total.
 */
export function dateLevelAdditionalPay(
  items: ShiftHistoryPayItem[]
): DateAdditionalPayLine[] {
  const pay = dateLevelPay(items);
  if (!pay) return [];
  const lines: DateAdditionalPayLine[] = [];
  if (pay.restDayPremium != null) {
    lines.push({
      key: "rest_day",
      label: "Rest-Day Premium",
      amount: pay.restDayPremium,
    });
  }
  if (pay.holidayPay != null) {
    lines.push({
      key: "holiday",
      label: "Holiday Premium",
      amount: pay.holidayPay,
    });
  }
  return lines;
}

/** Status text for Shift History. Does not change payroll. */
export function shiftHistoryStatusLabel(item: {
  status?: string | null;
  payroll_status?: string | null;
  earned?: number | null;
  shift_net?: number | null;
}): string {
  if (item.payroll_status === "historical_rate_required") return "Rate required";
  const status = item.status ?? "";
  if (status === "late") return "Late";
  if (status === "absent") return "Absent";
  if (status === "in_progress") return "In progress";
  if (status === "complete") return "Present";
  if (status === "holiday_paid") return "Paid Holiday — Not Worked";
  if (status === "on_leave") {
    const amount = finiteAmount(item.shift_net) ?? finiteAmount(item.earned);
    if (amount != null && amount > 0) return "Paid Leave";
    if (amount != null) return "Unpaid Leave";
    return "On leave";
  }
  if (status === "incomplete") return "Incomplete";
  return status.replace(/_/g, " ");
}

/**
 * Employee-facing shift lines from payslip fields already booked.
 * Does not recalculate payroll.
 */
export function presentShiftPay(
  item: ShiftHistoryPayItem,
  siblings: ShiftHistoryPayItem[]
): ShiftPayFace {
  if (item.historical_rate_required) {
    return {
      showEarned: false,
      earned: null,
      baseLabel: "Base Pay",
      restPay: null,
      holidayPay: null,
      shiftTotal: null,
      hideShiftTotal: false,
    };
  }
  if (item.status === "holiday_paid" || item.holiday_included_in_shift_net) {
    const credit = finiteAmount(item.shift_net) ?? finiteAmount(item.earned);
    return {
      showEarned: false,
      earned: null,
      baseLabel: "Base Pay",
      restPay: null,
      holidayPay: credit != null && credit > 0 ? credit : null,
      shiftTotal: credit,
      hideShiftTotal: false,
    };
  }
  const dailyCount = workedDailyStampCount(siblings);
  if (isWorkedDailyStamp(item) && dailyCount >= 2) {
    return {
      showEarned: false,
      earned: null,
      baseLabel: "Daily Entitlement",
      restPay: null,
      holidayPay: null,
      shiftTotal: null,
      hideShiftTotal: true,
    };
  }
  if (isWorkedDailyStamp(item) && dailyCount === 1) {
    const earned = finiteAmount(item.expected_salary_pay);
    const rest = positiveAmount(finiteAmount(item.day_rest_day_pay));
    const holiday = positiveAmount(finiteAmount(item.day_holiday_pay));
    const net =
      finiteAmount(item.reconciled_shift_total) ?? finiteAmount(item.shift_net);
    const extras = (rest ?? 0) + (holiday ?? 0);
    return {
      showEarned: earned != null,
      earned,
      baseLabel: "Daily Entitlement",
      restPay: rest,
      holidayPay: holiday,
      shiftTotal: net == null ? null : Math.round((net + extras) * 100) / 100,
      hideShiftTotal: false,
    };
  }
  const earned = finiteAmount(item.expected_salary_pay) ?? finiteAmount(item.earned);
  const rest = positiveAmount(finiteAmount(item.rest_day_premium_pay));
  const holiday = item.holiday_included_in_shift_net
    ? null
    : positiveAmount(finiteAmount(item.holiday_pay));
  const reconciled = finiteAmount(item.reconciled_shift_total);
  const net = finiteAmount(item.shift_net);
  const shiftTotal =
    reconciled ??
    (net == null ? null : Math.round((net + (holiday ?? 0)) * 100) / 100);
  return {
    showEarned: earned != null,
    earned,
    baseLabel: "Base Pay",
    restPay: rest,
    holidayPay: holiday,
    shiftTotal,
    hideShiftTotal: false,
  };
}

export function shiftIndexLabel(
  index: number,
  shiftName?: string | null
): string {
  const base = `Shift ${index + 1}`;
  const name = (shiftName ?? "").trim();
  return name ? `${base} — ${name}` : base;
}
