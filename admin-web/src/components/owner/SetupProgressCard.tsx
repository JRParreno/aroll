import { Link } from "react-router-dom";
import { Button } from "@/components/ui/button";
import type { SetupStatus } from "@/lib/api";

const STEP_ORDER = [
  "shifts",
  "positions",
  "payroll",
  "attendance_policy",
  "holidays",
  "rest_day",
  "location",
];

type Props = {
  status: SetupStatus;
};

export function SetupProgressCard({ status }: Props) {
  if (status.setup_completed_at && status.completion_percent >= 100) {
    return null;
  }

  const setupSteps = status.steps.filter((step) => step.key !== "review");
  const firstIncomplete = setupSteps.find((step) => !step.complete);
  const firstIncompleteIndex = Math.max(
    STEP_ORDER.indexOf(firstIncomplete?.key ?? "shifts"),
    0
  );
  const continuePath = `/owner/setup-wizard?step=${firstIncompleteIndex}`;
  const completedParts = setupSteps.filter((step) => step.complete).length;
  const totalParts = setupSteps.length;

  return (
    <section className="owner-card relative overflow-hidden px-4 py-4 sm:px-5">
      <div className="pointer-events-none absolute inset-y-0 right-0 w-40 bg-gradient-to-l from-[#1E3A5F]/[0.04] to-transparent" />
      <div className="relative flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2.5">
            <h2 className="text-sm font-semibold text-[#1F2937]">
              Business Setup Progress
            </h2>
            <span className="rounded-full bg-[#EEF3F8] px-2.5 py-1 text-xs font-semibold text-[#1E3A5F]">
              {status.completion_percent}%
            </span>
          </div>
          <p className="mt-1 text-xs text-[#6B7280]">
            {completedParts} of {totalParts} parts completed
          </p>
        </div>

        <div className="flex items-center gap-3 sm:min-w-[280px]">
          <div className="h-2 flex-1 overflow-hidden rounded-full bg-[#E5E7EB]">
            <div
              className="h-full rounded-full bg-gradient-to-r from-[#1E3A5F] to-[#284B73] transition-all"
              style={{ width: `${status.completion_percent}%` }}
            />
          </div>
          <Button asChild size="sm" className="h-9 rounded-xl px-4 text-xs">
            <Link to={continuePath}>Continue Setup</Link>
          </Button>
        </div>
      </div>
    </section>
  );
}
