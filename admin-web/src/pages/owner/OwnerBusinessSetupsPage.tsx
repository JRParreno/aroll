import { Link } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

const setupSections = [
  {
    title: "Business Information",
    description: "Business name, contact details, and general profile.",
    to: "/owner/location",
  },
  {
    title: "Positions & Salary Rates",
    description: "Define job roles and daily pay rates for your team.",
    to: "/owner/positions-salary-rates",
  },
  {
    title: "Payroll Configuration",
    description: "Pay period, payday schedule, and payroll rules.",
    to: "/owner/payroll-schedule",
  },
  {
    title: "Attendance Policies",
    description: "Clock-in rules, grace periods, overtime, and deductions.",
    to: "/owner/setup-wizard?step=3",
  },
  {
    title: "Holiday Management",
    description: "Company holidays, paid leave, and special non-working days.",
    to: "/owner/setup-wizard?step=4",
  },
  {
    title: "Account Settings",
    description: "Login credentials, password, and account security.",
    to: "/owner/settings/account",
  },
  {
    title: "Personal Settings",
    description: "Owner profile and notification preferences.",
    to: "/owner/settings/personal",
  },
  {
    title: "Business Settings",
    description: "Operational preferences and business-wide defaults.",
    to: "/owner/settings/business",
  },
];

export function OwnerBusinessSetupsPage() {
  return (
    <div className="min-h-full bg-muted/30 p-6">
      <div className="mx-auto max-w-4xl space-y-6">
        <div>
          <h1 className="text-2xl font-semibold">Business Setup</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Central hub for configuring your business. Use the setup wizard for
            guided onboarding, or open a section below to manage settings
            directly.
          </p>
        </div>

        <Card>
          <CardHeader>
            <CardTitle className="text-lg">Setup Wizard</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="mb-4 text-sm text-muted-foreground">
              Walk through shifts, positions, payroll, attendance, holidays, and
              rest day policies in one guided flow.
            </p>
            <Button asChild>
              <Link to="/owner/setup-wizard">Open Setup Wizard</Link>
            </Button>
          </CardContent>
        </Card>

        <div className="grid gap-4 sm:grid-cols-2">
          {setupSections.map((section) => (
            <Link key={section.title} to={section.to} className="block">
              <Card className="h-full transition-colors hover:bg-muted/50">
                <CardHeader className="pb-2">
                  <CardTitle className="text-base">{section.title}</CardTitle>
                </CardHeader>
                <CardContent>
                  <p className="text-sm text-muted-foreground">
                    {section.description}
                  </p>
                </CardContent>
              </Card>
            </Link>
          ))}
        </div>
      </div>
    </div>
  );
}
