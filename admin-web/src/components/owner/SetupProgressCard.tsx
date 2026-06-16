import { Link } from "react-router-dom";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import type { SetupStatus } from "@/lib/api";

const STEP_LABELS: Record<string, string> = {
  shifts: "Schedules Created",
  positions: "Positions Configured",
  payroll: "Payroll Configuration",
  attendance_policy: "Attendance Policies",
  holidays: "Holiday Management",
  rest_day: "Rest Day Policy",
  location: "Business Location",
};

type Props = {
  status: SetupStatus;
  onDismiss?: () => void;
};

export function SetupProgressCard({ status, onDismiss }: Props) {
  if (status.setup_completed_at && status.completion_percent >= 100) {
    return null;
  }

  const dismissed =
    localStorage.getItem("aroll_setup_card_dismissed") === "true";

  if (dismissed && status.completion_percent >= 80) {
    return null;
  }

  const checklistSteps = status.steps.filter((step) => step.key !== "review");

  return (
    <Card className="border-primary/30">
      <CardHeader>
        <CardTitle className="flex items-center justify-between text-lg">
          <span>Business Setup Progress</span>
          <span className="text-sm font-normal text-muted-foreground">
            {status.completion_percent}% complete
          </span>
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="h-2 w-full overflow-hidden rounded-full bg-muted">
          <div
            className="h-full rounded-full bg-[#3b9ae8] transition-all"
            style={{ width: `${status.completion_percent}%` }}
          />
        </div>

        <ul className="space-y-1.5 text-sm">
          {checklistSteps.map((step) => {
            const label = STEP_LABELS[step.key] ?? step.label;
            return (
              <li
                key={step.key}
                className={
                  step.complete
                    ? "text-foreground"
                    : "text-muted-foreground"
                }
              >
                {step.complete ? "✓" : "✗"} {label}
              </li>
            );
          })}
        </ul>

        <div className="flex flex-wrap gap-2">
          <Button asChild>
            <Link to="/owner/setup-wizard">Continue Setup</Link>
          </Button>
          <Button
            variant="outline"
            onClick={() => {
              localStorage.setItem("aroll_setup_card_dismissed", "true");
              onDismiss?.();
            }}
          >
            Remind me later
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
