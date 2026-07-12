import { useQuery } from "@tanstack/react-query";
import { Activity, Clock3, MapPin, TrendingUp, UserRound, WalletCards } from "lucide-react";
import { Link } from "react-router-dom";
import { PerformanceOverviewChart } from "@/components/owner/PerformanceOverviewChart";
import { SetupProgressCard } from "@/components/owner/SetupProgressCard";
import { getMe, getOwnerPerformance, getSetupStatus } from "@/lib/api";
import { ME_QUERY_KEY } from "@/lib/authSession";

const quickActions = [
  { label: "Employees", to: "/owner/employees", icon: UserRound },
  { label: "Location", to: "/owner/location", icon: MapPin },
  { label: "Payroll", to: "/owner/payroll", icon: WalletCards },
  { label: "Productivity", to: "/owner/productivity", icon: TrendingUp },
];

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
    <div className="min-h-screen bg-[#F7F8FA]">
      <header className="border-b border-slate-200 bg-white px-5 py-6 sm:px-8">
        <p className="text-sm font-medium text-[#6B7280]">Welcome back</p>
        <h1 className="mt-1 text-2xl font-semibold text-[#1F2937]">
          {businessName} Dashboard
        </h1>
      </header>

      <main className="space-y-6 px-5 py-6 sm:px-8">
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

        <section className="grid gap-6 xl:grid-cols-[1.4fr_0.8fr]">
          <div className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
            <div className="mb-6 flex items-center justify-between">
              <div>
                <h2 className="text-lg font-semibold text-[#1F2937]">
                  Performance Overview
                </h2>
                <p className="text-sm text-[#6B7280]">
                  Based on actual attendance and assigned shifts.
                </p>
              </div>
              <Link className="text-sm font-medium text-[#1E3A5F]" to="/owner/productivity">
                View insights
              </Link>
            </div>
            <PerformanceOverviewChart isLoading={isLoading} summary={summary} />
          </div>

          <div className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
            <h2 className="text-lg font-semibold text-[#1F2937]">Quick Actions</h2>
            <div className="mt-5 space-y-3">
              {quickActions.map((action) => {
                const Icon = action.icon;
                return (
                  <Link
                    className="flex items-center gap-3 rounded-xl border border-slate-100 p-3 transition hover:bg-[#FAFBFC]"
                    key={action.label}
                    to={action.to}
                  >
                    <span className="rounded-lg bg-[#F3F6FA] p-2 text-[#1E3A5F]">
                      <Icon className="h-4 w-4" />
                    </span>
                    <span className="text-sm font-medium text-[#1F2937]">
                      {action.label}
                    </span>
                  </Link>
                );
              })}
            </div>
          </div>
        </section>
      </main>
    </div>
  );
}
