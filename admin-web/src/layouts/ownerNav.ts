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
  { to: "/owner/payroll", label: "Payroll" },
  { to: "/owner/productivity", label: "Productivity" },
  { to: "/owner/location", label: "Location" },
  {
    to: "/owner/settings/setup",
    label: "Settings",
    activePaths: [
      "/owner/settings/setup",
      "/owner/settings/account",
      "/owner/settings/business",
      "/owner/positions-salary-rates",
      "/owner/payroll-schedule",
    ],
  },
  { to: "/owner/help", label: "Help" },
];
