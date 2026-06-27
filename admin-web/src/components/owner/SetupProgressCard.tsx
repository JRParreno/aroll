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
    <section className="rounded-2xl border border-slate-200 bg-white px-4 py-3 shadow-sm">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="min-w-0">
          <div className="flex items-center gap-3">
            <h2 className="text-sm font-semibold text-[#1F2937]">
              Business Setup Progress
            </h2>
            <span className="rounded-full bg-[#F3F6FA] px-2.5 py-1 text-xs font-medium text-[#1E3A5F]">
              {status.completion_percent}%
            </span>
          </div>
          <p className="mt-1 text-xs text-[#6B7280]">
            {completedParts} of {totalParts} parts completed
          </p>
        </div>

        <div className="flex items-center gap-3 sm:min-w-[260px]">
          <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-[#E5E7EB]">
            <div
              className="h-full rounded-full bg-[#1E3A5F] transition-all"
              style={{ width: `${status.completion_percent}%` }}
            />
          </div>
          <Button
            asChild
            size="sm"
            className="h-9 rounded-xl bg-[#1E3A5F] px-4 text-xs text-white hover:bg-[#284B73]"
          >
            <Link to={continuePath}>Continue Setup</Link>
          </Button>
        </div>
      </div>
    </section>
  );
}
