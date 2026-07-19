import { useQuery } from "@tanstack/react-query";
import { Search } from "lucide-react";
import { useMemo, useState } from "react";
import { Input } from "@/components/ui/input";
import {
  OwnerPage,
  OwnerPageContent,
  OwnerPageHeader,
} from "@/components/owner/layout/OwnerPageLayout";
import { getOwnerAttendanceReport } from "@/lib/api";

function formatTime(value: string | null) {
  if (!value) return "--:--";
  return new Date(value).toLocaleTimeString([], {
    hour: "numeric",
    minute: "2-digit",
  });
}

function formatWeekday(value?: string) {
  if (!value) return "";
  return value.charAt(0).toUpperCase() + value.slice(1);
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

  const restDayWork = useMemo(() => {
    const needle = search.toLowerCase();
    const source = data?.rest_day_work ?? (data?.records ?? []).filter(
      (record) => record.is_rest_day && record.time_in
    );
    return source.filter((record) => {
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
      if (record.is_rest_day && record.time_in) acc.restDay += 1;
      return acc;
    },
    { present: 0, late: 0, absent: 0, restDay: 0 }
  );

  const maxCount = Math.max(summary.present, summary.late, summary.absent, 1);
  const total = summary.present + summary.late + summary.absent;
  const presentPercent = total > 0 ? Math.round((summary.present / total) * 100) : 0;
  const restDayLabel = "Rest day";

  return (
    <OwnerPage>
      <OwnerPageHeader title="Attendance" />

      <OwnerPageContent>
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

        <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h2 className="text-base font-semibold text-[#1F2937]">
                Rest Day Work
              </h2>
              <p className="mt-1 text-sm text-[#6B7280]">
                Employees who clocked in or out on {restDayLabel}
                {typeof data?.rest_day_premium_percent === "number"
                  ? ` · ${data.rest_day_premium_percent}% premium`
                  : ""}
                .
              </p>
            </div>
            <span className="rounded-full bg-sky-50 px-3 py-1 text-xs font-semibold text-sky-700">
              {restDayWork.length} record{restDayWork.length === 1 ? "" : "s"}
            </span>
          </div>
          {restDayWork.length === 0 ? (
            <p className="mt-4 text-sm text-[#6B7280]">
              No rest day time-in/out records for this filter.
            </p>
          ) : (
            <div className="mt-4 grid gap-3 lg:grid-cols-2">
              {restDayWork.map((record) => {
                const unauthorized = record.rest_day_authorized === false;
                return (
                  <div
                    className={`flex items-center gap-4 rounded-xl border p-4 ${
                      unauthorized
                        ? "border-amber-200 bg-amber-50/70"
                        : "border-sky-100 bg-sky-50/60"
                    }`}
                    key={`rest-${record.id}`}
                  >
                    <div
                      className={`flex h-12 w-12 shrink-0 items-center justify-center rounded-full text-sm font-semibold ${
                        unauthorized
                          ? "bg-amber-100 text-amber-800"
                          : "bg-sky-100 text-sky-800"
                      }`}
                    >
                      {initials(record.employee_name)}
                    </div>
                    <div className="min-w-0 flex-1">
                      <h3 className="truncate text-sm font-semibold text-[#111827]">
                        {record.employee_name}
                      </h3>
                      <p className="mt-0.5 text-xs text-[#6B7280]">
                        {record.date}
                        {record.weekday ? ` · ${formatWeekday(record.weekday)}` : ""}
                        {record.shift_name ? ` · ${record.shift_name}` : ""}
                      </p>
                      <p className="text-xs text-[#6B7280]">
                        In {formatTime(record.time_in)} · Out {formatTime(record.time_out)}
                      </p>
                    </div>
                    <span
                      className={`rounded-full px-3 py-1 text-xs font-semibold ${
                        unauthorized
                          ? "bg-amber-100 text-amber-800"
                          : "bg-sky-100 text-sky-800"
                      }`}
                    >
                      {unauthorized ? "Not permitted" : "Rest day"}
                    </span>
                  </div>
                );
              })}
            </div>
          )}
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
                const restDay = Boolean(record.is_rest_day && record.time_in);
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
                        {restDay ? " · Rest day" : ""}
                      </p>
                    </div>
                    <span
                      className={`rounded-full px-3 py-1 text-xs font-semibold ${
                        absent
                          ? "bg-red-100 text-red-700"
                          : restDay
                            ? "bg-sky-100 text-sky-800"
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
      </OwnerPageContent>
    </OwnerPage>
  );
}
