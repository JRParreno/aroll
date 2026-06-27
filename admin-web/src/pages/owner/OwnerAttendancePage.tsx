import { useQuery } from "@tanstack/react-query";
import { Search } from "lucide-react";
import { useMemo, useState } from "react";
import { Input } from "@/components/ui/input";
import { getOwnerAttendanceReport } from "@/lib/api";

function formatTime(value: string | null) {
  if (!value) return "--:--";
  return new Date(value).toLocaleTimeString([], {
    hour: "numeric",
    minute: "2-digit",
  });
}

function initials(name: string) {
  return name
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join("");
}

function statusCopy(status: string) {
  if (status === "late") return "Arrived late";
  if (status === "absent") return "Marked absent";
  if (status === "in_progress") return "Clocked in";
  if (status === "complete") return "Arrived on time";
  return status.replace("_", " ");
}

export function OwnerAttendancePage() {
  const [search, setSearch] = useState("");
  const [month, setMonth] = useState("all");
  const [day, setDay] = useState("all");
  const [year, setYear] = useState("all");

  const { data, isLoading } = useQuery({
    queryKey: ["owner-attendance-report"],
    queryFn: getOwnerAttendanceReport,
  });

  const filterOptions = useMemo(() => {
    const dates = (data?.records ?? []).map((record) => new Date(`${record.date}T00:00:00`));
    return {
      months: Array.from(new Set(dates.map((date) => String(date.getMonth())))),
      days: Array.from(new Set(dates.map((date) => String(date.getDate())))),
      years: Array.from(new Set(dates.map((date) => String(date.getFullYear())))),
    };
  }, [data]);

  const records = useMemo(() => {
    const needle = search.toLowerCase();
    return (data?.records ?? []).filter((record) => {
      const recordDate = new Date(`${record.date}T00:00:00`);
      return (
        [record.employee_name, record.position_title ?? "", record.status]
          .join(" ")
          .toLowerCase()
          .includes(needle) &&
        (month === "all" || String(recordDate.getMonth()) === month) &&
        (day === "all" || String(recordDate.getDate()) === day) &&
        (year === "all" || String(recordDate.getFullYear()) === year)
      );
    });
  }, [data, search, month, day, year]);

  const summary = records.reduce(
    (acc, record) => {
      if (record.status === "absent") acc.absent += 1;
      else if (record.status === "late") acc.late += 1;
      else acc.present += 1;
      return acc;
    },
    { present: 0, late: 0, absent: 0 }
  );

  const maxCount = Math.max(summary.present, summary.late, summary.absent, 1);
  const total = summary.present + summary.late + summary.absent;
  const presentPercent = total > 0 ? Math.round((summary.present / total) * 100) : 0;

  return (
    <div className="min-h-screen bg-[#F7F8FA]">
      <header className="border-b border-slate-200 bg-white px-5 py-6 sm:px-8">
        <h1 className="text-2xl font-semibold text-[#111827]">Attendance</h1>
      </header>

      <main className="mx-auto max-w-6xl space-y-5 px-5 py-5 sm:px-8">
        <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
          <div className="mx-auto max-w-3xl space-y-3">
            <div className="relative">
              <Search className="absolute left-4 top-3 h-5 w-5 text-[#6B7280]" />
              <Input
                className="h-11 rounded-xl bg-[#FAFBFC] pl-12"
                placeholder="Search employee"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
              />
            </div>
            <div className="grid gap-3 sm:grid-cols-3">
              <select
                className="h-10 rounded-xl border border-slate-200 bg-[#FAFBFC] px-4 text-sm text-[#374151]"
                value={month}
                onChange={(e) => setMonth(e.target.value)}
              >
                <option value="all">Month</option>
                {filterOptions.months.map((value) => (
                  <option key={value} value={value}>
                    {new Date(2026, Number(value), 1).toLocaleDateString(undefined, {
                      month: "long",
                    })}
                  </option>
                ))}
              </select>
              <select
                className="h-10 rounded-xl border border-slate-200 bg-[#FAFBFC] px-4 text-sm text-[#374151]"
                value={day}
                onChange={(e) => setDay(e.target.value)}
              >
                <option value="all">Day</option>
                {filterOptions.days.map((value) => (
                  <option key={value} value={value}>
                    {value}
                  </option>
                ))}
              </select>
              <select
                className="h-10 rounded-xl border border-slate-200 bg-[#FAFBFC] px-4 text-sm text-[#374151]"
                value={year}
                onChange={(e) => setYear(e.target.value)}
              >
                <option value="all">Year</option>
                {filterOptions.years.map((value) => (
                  <option key={value} value={value}>
                    {value}
                  </option>
                ))}
              </select>
            </div>
          </div>
        </section>

        <section className="grid gap-5 lg:grid-cols-[1fr_220px]">
          <div className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
            <div className="flex h-40 items-end gap-12 border-b border-l border-slate-200 px-8">
              {[
                { label: "on time", value: summary.present, color: "#BEF7A5" },
                { label: "late", value: summary.late, color: "#FDBA74" },
                { label: "absent", value: summary.absent, color: "#F87171" },
              ].map((item) => (
                <div className="flex flex-1 flex-col items-center gap-2" key={item.label}>
                  <div
                    className="w-full max-w-16 rounded-t-lg"
                    style={{
                      height: `${Math.max((item.value / maxCount) * 100, item.value ? 14 : 0)}%`,
                      backgroundColor: item.color,
                    }}
                  />
                  <span className="text-xs text-[#6B7280]">{item.label}</span>
                </div>
              ))}
            </div>
          </div>

          <div className="flex items-center justify-center rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
            <div
              className="flex h-32 w-32 items-center justify-center rounded-full"
              style={{
                background: `conic-gradient(#45E035 0 ${presentPercent}%, #EEF2F7 ${presentPercent}% 100%)`,
              }}
            >
              <div className="flex h-20 w-20 flex-col items-center justify-center rounded-full bg-white">
                <span className="text-[10px] font-medium uppercase text-[#6B7280]">
                  Present
                </span>
                <span className="text-sm font-semibold text-[#1F2937]">
                  {presentPercent}%
                </span>
              </div>
            </div>
          </div>
        </section>

        <section className="max-h-[430px] overflow-y-auto pr-2">
          {isLoading ? (
            <div className="rounded-2xl border border-slate-200 bg-white p-6 text-sm text-[#6B7280] shadow-sm">
              Loading attendance...
            </div>
          ) : records.length === 0 ? (
            <div className="rounded-2xl border border-slate-200 bg-white p-6 text-sm text-[#6B7280] shadow-sm">
              No attendance records found.
            </div>
          ) : (
            <div className="grid gap-4 lg:grid-cols-2">
              {records.map((record) => {
                const late = record.status === "late";
                const absent = record.status === "absent";
                return (
                  <div
                    className="flex items-center gap-4 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm"
                    key={record.id}
                  >
                    <div className="flex h-14 w-14 shrink-0 items-center justify-center rounded-full bg-slate-100 text-sm font-semibold text-[#374151]">
                      {initials(record.employee_name)}
                    </div>
                    <div className="min-w-0 flex-1">
                      <h2 className="truncate text-sm font-semibold text-[#111827]">
                        {record.employee_name}
                      </h2>
                      <p className="mt-0.5 text-xs text-[#6B7280]">
                        {record.shift_name ?? record.position_title ?? "Attendance"}
                      </p>
                      <p className="text-xs text-[#6B7280]">
                        {statusCopy(record.status)}
                      </p>
                    </div>
                    <span
                      className={`rounded-full px-3 py-1 text-xs font-semibold ${
                        absent
                          ? "bg-red-100 text-red-700"
                          : late
                            ? "bg-orange-100 text-orange-700"
                            : "bg-green-100 text-green-700"
                      }`}
                    >
                      {absent ? "Absent" : formatTime(record.time_in)}
                    </span>
                  </div>
                );
              })}
            </div>
          )}
        </section>
      </main>
    </div>
  );
}
