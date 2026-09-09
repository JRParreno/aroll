import {
  BadgeDollarSign,
  Building2,
  CalendarDays,
  CalendarOff,
  ChevronRight,
  Clock3,
  FileText,
  HelpCircle,
  MapPin,
  ShieldCheck,
  UserRoundCog,
} from "lucide-react";
import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { Card, CardContent } from "@/components/ui/card";
import {
  OwnerPage,
  OwnerPageBackLink,
  OwnerPageContent,
  OwnerPageHeader,
} from "@/components/owner/layout/OwnerPageLayout";
import { getMe } from "@/lib/api";
import { ME_QUERY_KEY } from "@/lib/authSession";

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
    description: "Company holidays, paid leave, and special non-working days.",
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
] as const;

export function OwnerBusinessSetupsPage() {
  const { data: me } = useQuery({ queryKey: ME_QUERY_KEY, queryFn: getMe });
  const consentPath = me?.business_code
    ? `/legal/b/${me.business_code}`
    : "/owner/settings/business";

  return (
    <OwnerPage>
      <OwnerPageHeader
        title="Business Setup"
        description="Configure your business settings and onboarding requirements."
      />

      <OwnerPageContent>
        <OwnerPageBackLink to="/owner/dashboard" label="Back to Dashboard" />

        <section>
          <h2 className="mb-4 text-sm font-medium uppercase tracking-wide text-[#6B7280]">
            Settings Modules
          </h2>
          <div className="grid gap-4 md:grid-cols-2">
            {setupSections.map((section) => {
              const Icon = section.icon;

              return (
                <Link key={section.title} to={section.to} className="block">
                  <Card className="h-full rounded-2xl border-slate-200 shadow-sm transition hover:border-slate-300 hover:bg-[#FAFBFC]">
                    <CardContent className="flex items-center gap-4 p-5">
                      <span className="rounded-xl bg-[#F3F6FA] p-2 text-[#1E3A5F]">
                        <Icon className="h-5 w-5" />
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="owner-section-title block">
                          {section.title}
                        </span>
                        <span className="owner-section-subtitle mt-1 block">
                          {section.description}
                        </span>
                      </span>
                      <ChevronRight className="h-5 w-5 shrink-0 text-[#9CA3AF]" />
                    </CardContent>
                  </Card>
                </Link>
              );
            })}
            <Link to={consentPath} className="block">
              <Card className="h-full rounded-2xl border-slate-200 shadow-sm transition hover:border-slate-300 hover:bg-[#FAFBFC]">
                <CardContent className="flex items-center gap-4 p-5">
                  <span className="rounded-xl bg-[#F3F6FA] p-2 text-[#1E3A5F]">
                    <FileText className="h-5 w-5" />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="owner-section-title block">
                      Employee consent webpage
                    </span>
                    <span className="owner-section-subtitle mt-1 block">
                      Preview the generated workplace consent page. Edit the
                      content in Business Settings.
                    </span>
                  </span>
                  <ChevronRight className="h-5 w-5 shrink-0 text-[#9CA3AF]" />
                </CardContent>
              </Card>
            </Link>
          </div>
        </section>

        <Card className="rounded-2xl border-slate-200 shadow-sm">
          <CardContent className="flex items-center gap-4 p-5">
            <span className="rounded-xl bg-[#F3F6FA] p-2 text-[#1E3A5F]">
              <HelpCircle className="h-5 w-5" />
            </span>
            <div>
              <p className="owner-section-title">
                Need help configuring setup?
              </p>
              <p className="owner-section-subtitle mt-1">
                Use each module above to continue the existing setup workflow.
              </p>
            </div>
          </CardContent>
        </Card>
      </OwnerPageContent>
    </OwnerPage>
  );
}
