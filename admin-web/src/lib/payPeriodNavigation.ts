/** Move the payroll report `as_of` date to the neighboring configured period.

The API resolves the period that contains `as_of`. The day before a period
starts falls in the previous period, and the day after it ends falls in the
next one. Payroll rows are not read or written here.
*/

export function shiftIsoDate(iso: string, days: number): string {
  const [year, month, day] = iso.slice(0, 10).split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  date.setUTCDate(date.getUTCDate() + days);
  const y = date.getUTCFullYear();
  const m = String(date.getUTCMonth() + 1).padStart(2, "0");
  const d = String(date.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

export function previousPeriodAsOf(periodStart: string): string {
  return shiftIsoDate(periodStart, -1);
}

export function nextPeriodAsOf(periodEnd: string): string {
  return shiftIsoDate(periodEnd, 1);
}

/** Next is available only for a period that has already ended. */
export function canOpenNextPayPeriod(
  payrollStatus: string | null | undefined
): boolean {
  return payrollStatus === "completed";
}
