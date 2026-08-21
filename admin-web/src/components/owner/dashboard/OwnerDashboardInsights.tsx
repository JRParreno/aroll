import { useQuery } from "@tanstack/react-query";
import { CalendarClock, ClipboardCheck } from "lucide-react";
import { Link } from "react-router-dom";
import { getOwnerPayrollReport, getSetupStatus } from "@/lib/api";

function daysUntil(dateKey: string | null | undefined) {
  if (!dateKey) return null;
  const target = new Date(`${dateKey}T00:00:00`);
  if (Number.isNaN(target.getTime())) return null;
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  return Math.round((target.getTime() - today.getTime()) / 86_400_000);
}

function formatDisplayDate(value: string | null | undefined) {
  if (!value) return null;
  const date = new Date(`${value}T00:00:00`);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

function payrollStatusLabel(
  status: string | undefined,
  paydayIn: number | null
) {
  if (status === "completed") return "Period completed";
  if (status === "upcoming") return "Upcoming period";
  if (paydayIn === null) return "Not scheduled";
  if (paydayIn === 0) return "Payday is today";
  if (paydayIn < 0) return "Past due window";
  return `Due in ${paydayIn} day${paydayIn === 1 ? "" : "s"}`;
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
    <div className="owner-card p-5">
      <div className="flex items-start justify-between gap-3">
        <div className="owner-icon-well h-9 w-9">
          <Icon className="h-4 w-4" />
        </div>
        <Link
          className="rounded-lg px-2 py-1 text-xs font-medium text-[#1E3A5F] transition hover:bg-[#EEF3F8]"
          to={to}
        >
          {linkLabel}
        </Link>
      </div>
      <p className="mt-4 text-sm font-medium text-[#374151]">{title}</p>
      <p className="mt-1 text-xl font-semibold tracking-tight text-[#1F2937]">
        {loading ? "..." : value}
      </p>
      <p className="mt-2 text-xs leading-relaxed text-[#6B7280]">{helper}</p>
    </div>
  );
}

export function OwnerDashboardInsights() {
  const { data: payrollReport, isLoading: payrollLoading } = useQuery({
    queryKey: ["owner-payroll-report", "dashboard-current"],
    queryFn: () => getOwnerPayrollReport(),
  });

  const { data: setupStatus, isLoading: setupLoading } = useQuery({
    queryKey: ["setup-status"],
    queryFn: getSetupStatus,
  });

  const pendingSetup =
    setupStatus?.steps.filter((step) => !step.complete).length ?? 0;

  const payrollStepComplete = Boolean(
    setupStatus?.steps.find((step) => step.key === "payroll")?.complete
  );
  const hasPayrollPeriod = Boolean(payrollReport?.period_end);
  const payrollConfigured = payrollStepComplete || hasPayrollPeriod;

  const payday = payrollReport?.pay_date ?? payrollReport?.period_end ?? null;
  const paydayIn = payrollConfigured ? daysUntil(payday) : null;
  const paydayLabel = formatDisplayDate(payday);
  const periodLabel =
    payrollReport?.period_start && payrollReport?.period_end
      ? `${formatDisplayDate(payrollReport.period_start)} – ${formatDisplayDate(payrollReport.period_end)}`
      : null;

  return (
    <div className="flex flex-col gap-4">
      <InsightCard
        title="Payroll Status"
        icon={CalendarClock}
        loading={payrollLoading || setupLoading}
        value={
          !payrollConfigured
            ? "Not scheduled"
            : payrollStatusLabel(payrollReport?.payroll_status, paydayIn)
        }
        helper={
          !payrollConfigured
            ? "Configure payroll in Business Setup"
            : periodLabel
              ? `Current period: ${periodLabel}`
              : paydayLabel
                ? `Next payday: ${paydayLabel}`
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
