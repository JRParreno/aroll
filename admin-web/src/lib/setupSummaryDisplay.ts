/**
 * Read-only labels for the web owner Setup Summary.
 * Wording matches the mobile Owner Business Setup Summary screen.
 */

export type SetupSummaryShift = {
  name?: string | null;
  start_time?: string | null;
  end_time?: string | null;
};

export type SetupSummaryPosition = {
  title?: string | null;
  daily_rate?: number | null;
  hourly_rate?: number | null;
};

export type SetupSummaryInput = {
  business: {
    business_name?: string | null;
    business_type?: string | null;
    business_code?: string | null;
    application_status?: string | null;
    address?: string | null;
  };
  location: {
    address?: string | null;
    latitude?: number | null;
    longitude?: number | null;
    geofence_radius_m?: number | null;
  };
  shifts: SetupSummaryShift[];
  positions: SetupSummaryPosition[];
  payroll: {
    pay_period_type?: string | null;
    next_payday_date?: string | null;
  };
  attendancePolicy: Record<string, unknown> | null | undefined;
  holidays: unknown[];
  restDayPolicy: {
    rest_day_premium_percent?: number | null;
  };
};

export type SetupSummaryRow = {
  label: string;
  value: string;
};

export type SetupSummarySection = {
  title: string;
  rows: SetupSummaryRow[];
};

const UNCONFIGURED_VALUES = new Set([
  "Not set",
  "Not configured",
  "None configured",
  "No job roles with daily pay yet",
  "—%",
]);

export function isUnconfiguredSummaryValue(value: string) {
  return UNCONFIGURED_VALUES.has(value);
}

export function formatOwnerKey(value: string) {
  return value
    .split("_")
    .join(" ")
    .split(" ")
    .filter((part) => part.length > 0)
    .map((part) => `${part[0].toUpperCase()}${part.slice(1)}`)
    .join(" ");
}

function displayValue(value: unknown): string | null {
  if (value == null) return null;
  const text = String(value).trim();
  if (!text || text === "null") return null;
  return text;
}

function rowValue(value: unknown) {
  return displayValue(value) ?? "Not set";
}

export function ownerPayFrequencyLabel(payPeriodType: unknown) {
  switch (payPeriodType == null ? "null" : String(payPeriodType)) {
    case "weekly":
      return "Weekly";
    case "semi_monthly":
      return "Twice a month";
    case "monthly":
      return "Monthly";
    default: {
      const text = displayValue(payPeriodType);
      return text == null ? "Not set" : formatOwnerKey(text);
    }
  }
}

export function ownerStatusLabel(status: unknown) {
  const text = displayValue(status);
  if (text == null) return "Not set";
  return formatOwnerKey(text);
}

function radiusLabel(radius: unknown) {
  if (radius == null) return "Not set";
  const text = String(radius).trim();
  if (!text) return "Not set";
  return `${text}m`;
}

function minutesLabel(minutes: unknown) {
  if (minutes == null) return "Not set";
  const text = String(minutes).trim();
  if (!text) return "Not set";
  return `${text} min`;
}

function locationValidationLabel(location: SetupSummaryInput["location"]) {
  if (
    location.latitude != null &&
    location.longitude != null &&
    location.geofence_radius_m != null
  ) {
    return "Enabled";
  }
  return "Not set";
}

export type SummaryListItem = {
  name: string;
  detail: string | null;
};

export function summaryShiftItems(shifts: SetupSummaryShift[]): SummaryListItem[] {
  const items: SummaryListItem[] = [];
  for (const shift of shifts) {
    const name = `${shift.name ?? ""}`.trim();
    if (!name) continue;
    const detail =
      shift.start_time != null && shift.end_time != null
        ? `${shift.start_time}–${shift.end_time}`
        : null;
    items.push({ name, detail });
  }
  return items;
}

export function summaryPositionItems(
  positions: SetupSummaryPosition[]
): SummaryListItem[] {
  const items: SummaryListItem[] = [];
  for (const position of positions) {
    const name = `${position.title ?? ""}`.trim();
    if (!name) continue;
    const parts: string[] = [];
    if (position.daily_rate != null) parts.push(`₱${position.daily_rate}/day`);
    if (position.hourly_rate != null) parts.push(`₱${position.hourly_rate}/hr`);
    items.push({
      name,
      detail: parts.length === 0 ? null : parts.join(" · "),
    });
  }
  return items;
}

function shiftLabel(shift: SetupSummaryShift) {
  const [item] = summaryShiftItems([shift]);
  if (!item) return null;
  return item.detail ? `${item.name} (${item.detail})` : item.name;
}

function positionLabel(position: SetupSummaryPosition) {
  const [item] = summaryPositionItems([position]);
  if (!item) return null;
  return item.detail ? `${item.name} — ${item.detail}` : item.name;
}

function restDayLabel(policy: SetupSummaryInput["restDayPolicy"]) {
  if (policy.rest_day_premium_percent == null) return "Not configured";
  return `Extra pay on rest days: ${policy.rest_day_premium_percent}%`;
}

export function buildSetupSummarySections(
  summary: SetupSummaryInput
): SetupSummarySection[] {
  const shiftLines = summary.shifts
    .map(shiftLabel)
    .filter((line): line is string => Boolean(line));
  const positionLines = summary.positions
    .map(positionLabel)
    .filter((line): line is string => Boolean(line));
  const attendance = summary.attendancePolicy;
  const attendanceConfigured =
    attendance != null && Object.keys(attendance).length > 0;
  const holidayCount = summary.holidays.length;

  return [
    {
      title: "Business Profile",
      rows: [
        { label: "Business Name", value: rowValue(summary.business.business_name) },
        { label: "Business Type", value: rowValue(summary.business.business_type) },
        { label: "Business Code", value: rowValue(summary.business.business_code) },
        {
          label: "Business Status",
          value: ownerStatusLabel(summary.business.application_status),
        },
      ],
    },
    {
      title: "Work Location",
      rows: [
        {
          label: "Workplace Address",
          value: rowValue(summary.location.address ?? summary.business.address),
        },
        {
          label: "Allowed Attendance Radius",
          value: radiusLabel(summary.location.geofence_radius_m),
        },
        {
          label: "Work Location Validation",
          value: locationValidationLabel(summary.location),
        },
      ],
    },
    {
      title: "Work Shifts",
      rows: [
        {
          label: "Configured Shifts",
          value: shiftLines.length === 0 ? "None configured" : shiftLines.join("\n"),
        },
      ],
    },
    {
      title: "Employee Positions",
      rows: [
        {
          label: "Configured Positions",
          value:
            positionLines.length === 0
              ? "None configured"
              : positionLines.join("\n"),
        },
      ],
    },
    {
      title: "Payroll",
      rows: [
        {
          label: "Payroll Frequency",
          value: ownerPayFrequencyLabel(summary.payroll.pay_period_type),
        },
        {
          label: "Daily Rate Settings",
          value:
            summary.positions.length === 0
              ? "No job roles with daily pay yet"
              : `${summary.positions.length} job role${
                  summary.positions.length === 1 ? "" : "s"
                } configured`,
        },
        {
          label: "Next Payday",
          value: rowValue(summary.payroll.next_payday_date),
        },
      ],
    },
    {
      title: "Attendance",
      rows: [
        {
          label: "Time-In Settings",
          value: attendanceConfigured ? "Configured" : "Not configured",
        },
        {
          label: "Early Time-In Window",
          value: minutesLabel(attendance?.early_clock_in_minutes),
        },
        {
          label: "Extra Minutes Before Late",
          value: minutesLabel(attendance?.on_time_grace_minutes),
        },
        {
          label: "Minimum Worked Shift (%)",
          value: `${attendance?.absent_threshold_percent ?? "—"}%`,
        },
        {
          label: "Minimum Overtime",
          value: minutesLabel(attendance?.overtime_minimum_minutes),
        },
        {
          label: "Maximum Overtime Duration",
          value: minutesLabel(attendance?.maximum_overtime_minutes),
        },
        {
          label: "Work Location Validation Status",
          value: locationValidationLabel(summary.location),
        },
      ],
    },
    {
      title: "Holidays",
      rows: [
        {
          label: "Configured Holidays",
          value:
            holidayCount === 0
              ? "None configured"
              : `${holidayCount} holiday${holidayCount === 1 ? "" : "s"}`,
        },
      ],
    },
    {
      title: "Rest Days",
      rows: [
        {
          label: "Configured Rest Days",
          value: restDayLabel(summary.restDayPolicy),
        },
      ],
    },
  ];
}
