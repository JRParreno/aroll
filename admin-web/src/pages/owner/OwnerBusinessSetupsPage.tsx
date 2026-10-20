import {
  BadgeDollarSign,
  Building2,
  CalendarDays,
  CalendarOff,
  ChevronRight,
  Clock3,
  ClipboardList,
  FileText,
  MapPin,
  ShieldCheck,
  UserRoundCog,
} from "lucide-react";
import { Link } from "react-router-dom";
import {
  OwnerCard,
  OwnerPage,
  OwnerPageContent,
  OwnerPageHeader,
} from "@/components/owner/layout/OwnerPageLayout";

const setupSections = [
  {
    title: "Business Schedules",
    description: "Shifts, start/end times, and employee capacity.",
    to: "/owner/setup-wizard?step=0",
    icon: CalendarDays,
  },
  {
    title: "Business Location",
    description: "Work site address, coordinates, and attendance geofence.",
    to: "/owner/location",
    icon: MapPin,
  },
  {
    title: "Positions & Salary Rates",
    description: "Define job roles with daily pay and optional hourly rates.",
    to: "/owner/setup-wizard?step=1",
    icon: BadgeDollarSign,
  },
  {
    title: "Payroll Configuration",
    description: "Pay period, payday schedule, and payroll rules.",
    to: "/owner/setup-wizard?step=2",
    icon: Clock3,
  },
  {
    title: "Attendance Policies",
    description: "Time-in rules, grace periods, overtime, and deductions.",
    to: "/owner/setup-wizard?step=3",
    icon: ShieldCheck,
  },
  {
    title: "Holiday Management",
    description:
      "Holiday calendar, holiday rules, and how holiday pay works in Aroll+.",
    to: "/owner/setup-wizard?step=4",
    icon: CalendarDays,
  },
  {
    title: "Leave Policy",
    description: "Set which leave types are Paid Leave or Unpaid Leave.",
    to: "/owner/settings/leave-policy",
    icon: CalendarOff,
  },
  {
    title: "Consent Configuration",
    description: "Workplace consent documents, required flags, and custom catalogs.",
    to: "/owner/settings/consents",
    icon: FileText,
  },
  {
    title: "Audit History",
    description: "Read-only history of account and workplace activity.",
    to: "/owner/settings/audit-history",
    icon: ClipboardList,
  },
  {
    title: "Account Settings",
    description: "Login credentials, password, and account security.",
    to: "/owner/settings/account",
    icon: UserRoundCog,
  },
  {
    title: "Business Settings",
    description: "Business profile, registration documents, and business code.",
    to: "/owner/settings/business",
    icon: Building2,
  },
];

export function OwnerBusinessSetupsPage() {
  return (
    <OwnerPage>
      <OwnerPageHeader
        title="Business Setup"
        description="Configure your business settings and onboarding requirements."
      />

      <OwnerPageContent>
        <section>
          <h2 className="owner-section-kicker">Settings Modules</h2>
          <div className="grid gap-4 md:grid-cols-2">
            {setupSections.map((section) => {
              const Icon = section.icon;

              return (
                <Link key={section.title} to={section.to} className="block">
                  <OwnerCard className="group h-full transition hover:border-[color-mix(in_srgb,var(--owner-accent)_32%,white)] hover:shadow-[0_8px_24px_rgba(15,23,42,0.06)]">
                    <div className="flex items-center gap-4 p-5">
                      <span className="owner-icon-well h-11 w-11 shrink-0">
                        <Icon className="h-5 w-5" />
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="block text-sm font-semibold text-[#1F2937] group-hover:text-[var(--owner-navy)]">
                          {section.title}
                        </span>
                        <span className="owner-section-subtitle mt-1 block text-[0.8125rem] leading-5">
                          {section.description}
                        </span>
                      </span>
                      <ChevronRight className="h-5 w-5 shrink-0 text-[#9CA3AF] transition group-hover:translate-x-0.5 group-hover:text-[var(--owner-navy)]" />
                    </div>
                  </OwnerCard>
                </Link>
              );
            })}
          </div>
        </section>
      </OwnerPageContent>
    </OwnerPage>
  );
}
