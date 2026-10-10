import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Activity, Clock3, TrendingUp } from "lucide-react";
import { OwnerDashboardInsights } from "@/components/owner/dashboard/OwnerDashboardInsights";
import {
  PerformanceOverviewChart,
  type PerformanceBarCategory,
} from "@/components/owner/PerformanceOverviewChart";
import {
  OwnerCard,
  OwnerPage,
  OwnerPageContent,
  OwnerPageHeader,
} from "@/components/owner/layout/OwnerPageLayout";
import { SetupProgressCard } from "@/components/owner/SetupProgressCard";
import { PrototypeNotice } from "@/components/tenant/PrototypeNotice";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  getOwnerPerformance,
  getSetupStatus,
  type OwnerPerformanceEventItem,
} from "@/lib/api";
import { formatAttendanceTime } from "@/lib/attendanceTime";
import { useTenantMode } from "@/lib/tenantMode";

type PerformancePeriod = "week" | "month" | "year";

const PERIOD_OPTIONS: { id: PerformancePeriod; label: string }[] = [
  { id: "week", label: "Weekly" },
  { id: "month", label: "Monthly" },
  { id: "year", label: "Yearly" },
];

function periodBadge(period: PerformancePeriod, isDemo: boolean) {
  const label =
    period === "week" ? "This week" : period === "month" ? "This month" : "This year";
  return isDemo ? `Simulated · ${label}` : label;
}

export function OwnerDashboardPage() {
  const { me, isDemo } = useTenantMode();
  const [period, setPeriod] = useState<PerformancePeriod>("week");
  const [selectedBar, setSelectedBar] = useState<{
    category: PerformanceBarCategory;
    label: string;
  } | null>(null);

  const { data: setupStatus } = useQuery({
    queryKey: ["setup-status"],
    queryFn: getSetupStatus,
  });
  const { data: performance, isLoading } = useQuery({
    queryKey: ["owner-performance", period],
    queryFn: () => getOwnerPerformance({ period }),
  });

  const businessName =
    me?.business_name ?? localStorage.getItem("aroll_business_name") ?? "Aroll+";
  const summary = performance?.summary;
  const timeZone = me?.timezone;
  const events = performance?.events ?? [];

  const selectedEvents = useMemo(() => {
    if (!selectedBar) return [] as OwnerPerformanceEventItem[];
    return events.filter((event) => event.category === selectedBar.category);
  }, [events, selectedBar]);

  const metrics = [
    {
      label: "Attendance Rate",
      value: `${summary?.attendance_rate ?? 0}%`,
      icon: Activity,
      helper: `${summary?.attended_shifts ?? 0}/${summary?.assigned_shifts ?? 0} shifts attended`,
      accent: "from-emerald-50 to-white",
      iconTone: "bg-emerald-50 text-emerald-700",
    },
    {
      label: "Punctuality",
      value: `${summary?.punctuality_rate ?? 0}%`,
      icon: Clock3,
      helper: `${summary?.on_time_clock_ins ?? 0} on-time Time Ins`,
      accent: "from-sky-50 to-white",
      iconTone: "bg-sky-50 text-sky-700",
    },
    {
      label: "Overtime",
      value: `${summary?.total_overtime_hours ?? 0} hrs`,
      icon: TrendingUp,
      helper: `${summary?.overtime_shifts ?? 0} overtime shifts`,
      accent: "from-amber-50 to-white",
      iconTone: "bg-amber-50 text-amber-700",
    },
  ];

  return (
    <OwnerPage className="owner-dashboard-page">
      <OwnerPageHeader
        eyebrow="Welcome back"
        title={`${businessName} Dashboard`}
        description={
          isDemo
            ? "Simulated attendance snapshot for demonstration only."
            : "A clear snapshot of attendance health and overtime."
        }
      />

      <OwnerPageContent className="owner-dashboard-content">
        <PrototypeNotice />
        {setupStatus && !setupStatus.setup_completed_at && (
          <SetupProgressCard status={setupStatus} />
        )}

        <section className="grid shrink-0 gap-3 md:grid-cols-3">
          {metrics.map((metric) => {
            const Icon = metric.icon;
            return (
              <OwnerCard
                className={`relative overflow-hidden bg-gradient-to-br ${metric.accent} p-4 sm:p-5`}
                key={metric.label}
              >
                <div className="pointer-events-none absolute -right-6 -top-6 h-20 w-20 rounded-full bg-white/60" />
                <div className="relative flex items-center justify-between">
                  <div className={`rounded-xl p-2.5 ${metric.iconTone}`}>
                    <Icon className="h-5 w-5" />
                  </div>
                  <span className="rounded-full bg-white/80 px-2 py-0.5 text-[11px] font-medium uppercase tracking-wide text-[#6B7280] ring-1 ring-slate-200/80">
                    {periodBadge(period, Boolean(isDemo))}
                  </span>
                </div>
                <p className="relative mt-3 text-2xl font-semibold tracking-tight text-[#1F2937]">
                  {isLoading ? "..." : metric.value}
                </p>
                <p className="relative mt-1 text-[0.9375rem] font-medium text-[#374151]">
                  {metric.label}
                </p>
                <p className="owner-section-subtitle relative mt-1.5 text-[0.8125rem]">
                  {metric.helper}
                </p>
              </OwnerCard>
            );
          })}
        </section>

        <section className="owner-dashboard-main grid items-stretch gap-3 lg:grid-cols-[minmax(0,1fr)_minmax(16rem,20rem)]">
          <OwnerCard className="flex h-full min-h-0 flex-col p-4 sm:p-5">
            <div className="mb-3 flex shrink-0 flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
              <div>
                <h2 className="owner-section-title">Performance Overview</h2>
                <p className="owner-section-subtitle mt-1">
                  {isDemo
                    ? "Simulated/demo attendance data. Not a real employee performance evaluation."
                    : "Based on actual attendance and assigned shifts. Tap a bar to view employees."}
                </p>
              </div>
              <div className="inline-flex rounded-xl border border-slate-200 bg-[#F8FAFC] p-1">
                {PERIOD_OPTIONS.map((option) => {
                  const active = period === option.id;
                  return (
                    <button
                      key={option.id}
                      type="button"
                      onClick={() => {
                        setPeriod(option.id);
                        setSelectedBar(null);
                      }}
                      className={`rounded-lg px-3 py-1.5 text-xs font-semibold transition ${
                        active
                          ? "bg-white text-[var(--owner-navy)] shadow-sm"
                          : "text-[#6B7280] hover:text-[#374151]"
                      }`}
                    >
                      {option.label}
                    </button>
                  );
                })}
              </div>
            </div>
            <div className="flex min-h-0 flex-1 flex-col">
              <PerformanceOverviewChart
                className="min-h-0 flex-1"
                isLoading={isLoading}
                summary={summary}
                onBarClick={({ category, label }) =>
                  setSelectedBar({ category, label })
                }
              />
            </div>
          </OwnerCard>

          <OwnerDashboardInsights />
        </section>
      </OwnerPageContent>

      <Dialog
        open={Boolean(selectedBar)}
        onOpenChange={(open) => {
          if (!open) setSelectedBar(null);
        }}
      >
        <DialogContent className="max-w-md gap-0 overflow-hidden border-slate-200 p-0 sm:rounded-2xl">
          <div className="border-b border-[#E8EEF4] px-5 py-4">
            <DialogHeader>
              <DialogTitle className="text-[15px] font-extrabold text-[#111827]">
                {selectedBar?.label ?? "Employees"}
              </DialogTitle>
            </DialogHeader>
            <p className="mt-1 text-xs text-[#6B7280]">
              Exact attendance Time In / Time Out for this status in the selected
              period.
            </p>
          </div>
          <div className="max-h-[60vh] overflow-y-auto px-5 py-3">
            {selectedEvents.length === 0 ? (
              <div className="rounded-xl border border-dashed border-slate-200 bg-[#FAFBFC] px-4 py-6 text-center">
                <p className="text-sm font-medium text-[#374151]">
                  No employees found for this period.
                </p>
              </div>
            ) : (
              <ul className="divide-y divide-[#EEF2F7]">
                {selectedEvents.map((event, index) => (
                  <li
                    key={`${event.employee_id}_${event.work_date}_${event.category}_${index}`}
                    className="py-3"
                  >
                    <p className="truncate text-sm font-semibold text-[#111827]">
                      {event.full_name}
                    </p>
                    <p className="mt-0.5 text-xs text-[#6B7280]">
                      {event.work_date}
                    </p>
                    <div className="mt-2 grid grid-cols-2 gap-2 text-xs">
                      <div>
                        <p className="font-semibold text-[#6B7280]">Time In</p>
                        <p className="mt-0.5 font-semibold text-[#111827]">
                          {formatAttendanceTime(event.time_in, timeZone)}
                        </p>
                      </div>
                      <div>
                        <p className="font-semibold text-[#6B7280]">Time Out</p>
                        <p className="mt-0.5 font-semibold text-[#111827]">
                          {formatAttendanceTime(event.time_out, timeZone)}
                        </p>
                      </div>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </div>
          <div className="border-t border-[#E8EEF4] px-5 py-3">
            <Button
              type="button"
              variant="outline"
              className="w-full rounded-xl"
              onClick={() => setSelectedBar(null)}
            >
              Close
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </OwnerPage>
  );
}
