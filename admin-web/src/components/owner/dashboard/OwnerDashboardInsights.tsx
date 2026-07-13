import { useQuery } from "@tanstack/react-query";
import { CalendarClock, ClipboardCheck } from "lucide-react";
import { Link } from "react-router-dom";
import { getPayrollConfig, getSetupStatus } from "@/lib/api";

function daysUntil(dateKey: string | null | undefined) {
  if (!dateKey) return null;
  const target = new Date(`${dateKey}T00:00:00`);
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  return Math.round((target.getTime() - today.getTime()) / 86_400_000);
}

function InsightCard({
  title,
  icon: Icon,
  loading,
  value,
  helper,
  to,
  linkLabel,
}: {
  title: string;
  icon: typeof CalendarClock;
  loading: boolean;
  value: string;
  helper: string;
  to: string;
  linkLabel: string;
}) {
  return (
    <div className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
      <div className="flex items-start justify-between gap-3">
        <div className="rounded-xl bg-[#F3F6FA] p-2 text-[#1E3A5F]">
          <Icon className="h-4 w-4" />
        </div>
        <Link className="text-xs font-medium text-[#1E3A5F]" to={to}>
          {linkLabel}
        </Link>
      </div>
      <p className="mt-4 text-sm font-medium text-[#374151]">{title}</p>
      <p className="mt-1 text-xl font-semibold text-[#1F2937]">
        {loading ? "..." : value}
      </p>
      <p className="mt-2 text-xs text-[#6B7280]">{helper}</p>
    </div>
  );
}

export function OwnerDashboardInsights() {
  const { data: payrollConfig, isLoading: payrollLoading } = useQuery({
    queryKey: ["payroll-config"],
    queryFn: getPayrollConfig,
  });

  const { data: setupStatus, isLoading: setupLoading } = useQuery({
    queryKey: ["setup-status"],
    queryFn: getSetupStatus,
  });

  const pendingSetup =
    setupStatus?.steps.filter((step) => !step.completed).length ?? 0;

  const paydayIn = daysUntil(payrollConfig?.next_payday_date);

  return (
    <div className="flex flex-col gap-4">
      <InsightCard
        title="Payroll Status"
        icon={CalendarClock}
        loading={payrollLoading}
        value={
          paydayIn === null
            ? "Not scheduled"
            : paydayIn === 0
              ? "Payday is today"
              : paydayIn < 0
                ? "Past due window"
                : `Due in ${paydayIn} day${paydayIn === 1 ? "" : "s"}`
        }
        helper={
          payrollConfig?.next_payday_date
            ? `Next payday: ${payrollConfig.next_payday_date}`
            : "Configure payroll in Business Setup"
        }
        to="/owner/payroll"
        linkLabel="View payroll"
      />
      <InsightCard
        title="Setup Tasks"
        icon={ClipboardCheck}
        loading={setupLoading}
        value={
          setupStatus?.setup_completed_at
            ? "Complete"
            : `${pendingSetup} pending`
        }
        helper={
          setupStatus?.setup_completed_at
            ? "Business setup is finished"
            : "Finish required setup steps"
        }
        to="/owner/settings/setup"
        linkLabel="Open setup"
      />
    </div>
  );
}
