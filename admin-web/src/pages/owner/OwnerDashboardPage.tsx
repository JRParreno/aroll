import { useQuery } from "@tanstack/react-query";
import { Activity, Clock3, TrendingUp } from "lucide-react";
import { OwnerDashboardInsights } from "@/components/owner/dashboard/OwnerDashboardInsights";
import { PerformanceOverviewChart } from "@/components/owner/PerformanceOverviewChart";
import {
  OwnerCard,
  OwnerPage,
  OwnerPageContent,
  OwnerPageHeader,
} from "@/components/owner/layout/OwnerPageLayout";
import { SetupProgressCard } from "@/components/owner/SetupProgressCard";
import { PrototypeNotice } from "@/components/tenant/PrototypeNotice";
import { getOwnerPerformance, getSetupStatus } from "@/lib/api";
import { useTenantMode } from "@/lib/tenantMode";

export function OwnerDashboardPage() {
  const { me, isDemo } = useTenantMode();
  const { data: setupStatus } = useQuery({
    queryKey: ["setup-status"],
    queryFn: getSetupStatus,
  });
  const { data: performance, isLoading } = useQuery({
    queryKey: ["owner-performance", 30],
    queryFn: () => getOwnerPerformance({ days: 30 }),
  });

  const businessName =
    me?.business_name ?? localStorage.getItem("aroll_business_name") ?? "Aroll+";
  const summary = performance?.summary;
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
    <OwnerPage>
      <OwnerPageHeader
        eyebrow="Welcome back"
        title={`${businessName} Dashboard`}
        description={
          isDemo
            ? "Simulated attendance snapshot for demonstration only."
            : "A clear snapshot of attendance health and overtime."
        }
      />

      <OwnerPageContent>
        <PrototypeNotice />
        {setupStatus && !setupStatus.setup_completed_at && (
          <SetupProgressCard status={setupStatus} />
        )}

        <section className="grid gap-4 md:grid-cols-3">
          {metrics.map((metric) => {
            const Icon = metric.icon;
            return (
              <OwnerCard
                className={`relative overflow-hidden bg-gradient-to-br ${metric.accent} p-5`}
                key={metric.label}
              >
                <div className="pointer-events-none absolute -right-6 -top-6 h-20 w-20 rounded-full bg-white/60" />
                <div className="relative flex items-center justify-between">
                  <div className={`rounded-xl p-2.5 ${metric.iconTone}`}>
                    <Icon className="h-5 w-5" />
                  </div>
                  <span className="rounded-full bg-white/80 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-[#6B7280] ring-1 ring-slate-200/80">
                    {isDemo ? "Simulated · 30 days" : "30 days"}
                  </span>
                </div>
                <p className="relative mt-5 text-2xl font-semibold tracking-tight text-[#1F2937]">
                  {isLoading ? "..." : metric.value}
                </p>
                <p className="relative mt-1 text-sm font-medium text-[#374151]">
                  {metric.label}
                </p>
                <p className="relative mt-2 text-xs leading-relaxed text-[#6B7280]">
                  {metric.helper}
                </p>
              </OwnerCard>
            );
          })}
        </section>

        <section className="grid items-start gap-4 xl:grid-cols-[minmax(0,1fr)_320px]">
          <OwnerCard className="p-5 sm:p-6">
            <div className="mb-5">
              <h2 className="owner-section-title">Performance Overview</h2>
              <p className="owner-section-subtitle mt-1">
                {isDemo
                  ? "Simulated/demo attendance data. Not a real employee performance evaluation."
                  : "Based on actual attendance and assigned shifts."}
              </p>
            </div>
            <PerformanceOverviewChart isLoading={isLoading} summary={summary} />
          </OwnerCard>

          <OwnerDashboardInsights />
        </section>
      </OwnerPageContent>
    </OwnerPage>
  );
}
