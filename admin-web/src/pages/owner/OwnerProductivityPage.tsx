import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  CalendarClock,
  CheckCircle2,
  Clock3,
  Star,
  TrendingUp,
  Users,
} from "lucide-react";
import { Link } from "react-router-dom";
import { PerformanceOverviewChart } from "@/components/owner/PerformanceOverviewChart";
import {
  OwnerPage,
  OwnerPageContent,
  OwnerPageHeader,
} from "@/components/owner/layout/OwnerPageLayout";
import { getOwnerPerformance, type EmployeePerformanceItem } from "@/lib/api";

function initials(name: string) {
  return name
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join("");
}

function EmployeeAvatar({
  name,
  imageUrl,
  className = "h-12 w-12 text-sm",
}: {
  name: string;
  imageUrl?: string | null;
  className?: string;
}) {
  return (
    <div
      className={`flex shrink-0 items-center justify-center overflow-hidden rounded-full bg-[#E7EEF5] font-bold text-[#1E466E] ${className}`}
    >
      {imageUrl ? (
        <img alt={name} className="h-full w-full object-cover" src={imageUrl} />
      ) : (
        initials(name) || "E"
      )}
    </div>
  );
}

const RANK_COLORS = ["#16A34A", "#2563EB", "#EA580C", "#1E466E", "#7C3AED"];

function monthOptions() {
  return Array.from({ length: 12 }, (_, index) => {
    const month = index + 1;
    const label = new Date(2026, index, 1).toLocaleString(undefined, {
      month: "long",
    });
    return { value: month, label };
  });
}

function formatHours(value: number) {
  if (Math.abs(value - Math.round(value)) < 0.05) return `${Math.round(value)}`;
  return value.toFixed(1);
}

function KpiCard({
  label,
  value,
  hint,
  icon: Icon,
  accent,
}: {
  label: string;
  value: string;
  hint: string;
  icon: typeof TrendingUp;
  accent: string;
}) {
  return (
    <div className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-xs font-medium text-[#6B7280]">{label}</p>
          <p className="mt-2 text-2xl font-extrabold tracking-tight text-[#111827]">
            {value}
          </p>
          <p className="mt-1 text-xs text-[#9CA3AF]">{hint}</p>
        </div>
        <div
          className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl"
          style={{ backgroundColor: `${accent}18`, color: accent }}
        >
          <Icon className="h-5 w-5" />
        </div>
      </div>
    </div>
  );
}

function RankCard({
  employee,
  rank,
}: {
  employee: EmployeePerformanceItem;
  rank: number;
}) {
  const color = RANK_COLORS[(rank - 1) % RANK_COLORS.length];
  const score = Math.max(0, Math.min(100, employee.productivity_score));

  return (
    <div className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
      <div className="flex items-center gap-3">
        <span className="w-7 text-xl font-extrabold" style={{ color }}>
          {rank}
        </span>
        <EmployeeAvatar
          imageUrl={employee.profile_image_url}
          name={employee.full_name}
        />
        <div className="min-w-0 flex-1">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <h3 className="truncate text-sm font-semibold text-[#111827]">
                {employee.full_name}
              </h3>
              <p className="truncate text-xs text-[#6B7280]">
                {employee.position_title ?? "Team member"}
                {" · "}
                {employee.attendance_rate}% attendance
              </p>
            </div>
            <div className="text-right">
              <p className="text-lg font-extrabold" style={{ color }}>
                {employee.productivity_score}
              </p>
              <p className="text-[10px] font-medium uppercase tracking-wide text-[#9CA3AF]">
                score
              </p>
            </div>
          </div>
          <div className="mt-3 h-1.5 overflow-hidden rounded-full bg-slate-100">
            <div
              className="h-full rounded-full transition-all"
              style={{ width: `${score}%`, backgroundColor: color }}
            />
          </div>
        </div>
      </div>
    </div>
  );
}

export function OwnerProductivityPage() {
  const now = new Date();
  const [year, setYear] = useState(now.getFullYear());
  const [month, setMonth] = useState(now.getMonth() + 1);
  const [showAll, setShowAll] = useState(false);

  const yearOptions = useMemo(() => {
    const current = now.getFullYear();
    return Array.from({ length: 5 }, (_, index) => current - index);
  }, [now]);

  const { data: performance, isLoading, isFetching } = useQuery({
    queryKey: ["owner-performance", year, month],
    queryFn: () => getOwnerPerformance({ year, month }),
  });

  const summary = performance?.summary;
  const employees = performance?.employees ?? [];
  const hasPerformanceData = Boolean(
    summary?.has_performance_data && employees.length > 0
  );
  const topEmployee = hasPerformanceData ? employees[0] ?? null : null;
  const visibleEmployees = showAll ? employees : employees.slice(0, 5);
  const periodLabel = new Date(year, month - 1, 1).toLocaleString(undefined, {
    month: "long",
    year: "numeric",
  });

  return (
    <OwnerPage>
      <OwnerPageHeader
        title="Productivity"
        description="Track attendance quality, punctuality, and top performers for the selected month."
        actions={
          <div className="flex flex-wrap items-center gap-2">
            <label className="flex flex-col gap-1 text-xs font-medium text-[#6B7280]">
              Month
              <select
                className="h-10 min-w-[140px] rounded-xl border border-slate-200 bg-[#FAFBFC] px-3 text-sm text-[#111827]"
                onChange={(event) => {
                  setMonth(Number(event.target.value));
                  setShowAll(false);
                }}
                value={month}
              >
                {monthOptions().map((option) => (
                  <option key={option.value} value={option.value}>
                    {option.label}
                  </option>
                ))}
              </select>
            </label>
            <label className="flex flex-col gap-1 text-xs font-medium text-[#6B7280]">
              Year
              <select
                className="h-10 min-w-[100px] rounded-xl border border-slate-200 bg-[#FAFBFC] px-3 text-sm text-[#111827]"
                onChange={(event) => {
                  setYear(Number(event.target.value));
                  setShowAll(false);
                }}
                value={year}
              >
                {yearOptions.map((option) => (
                  <option key={option} value={option}>
                    {option}
                  </option>
                ))}
              </select>
            </label>
          </div>
        }
      />

      <OwnerPageContent>
        <div className="flex flex-wrap items-center justify-between gap-2 text-sm text-[#6B7280]">
          <p>
            Showing insights for{" "}
            <span className="font-semibold text-[#111827]">{periodLabel}</span>
            {isFetching ? " · updating…" : null}
          </p>
          <Link
            className="font-medium text-[#1E466E] hover:underline"
            to="/owner/employees"
          >
            Manage employees
          </Link>
        </div>

        <section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <KpiCard
            accent="#16A34A"
            hint="Completed vs assigned shifts"
            icon={CheckCircle2}
            label="Attendance rate"
            value={
              hasPerformanceData ? `${summary?.attendance_rate ?? 0}%` : "—"
            }
          />
          <KpiCard
            accent="#2563EB"
            hint="On-time clock-ins"
            icon={Clock3}
            label="Punctuality"
            value={
              hasPerformanceData ? `${summary?.punctuality_rate ?? 0}%` : "—"
            }
          />
          <KpiCard
            accent="#EA580C"
            hint="Approved overtime hours"
            icon={CalendarClock}
            label="Overtime"
            value={
              hasPerformanceData
                ? `${formatHours(summary?.total_overtime_hours ?? 0)} hrs`
                : "—"
            }
          />
          <KpiCard
            accent="#1E466E"
            hint="Team average score"
            icon={TrendingUp}
            label="Productivity score"
            value={
              hasPerformanceData
                ? `${summary?.productivity_score ?? 0}/100`
                : "—"
            }
          />
        </section>

        <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
          <div className="mb-4 flex items-start justify-between gap-3">
            <div>
              <h2 className="text-base font-semibold text-[#1F2937]">
                Performance overview
              </h2>
              <p className="mt-1 text-sm text-[#6B7280]">
                Attendance outcomes across the selected month.
              </p>
            </div>
            <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-[#E7EEF5] text-[#1E466E]">
              <Users className="h-4 w-4" />
            </div>
          </div>
          <PerformanceOverviewChart isLoading={isLoading} summary={summary} />
        </section>

        <section className="space-y-4">
          <div className="flex items-center justify-between gap-3">
            <div>
              <h2 className="text-base font-semibold text-[#1F2937]">
                Top performing employees
              </h2>
              <p className="mt-1 text-sm text-[#6B7280]">
                Ranked by productivity score for {periodLabel}.
              </p>
            </div>
            {employees.length > 5 ? (
              <button
                className="text-sm font-semibold text-[#1E466E] hover:underline"
                onClick={() => setShowAll((value) => !value)}
                type="button"
              >
                {showAll ? "Show less" : `View all (${employees.length})`}
              </button>
            ) : null}
          </div>

          {isLoading ? (
            <p className="text-sm text-[#6B7280]">Loading performance data…</p>
          ) : !hasPerformanceData || !topEmployee ? (
            <div className="rounded-2xl border border-dashed border-slate-200 bg-white p-8 text-center shadow-sm">
              <p className="text-base font-semibold text-[#1F2937]">
                No productivity data yet
              </p>
              <p className="mx-auto mt-2 max-w-md text-sm leading-6 text-[#6B7280]">
                Rankings and employee highlights will appear once your team has
                attendance activity for this month.
              </p>
            </div>
          ) : (
            <div className="grid gap-5 lg:grid-cols-[minmax(280px,0.9fr)_1.1fr]">
              <div className="space-y-3">
                <div className="rounded-2xl border border-amber-200 bg-gradient-to-br from-[#FFF7E8] to-[#FFFBEB] p-5 shadow-sm">
                  <div className="flex items-center justify-between gap-3">
                    <p className="text-sm font-extrabold text-[#C2410C]">
                      Employee of the Month
                    </p>
                    <span className="rounded-full bg-amber-100 px-2.5 py-1 text-[11px] font-semibold text-amber-800">
                      Top score
                    </span>
                  </div>
                  <div className="mt-4 flex items-center gap-4">
                    <div className="relative">
                      <EmployeeAvatar
                        className="h-16 w-16 text-lg"
                        imageUrl={topEmployee.profile_image_url}
                        name={topEmployee.full_name}
                      />
                      <span className="absolute -bottom-1 -right-1 flex h-7 w-7 items-center justify-center rounded-full border-2 border-white bg-amber-500 text-white shadow-sm">
                        <Star className="h-3.5 w-3.5 fill-white" />
                      </span>
                    </div>
                    <div className="min-w-0">
                      <h3 className="truncate text-lg font-extrabold text-[#111827]">
                        {topEmployee.full_name}
                      </h3>
                      <p className="text-sm text-[#6B7280]">
                        {topEmployee.position_title ?? "Team member"}
                      </p>
                      <p className="mt-2 text-sm font-semibold text-[#15803D]">
                        {topEmployee.productivity_score}% productive · top
                        performer
                      </p>
                    </div>
                  </div>
                </div>

                <div className="space-y-2">
                  {topEmployee.reasons.map((reason) => (
                    <div
                      className="flex min-h-10 items-center gap-2 rounded-xl border border-amber-200 bg-[#FFFBEB] px-4 text-xs font-semibold text-[#92400E]"
                      key={reason}
                    >
                      <Star className="h-3.5 w-3.5 shrink-0 fill-[#F59E0B] text-[#F59E0B]" />
                      {reason}
                    </div>
                  ))}
                </div>
              </div>

              <div className="space-y-3">
                {visibleEmployees.map((employee, index) => (
                  <RankCard
                    employee={employee}
                    key={employee.employee_id}
                    rank={index + 1}
                  />
                ))}
              </div>
            </div>
          )}
        </section>
      </OwnerPageContent>
    </OwnerPage>
  );
}
