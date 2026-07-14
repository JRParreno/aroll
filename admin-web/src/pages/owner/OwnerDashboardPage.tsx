import { useQuery } from "@tanstack/react-query";
import { Activity, Clock3, TrendingUp, UserRound } from "lucide-react";
import { Link } from "react-router-dom";
import { OwnerDashboardInsights } from "@/components/owner/dashboard/OwnerDashboardInsights";
import { PerformanceOverviewChart } from "@/components/owner/PerformanceOverviewChart";
import {
  OwnerPage,
  OwnerPageContent,
  OwnerPageHeader,
} from "@/components/owner/layout/OwnerPageLayout";
import { SetupProgressCard } from "@/components/owner/SetupProgressCard";
import { getMe, getOwnerPerformance, getSetupStatus } from "@/lib/api";
import { ME_QUERY_KEY } from "@/lib/authSession";

export function OwnerDashboardPage() {
  const { data: me } = useQuery({
    queryKey: ME_QUERY_KEY,
    queryFn: getMe,
  });
  const { data: setupStatus } = useQuery({
    queryKey: ["setup-status"],
    queryFn: getSetupStatus,
  });
  const { data: performance, isLoading } = useQuery({
    queryKey: ["owner-performance", 30],
    queryFn: () => getOwnerPerformance(30),
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
    },
    {
      label: "Punctuality",
      value: `${summary?.punctuality_rate ?? 0}%`,
      icon: Clock3,
      helper: `${summary?.on_time_clock_ins ?? 0} on-time clock-ins`,
    },
    {
      label: "Overtime",
      value: `${summary?.total_overtime_hours ?? 0} hrs`,
      icon: TrendingUp,
      helper: `${summary?.overtime_shifts ?? 0} overtime shifts`,
    },
    {
      label: "Productivity",
      value: `${summary?.productivity_score ?? 0}/100`,
      icon: UserRound,
      helper: "Average employee score",
    },
  ];

  return (
    <OwnerPage>
      <OwnerPageHeader
        eyebrow="Welcome back"
        title={`${businessName} Dashboard`}
      />

      <OwnerPageContent>
        {setupStatus && !setupStatus.setup_completed_at && (
          <SetupProgressCard status={setupStatus} />
        )}

        <section className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
          {metrics.map((metric) => {
            const Icon = metric.icon;
            return (
              <div
                className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm"
                key={metric.label}
              >
                <div className="flex items-center justify-between">
                  <div className="rounded-xl bg-[#F3F6FA] p-2 text-[#1E3A5F]">
                    <Icon className="h-5 w-5" />
                  </div>
                  <span className="text-xs font-medium text-emerald-700">
                    Live
                  </span>
                </div>
                <p className="mt-5 text-2xl font-semibold text-[#1F2937]">
                  {isLoading ? "..." : metric.value}
                </p>
                <p className="mt-1 text-sm font-medium text-[#374151]">
                  {metric.label}
                </p>
                <p className="mt-2 text-xs text-[#6B7280]">{metric.helper}</p>
              </div>
            );
          })}
        </section>

        <section className="grid items-start gap-4 xl:grid-cols-[minmax(0,1fr)_320px]">
          <div className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
            <div className="mb-4 flex items-center justify-between gap-4">
              <div>
                <h2 className="text-lg font-semibold text-[#1F2937]">
                  Performance Overview
                </h2>
                <p className="text-sm text-[#6B7280]">
                  Based on actual attendance and assigned shifts.
                </p>
              </div>
              <Link className="shrink-0 text-sm font-medium text-[#1E3A5F]" to="/owner/productivity">
                View insights
              </Link>
            </div>
            <PerformanceOverviewChart isLoading={isLoading} summary={summary} />
          </div>

          <OwnerDashboardInsights />
        </section>
      </OwnerPageContent>
    </OwnerPage>
  );
}
