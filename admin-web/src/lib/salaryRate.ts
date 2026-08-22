/** Canonical payroll salary-rate display from employee pay_basis. */

export type PayBasisDisplay = "daily" | "hourly" | "monthly" | string;

export type SalaryRateFields = {
  pay_basis?: PayBasisDisplay | null;
  daily_rate?: number | null;
  hourly_rate?: number | null;
  monthly_salary?: number | null;
  /** Legacy alias from payslip payload. */
  hourly_rate_configured?: number | null;
  /** Legacy alias from payslip payload. */
  monthly_salary_configured?: number | null;
};

function moneyAmount(value: number) {
  return new Intl.NumberFormat("en-PH", {
    style: "currency",
    currency: "PHP",
  }).format(value);
}

function asNumber(value: number | null | undefined): number | null {
  if (value == null || Number.isNaN(Number(value))) return null;
  const n = Number(value);
  return n > 0 ? n : null;
}

/** Amount used for the salary-rate label (basis-specific; ignores legacy daily fallback for hourly/monthly). */
export function salaryRateAmount(fields: SalaryRateFields): number | null {
  const basis = (fields.pay_basis ?? "daily").toLowerCase();
  if (basis === "hourly") {
    return (
      asNumber(fields.hourly_rate) ?? asNumber(fields.hourly_rate_configured)
    );
  }
  if (basis === "monthly") {
    return (
      asNumber(fields.monthly_salary) ??
      asNumber(fields.monthly_salary_configured)
    );
  }
  return asNumber(fields.daily_rate);
}

/** Unit suffix for the salary-rate label. */
export function salaryRateUnit(payBasis?: PayBasisDisplay | null): string {
  const basis = (payBasis ?? "daily").toLowerCase();
  if (basis === "hourly") return "/hour";
  if (basis === "monthly") return "/month";
  return "/day";
}

/** e.g. "₱120.00/hour" or "Not set". */
export function formatSalaryRate(fields: SalaryRateFields): string {
  const amount = salaryRateAmount(fields);
  if (amount == null) return "Not set";
  return `${moneyAmount(amount)}${salaryRateUnit(fields.pay_basis)}`;
}

/** Row label for payslip / PDF (neutral: "Salary Rate"). */
export function salaryRateLabel(): string {
  return "Salary Rate";
}
