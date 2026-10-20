/**
 * Owner-facing Holiday Management copy and helpers.
 * Explains existing payroll behavior — does not recompute payroll.
 */

export type HolidayRulesMode = "philippine_labor" | "custom_company";

export type HolidayTypeKey = "regular" | "special_non_working" | "company" | string;

export type HolidayLike = {
  id?: string;
  name: string;
  holiday_date: string;
  holiday_type: string;
  is_paid: boolean;
  pay_multiplier: number;
  ot_premium_percent?: number | null;
  is_active?: boolean;
};

export const HOLIDAY_TERMS = {
  holidayType: "Holiday Type",
  workedPremium: "Holiday Pay Rate",
  payWhenNotWorking: "Pay Scheduled Day When Not Working",
  holidayOtPremium: "Holiday OT Premium",
  active: "Active",
  inactive: "Inactive",
  ruleSummary: "Holiday Rule Summary",
  holidayRules: "Holiday Rules",
  howHolidayPayWorks: "How Holiday Pay Works",
  holidays: "Holidays",
  editHolidayPay: "Edit holiday pay",
  payScheduledDay: "Pay Scheduled Day",
} as const;

export type HolidayOptionParts = {
  title: string;
  detail: string;
};

/** Two-line pay-rate choices. Values still map to existing pay_multiplier presets. */
export const HOLIDAY_PAY_RATE_OPTIONS: ReadonlyArray<{
  multiplier: number;
  title: string;
  detail: string;
}> = [
  { multiplier: 1.0, title: "Regular Pay", detail: "100%" },
  { multiplier: 1.3, title: "130% Holiday Pay", detail: "130%" },
  { multiplier: 1.5, title: "150% Holiday Pay", detail: "150%" },
  { multiplier: 2.0, title: "Double Pay", detail: "200%" },
  { multiplier: 2.5, title: "250% Holiday Pay", detail: "250%" },
  { multiplier: 3.0, title: "Triple Pay", detail: "300%" },
];

export const HOLIDAY_OT_OPTIONS: ReadonlyArray<{
  id: "0" | "30" | "custom";
  title: string;
  detail: string;
}> = [
  { id: "0", title: "No Extra OT", detail: "0%" },
  { id: "30", title: "30% Extra", detail: "30%" },
  { id: "custom", title: "Custom", detail: "Enter a percent" },
];

export function holidayPayRateParts(multiplier: number): HolidayOptionParts {
  const safe =
    Number.isFinite(multiplier) && multiplier > 0 ? multiplier : 1;
  const preset = HOLIDAY_PAY_RATE_OPTIONS.find(
    (p) => Math.abs(p.multiplier - safe) < PRESET_EPS
  );
  if (preset) return { title: preset.title, detail: preset.detail };
  const pct = holidayPayRatePercent(safe);
  const pctText = Number.isInteger(pct) ? String(pct) : pct.toFixed(1);
  return { title: `${pctText}% Pay`, detail: `${pctText}%` };
}

export function holidayPayRateCardLine(multiplier: number): string {
  const parts = holidayPayRateParts(multiplier);
  if (isHolidayPayRatePreset(multiplier)) {
    return `${parts.title} · ${parts.detail}`;
  }
  return parts.detail;
}

export function holidayOtCardLine(value: number | null | undefined): string {
  if (value == null || value === 0) return "No Extra OT";
  if (Math.abs(value - 30) < PRESET_EPS) return "30%";
  const pct = Number.isInteger(value) ? String(value) : String(value);
  return `${pct}%`;
}

/** Preset total-pay rates mapped to existing `pay_multiplier` values. */
export const HOLIDAY_PAY_RATE_PRESETS: ReadonlyArray<{
  multiplier: number;
  label: string;
}> = [
  { multiplier: 1.0, label: "Regular Pay — 100%" },
  { multiplier: 1.3, label: "130% Pay" },
  { multiplier: 1.5, label: "150% Pay" },
  { multiplier: 2.0, label: "Double Pay — 200%" },
  { multiplier: 2.5, label: "250% Pay" },
  { multiplier: 3.0, label: "Triple Pay — 300%" },
];

const PRESET_EPS = 0.0001;

export function isHolidayPayRatePreset(multiplier: number): boolean {
  return HOLIDAY_PAY_RATE_PRESETS.some(
    (p) => Math.abs(p.multiplier - multiplier) < PRESET_EPS
  );
}

/** Display-only total-pay percentage from existing multiplier (does not rewrite storage). */
export function holidayPayRatePercent(multiplier: number): number {
  const safe =
    Number.isFinite(multiplier) && multiplier > 0 ? multiplier : 1;
  return Math.round(safe * 1000) / 10; // one decimal when needed (e.g. 133.3)
}

export function holidayPayRateLabel(multiplier: number): string {
  const safe =
    Number.isFinite(multiplier) && multiplier > 0 ? multiplier : 1;
  const preset = HOLIDAY_PAY_RATE_PRESETS.find(
    (p) => Math.abs(p.multiplier - safe) < PRESET_EPS
  );
  if (preset) return preset.label;
  const pct = holidayPayRatePercent(safe);
  const pctText = Number.isInteger(pct) ? String(pct) : pct.toFixed(1);
  return `${pctText}% Pay`;
}

export function percentToPayMultiplier(percent: number): number {
  return percent / 100;
}

export function multiplierToPercentInput(multiplier: number): string {
  const safe =
    Number.isFinite(multiplier) && multiplier > 0 ? multiplier : 1;
  const pct = holidayPayRatePercent(safe);
  return Number.isInteger(pct) ? String(pct) : String(pct);
}

/** Owner-facing TOTAL pay-rate explanation (not additional premium). */
export function holidayPayRateExplanation(multiplier: number): string {
  const label = holidayPayRateLabel(multiplier);
  const pct = holidayPayRatePercent(
    Number.isFinite(multiplier) && multiplier > 0 ? multiplier : 1
  );
  const pctText = Number.isInteger(pct) ? String(pct) : pct.toFixed(1);
  return (
    `${label}. Employees who work this holiday receive ${pctText}% of their ` +
    "applicable normal pay (total pay rate, not an additional premium)."
  );
}

export function holidayPayRateExample(multiplier: number): string {
  const safe =
    Number.isFinite(multiplier) && multiplier > 0 ? multiplier : 1;
  const exampleBase = 500;
  const total = Math.round(exampleBase * safe * 100) / 100;
  const pct = holidayPayRatePercent(safe);
  const pctText = Number.isInteger(pct) ? String(pct) : pct.toFixed(1);
  return (
    `Example: if applicable normal pay is ₱${exampleBase.toFixed(0)}, ` +
    `this holiday rate is ₱${total.toLocaleString("en-PH", {
      minimumFractionDigits: 0,
      maximumFractionDigits: 2,
    })} (${pctText}% total) before other applicable adjustments.`
  );
}

export function holidayOtPremiumOwnerLabel(
  value: number | null | undefined
): string {
  if (value == null || (typeof value === "number" && value === 0)) {
    return "No additional holiday OT premium — 0%";
  }
  if (Math.abs(value - 30) < PRESET_EPS) {
    return "30% additional — 30%";
  }
  return `${value}% additional`;
}

export function holidayTypeLabel(type: string): string {
  if (type === "regular") return "Regular Holiday";
  if (type === "special_non_working") return "Special Non-Working Day";
  if (type === "company") return "Company Holiday";
  return type;
}

export function holidayTypeDescription(type: string): string {
  if (type === "regular") {
    return "Uses the existing Philippine Labor holiday policy in Aroll+.";
  }
  if (type === "special_non_working") {
    return "Uses the existing Philippine Labor special non-working-day policy in Aroll+.";
  }
  if (type === "company") {
    return "Uses your business's configured company-holiday behavior.";
  }
  return "Uses the holiday settings saved for this date.";
}

export function rulesModeLabel(mode: HolidayRulesMode): string {
  return mode === "custom_company"
    ? "Custom company rules"
    : "Philippine labor rules";
}

export function rulesModeDescription(mode: HolidayRulesMode): string {
  if (mode === "custom_company") {
    return "Each holiday's Pay Scheduled Day When Not Working setting and Holiday Pay Rate are used directly.";
  }
  return "Regular holidays pay the scheduled day even if unworked. Special non-working days follow no-work-no-pay unless worked. Company holidays follow the Pay Scheduled Day When Not Working setting.";
}

/** Whether the owner can edit is_paid for this type under the current mode. */
export function canEditPayWhenNotWorking(
  mode: HolidayRulesMode,
  holidayType: string
): boolean {
  if (mode === "custom_company") return true;
  return holidayType === "company";
}

export type UnworkedRulePresentation = {
  editable: boolean;
  effectivePaysUnworked: boolean;
  title: string;
  explanation: string;
};

export function unworkedRulePresentation(
  mode: HolidayRulesMode,
  holidayType: string,
  isPaid: boolean
): UnworkedRulePresentation {
  if (mode === "custom_company") {
    return {
      editable: true,
      effectivePaysUnworked: isPaid,
      title: HOLIDAY_TERMS.payWhenNotWorking,
      explanation: "Pay their scheduled day if they do not work.",
    };
  }

  if (holidayType === "regular") {
    return {
      editable: false,
      effectivePaysUnworked: true,
      title: HOLIDAY_TERMS.payWhenNotWorking,
      explanation:
        "Regular holidays are paid even when the employee does not work.",
    };
  }

  if (holidayType === "special_non_working") {
    return {
      editable: false,
      effectivePaysUnworked: false,
      title: HOLIDAY_TERMS.payWhenNotWorking,
      explanation:
        "Special non-working days are not paid when the employee does not work.",
    };
  }

  return {
    editable: true,
    effectivePaysUnworked: isPaid,
    title: HOLIDAY_TERMS.payWhenNotWorking,
    explanation: "Pay their scheduled day if they do not work.",
  };
}

export function workedPremiumHelperText(factor: number): string {
  return holidayPayRateExplanation(factor);
}

export function multiplierWarning(factor: number | null): string | null {
  if (factor == null || Number.isNaN(factor)) return null;
  if (factor <= 0) {
    return "Values of 0% or less are unusual. Current payroll treats invalid rates as Regular Pay — 100%.";
  }
  return null;
}

export function workedRateNote(multiplier: number, custom: boolean): string {
  if (custom) {
    return "Enter the total pay rate. 200% is double pay, not 200% on top.";
  }
  if (Math.abs(multiplier - 1) < 0.0001) {
    return "Regular pay. No extra holiday pay.";
  }
  if (Math.abs(multiplier - 2) < 0.0001) {
    return "Double pay for eligible holiday work.";
  }
  return "Extra pay when employees work this holiday.";
}

export function otPremiumNote(_raw?: string | null): string {
  return "Extra pay for approved overtime worked this holiday.";
}

export function otPremiumWarning(raw: string | null | undefined): string {
  return otPremiumNote(raw);
}

export function formatOtPremiumLabel(
  value: number | null | undefined
): string {
  if (value == null) return "0% (blank / not configured)";
  return `${value}%`;
}

export type DuplicateHolidayHit = {
  id: string;
  name: string;
  holiday_type: string;
};

export function findDuplicateActiveHoliday(
  holidays: HolidayLike[],
  holidayDate: string,
  excludeId?: string | null
): DuplicateHolidayHit | null {
  if (!holidayDate) return null;
  const hit = holidays.find(
    (h) =>
      h.holiday_date === holidayDate &&
      (h.is_active === undefined || h.is_active) &&
      (!excludeId || h.id !== excludeId)
  );
  if (!hit || !hit.id) return null;
  return {
    id: hit.id,
    name: hit.name,
    holiday_type: hit.holiday_type,
  };
}

export type RuleSummaryLines = {
  holiday: string;
  type: string;
  typeDescription: string;
  worked: string[];
  unworked: string[];
  overtime: string[];
  restDay: string[];
  multipleShifts: string[];
};

export function buildRuleSummary(args: {
  name: string;
  holidayType: string;
  mode: HolidayRulesMode;
  isPaid: boolean;
  payMultiplier: number;
  otPremiumRaw: string | null | undefined;
}): RuleSummaryLines {
  const unworked = unworkedRulePresentation(
    args.mode,
    args.holidayType,
    args.isPaid
  );
  const factor =
    Number.isFinite(args.payMultiplier) && args.payMultiplier > 0
      ? args.payMultiplier
      : 1;
  const otTrimmed = (args.otPremiumRaw ?? "").trim();
  const otNum = otTrimmed ? Number(otTrimmed) : null;
  const otLabel = holidayOtPremiumOwnerLabel(
    otTrimmed === "" || Number.isNaN(otNum as number) ? null : otNum
  );

  return {
    holiday: args.name.trim() || "(Untitled holiday)",
    type: holidayTypeLabel(args.holidayType),
    typeDescription: holidayTypeDescription(args.holidayType),
    worked: [
      holidayPayRateExplanation(factor),
      holidayPayRateExample(factor),
    ],
    unworked: [
      unworked.effectivePaysUnworked
        ? "Scheduled-day entitlement according to the current holiday policy"
        : "No scheduled-day holiday entitlement when the employee does not work",
      unworked.explanation,
    ],
    overtime: [
      "Approved overtime uses your business OT ₱/minute rate",
      `Holiday OT Premium: ${otLabel}`,
    ],
    restDay: [
      "Existing rest-day premium rules still apply separately when the assignment is rest-day work",
    ],
    multipleShifts: [
      "Holiday pay automatically follows the employee's existing pay basis.",
      "Multiple shifts on the same day are handled automatically by Aroll+.",
    ],
  };
}

export function compactRuleLine(args: {
  mode: HolidayRulesMode;
  holidayType: string;
  isPaid: boolean;
  payMultiplier: number;
}): string {
  const unworked = unworkedRulePresentation(
    args.mode,
    args.holidayType,
    args.isPaid
  );
  const factor =
    Number.isFinite(args.payMultiplier) && args.payMultiplier > 0
      ? args.payMultiplier
      : 1;
  const worked = holidayPayRateLabel(factor);
  const notWorked = unworked.effectivePaysUnworked
    ? "Pay Scheduled Day"
    : "No pay if unworked";
  return `${worked} · ${notWorked}`;
}

export function shortWorkedPremiumHint(): string {
  return "Extra pay when employees work this holiday.";
}

export const HOW_HOLIDAY_PAY_WORKS_PRIMARY: {
  title: string;
  summary: string;
  detail: string;
}[] = [
  {
    title: "When an employee works on a holiday",
    summary:
      "They receive the Holiday Pay Rate you configured for eligible work (total pay rate, such as Double Pay — 200%).",
    detail:
      "The existing pay_multiplier is a total-pay factor (2.0 = 200% total). Payroll still applies the same holiday premium rules as before.",
  },
  {
    title: "When an employee does not work",
    summary:
      "Some holidays still pay a scheduled-day amount; others do not. This follows your holiday type and Holiday Rules mode.",
    detail:
      "Under Philippine labor rules, Regular Holidays pay when unworked; Special Non-Working Days do not. Company holidays follow Pay Scheduled Day When Not Working.",
  },
  {
    title: "How overtime is handled",
    summary:
      "Approved OT uses your business OT ₱/minute rate, plus this holiday’s Holiday OT Premium. Blank premium means 0%.",
    detail:
      "Rest-day premiums remain separate. Unused business OT percentage fields do not control holiday OT.",
  },
  {
    title: "Daily vs Hourly employees",
    summary:
      "Holiday pay automatically follows the employee's existing pay basis. Daily and Hourly employees use the payroll rules already configured in Aroll+.",
    detail:
      "Aroll+ does not stack a separate Daily holiday entitlement for every shift on the same date. Multiple shifts on the same day are handled automatically.",
  },
  {
    title: "After payroll is finalized",
    summary:
      "Finalized payroll uses the saved snapshot. Changing a holiday later does not change finalized payroll.",
    detail:
      "Live unfinalized periods recalculate from current holiday settings.",
  },
];
