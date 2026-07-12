import { useQuery } from "@tanstack/react-query";
import { Star } from "lucide-react";
import { Link } from "react-router-dom";
import { PerformanceOverviewChart } from "@/components/owner/PerformanceOverviewChart";
import { getMe, getOwnerPerformance } from "@/lib/api";
import { ME_QUERY_KEY } from "@/lib/authSession";

function initials(name: string) {
  return name
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join("");
}

export function OwnerProductivityPage() {
  const { data: me } = useQuery({
    queryKey: ME_QUERY_KEY,
    queryFn: getMe,
  });

  const { data: performance, isLoading } = useQuery({
    queryKey: ["owner-performance", 30],
    queryFn: () => getOwnerPerformance(30),
  });

  const businessName =
    me?.business_name ?? localStorage.getItem("aroll_business_name") ?? "Aroll+";
  const summary = performance?.summary;
  const hasPerformanceData = Boolean(summary?.has_performance_data);
  const topEmployee = hasPerformanceData ? performance?.employees[0] ?? null : null;

  return (
    <div className="min-h-screen bg-[#f3f3f3]">
      <header className="flex h-[72px] items-center justify-between border-b border-[#9f9f9f] bg-white px-5 sm:px-7">
        <h1 className="text-2xl font-extrabold text-black sm:text-[28px]">
          Performance Insights
        </h1>
        <div className="flex h-12 w-12 items-center justify-center overflow-hidden rounded-full bg-[#f7ead4] p-1 shadow-sm">
          <div className="flex h-full w-full items-center justify-center rounded-full bg-[#354151] text-sm font-bold text-white">
            {businessName.slice(0, 1).toUpperCase()}
          </div>
        </div>
      </header>

      <main className="px-5 py-4 sm:px-7">
        <section>
          <h2 className="mb-1 text-[22px] font-medium text-[#262626]">
            Performance Overview
          </h2>
          <p className="mb-4 text-sm text-[#6B7280]">
            Live attendance and shift activity.
          </p>
          <div className="rounded-md border border-[#b6b6b6] bg-white px-5 py-4 shadow-sm">
            <PerformanceOverviewChart isLoading={isLoading} summary={summary} />
          </div>
        </section>

        <section className="mt-9">
          <div className="mb-5 flex items-center justify-between">
            <h2 className="text-[22px] font-extrabold text-[#202020]">
              Top Performing Employees
            </h2>
            <Link
              className="text-sm font-medium text-[#1475df]"
              to="/owner/employees"
            >
              View All
            </Link>
          </div>

          {isLoading ? (
            <p className="text-sm text-muted-foreground">
              Loading performance data...
            </p>
          ) : !hasPerformanceData ? (
            <div className="grid gap-6 lg:grid-cols-[minmax(280px,0.95fr)_1fr]">
              <div>
                <div className="rounded-md border border-slate-200 bg-white p-6 shadow-sm">
                  <p className="text-base font-semibold text-[#1F2937]">
                    No Data Available Yet
                  </p>
                  <p className="mt-2 text-sm leading-6 text-[#6B7280]">
                    No attendance or productivity records have been collected
                    yet. Performance insights will appear once employee
                    activity has been recorded.
                  </p>
                </div>
                <div className="mt-2 space-y-2">
                  {[1, 2, 3].map((item) => (
                    <div
                      className="min-h-9 rounded-md border border-slate-200 bg-white px-6 py-2 text-xs text-[#9CA3AF] shadow-sm"
                      key={item}
                    >
                      Performance reason placeholder
                    </div>
                  ))}
                </div>
              </div>

              <div className="space-y-4">
                <div className="rounded-md border border-slate-200 bg-white p-6 shadow-sm">
                  <p className="text-base font-semibold text-[#1F2937]">
                    No Employee Performance Data Available
                  </p>
                  <p className="mt-2 text-sm leading-6 text-[#6B7280]">
                    Employee performance records will appear here once
                    attendance and productivity data have been collected.
                  </p>
                </div>
                {[1, 2, 3].map((item) => (
                  <div
                    className="flex items-center gap-3 rounded-md border border-slate-200 bg-white px-3 py-3 opacity-70 shadow-sm"
                    key={item}
                  >
                    <span className="text-2xl font-medium text-[#CBD5E1]">
                      {item}
                    </span>
                    <div className="h-14 w-14 rounded-full bg-slate-100" />
                    <div className="flex-1 space-y-3">
                      <div className="h-3 w-36 rounded-full bg-slate-100" />
                      <div className="h-0.5 w-44 bg-slate-100" />
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ) : !topEmployee ? (
            <div className="rounded-md border bg-white p-6 text-sm text-muted-foreground">
              No employee performance records yet.
            </div>
          ) : (
            <div className="grid gap-6 lg:grid-cols-[minmax(280px,0.95fr)_1fr]">
              <div>
                <div className="rounded-md border border-[#f4d987] bg-[#fff4cf] p-4 shadow-sm">
                  <p className="text-sm font-extrabold text-[#f07800]">
                    Employee of the Month
                  </p>
                  <div className="mt-2 flex items-center justify-between gap-4">
                    <div>
                      <h3 className="text-xl font-extrabold text-black">
                        {topEmployee.full_name}
                      </h3>
                      <p className="mt-2 text-sm font-medium text-[#229000]">
                        {topEmployee.productivity_score}% Productive: Top
                        Performer
                      </p>
                    </div>
                    <div className="flex h-16 w-16 shrink-0 items-center justify-center rounded-full bg-[#d8d8d8] text-lg font-extrabold text-[#333]">
                      {initials(topEmployee.full_name)}
                    </div>
                  </div>
                </div>

                <div className="mt-1 space-y-1">
                  {topEmployee.reasons.map((reason) => (
                    <div
                      className="flex min-h-8 items-center gap-2 rounded-md border border-[#ead491] bg-[#fff6d8] px-6 text-xs font-bold text-black shadow-sm"
                      key={reason}
                    >
                      <Star className="h-4 w-4 fill-[#f4be26] text-[#f4be26]" />
                      {reason}
                    </div>
                  ))}
                </div>
              </div>

              <div className="space-y-7">
                {performance?.employees.slice(0, 3).map((employee, index) => {
                  const colors = ["#3fbf29", "#2a7fe3", "#f07817"];
                  const color = colors[index] ?? "#1f456b";

                  return (
                    <div
                      className="flex items-center gap-3 rounded-md bg-white px-3 py-3 shadow-md"
                      key={employee.employee_id}
                    >
                      <span
                        className="text-2xl font-extrabold"
                        style={{ color }}
                      >
                        {index + 1}
                      </span>
                      <div className="flex h-14 w-14 shrink-0 items-center justify-center rounded-full bg-[#d8d8d8] text-sm font-extrabold text-[#333]">
                        {initials(employee.full_name)}
                      </div>
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center justify-between gap-4">
                          <h3 className="truncate text-xl font-extrabold text-black">
                            {employee.full_name}
                          </h3>
                          <span
                            className="text-2xl font-medium"
                            style={{ color }}
                          >
                            {employee.productivity_score}
                          </span>
                        </div>
                        <div
                          className="mt-4 h-0.5 max-w-[220px]"
                          style={{ backgroundColor: color }}
                        />
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          )}
        </section>
      </main>
    </div>
  );
}
