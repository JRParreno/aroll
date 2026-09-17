export type OwnerNavItem = {
  to: string;
  label: string;
  /** Additional paths that should highlight this nav item as active. */
  activePaths?: string[];
};

export const ownerNavItems: OwnerNavItem[] = [
  { to: "/owner/dashboard", label: "Dashboard" },
  { to: "/owner/employees", label: "Employees" },
  { to: "/owner/schedule", label: "Schedule" },
  { to: "/owner/attendance", label: "Attendance" },
  { to: "/owner/leave", label: "Leave Management" },
  { to: "/owner/payroll", label: "Payroll" },
  { to: "/owner/location", label: "Location" },
  {
    to: "/owner/settings/setup",
    label: "Settings",
    activePaths: [
      "/owner/settings",
      "/owner/positions-salary-rates",
      "/owner/payroll-schedule",
      "/owner/business-documents",
      "/owner/setup-wizard",
    ],
  },
  { to: "/owner/help", label: "Help" },
];

export function isOwnerNavItemActive(
  pathname: string,
  to: string,
  activePaths?: string[]
) {
  const matches = (path: string) =>
    pathname === path || pathname.startsWith(`${path}/`);

  if (matches(to)) return true;
  return (activePaths ?? []).some(matches);
}
