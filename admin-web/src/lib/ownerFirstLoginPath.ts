export type OwnerLandingMe = {
  setup_completed_at?: string | null;
  needs_branding_onboarding?: boolean | null;
};

/** First-login landing for owners. Existing completed businesses stay on the dashboard. */
export function ownerFirstLoginPath(me: OwnerLandingMe): string {
  if (me.setup_completed_at) return "/owner/dashboard";
  if (me.needs_branding_onboarding) return "/owner/branding-setup";
  return "/owner/setup-wizard";
}

export const SETUP_WIZARD_STEPS = [
  "Work Shifts",
  "Employee Job Roles",
  "Set Up Employee Pay",
  "How Employees Time In & Out",
  "Holiday Management",
  "Leave Policy",
  "Work Location",
  "Review Your Setup",
] as const;

export const SETUP_WIZARD_STATUS_KEYS = [
  "shifts",
  "positions",
  "payroll",
  "attendance_policy",
  "holidays",
  "leave_policy",
  "location",
  "review",
] as const;

export const SETUP_WIZARD_LEAVE_POLICY_STEP = 5;
export const SETUP_WIZARD_LOCATION_STEP = 6;
export const SETUP_WIZARD_REVIEW_STEP = 7;
