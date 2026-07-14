import {
  BadgeDollarSign,
  Building2,
  CalendarDays,
  ChevronRight,
  Clock3,
  FileText,
  HelpCircle,
  MapPin,
  ShieldCheck,
  UserRoundCog,
} from "lucide-react";
import { Link } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  OwnerPage,
  OwnerPageBackLink,
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
    description: "Define job roles and daily pay rates for your team.",
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
    description: "Clock-in rules, grace periods, overtime, and deductions.",
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
        <OwnerPageBackLink to="/owner/dashboard" label="Back to Dashboard" />

        <Card className="rounded-2xl border-slate-200 shadow-sm">
          <CardHeader className="pb-3">
            <div className="flex items-start justify-between gap-4">
              <div>
                <CardTitle className="text-lg font-semibold text-[#1F2937]">
                  Setup Wizard
                </CardTitle>
                <p className="mt-1 text-sm text-[#6B7280]">
                  Walk through shifts, positions, payroll, attendance, holidays,
                  location, and rest day policies in one guided flow.
                </p>
              </div>
              <span className="rounded-xl bg-[#F3F6FA] p-2 text-[#1E3A5F]">
                <FileText className="h-5 w-5" />
              </span>
            </div>
          </CardHeader>
          <CardContent>
            <Button className="bg-[#1E3A5F] hover:bg-[#284B73]" asChild>
              <Link to="/owner/setup-wizard">Open Setup Wizard</Link>
            </Button>
          </CardContent>
        </Card>

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
                        <span className="block text-sm font-semibold text-[#1F2937]">
                          {section.title}
                        </span>
                        <span className="mt-1 block text-xs leading-5 text-[#6B7280]">
                          {section.description}
                        </span>
                      </span>
                      <ChevronRight className="h-5 w-5 shrink-0 text-[#9CA3AF]" />
                    </CardContent>
                  </Card>
                </Link>
              );
            })}
          </div>
        </section>

        <Card className="rounded-2xl border-slate-200 shadow-sm">
          <CardContent className="flex items-center gap-4 p-5">
            <span className="rounded-xl bg-[#F3F6FA] p-2 text-[#1E3A5F]">
              <HelpCircle className="h-5 w-5" />
            </span>
            <div>
              <p className="text-sm font-semibold text-[#1F2937]">
                Need help configuring setup?
              </p>
              <p className="mt-1 text-xs text-[#6B7280]">
                Use each module above to continue the existing setup workflow.
              </p>
            </div>
          </CardContent>
        </Card>
      </OwnerPageContent>
    </OwnerPage>
  );
}
