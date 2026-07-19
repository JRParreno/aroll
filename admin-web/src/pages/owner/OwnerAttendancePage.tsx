import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Search } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { toast } from "sonner";
import { Input } from "@/components/ui/input";
import {
  OwnerPage,
  OwnerPageContent,
  OwnerPageHeader,
} from "@/components/owner/layout/OwnerPageLayout";
import {
  approveOwnerAttendanceCorrection,
  getOwnerAttendanceCorrections,
  getOwnerAttendanceReport,
  rejectOwnerAttendanceCorrection,
  type OwnerAttendanceCorrection,
} from "@/lib/api";

function todayIso() {
  const now = new Date();
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, "0");
  const d = String(now.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

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

function formatDisplayDate(value: string) {
  const date = new Date(`${value}T00:00:00`);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
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
  const queryClient = useQueryClient();
  const [search, setSearch] = useState("");
  const [date, setDate] = useState(todayIso);
  const [debouncedSearch, setDebouncedSearch] = useState("");
  const [rejectingId, setRejectingId] = useState<string | null>(null);
  const [rejectNote, setRejectNote] = useState("");

  useEffect(() => {
    const handle = window.setTimeout(() => {
      setDebouncedSearch(search.trim());
    }, 250);
    return () => window.clearTimeout(handle);
  }, [search]);

  const { data, isLoading, isError, refetch, isFetching } = useQuery({
    queryKey: ["owner-attendance-report", date, debouncedSearch],
    queryFn: () =>
      getOwnerAttendanceReport({
        date: date || undefined,
        q: debouncedSearch || undefined,
      }),
  });

  const {
    data: pendingCorrections = [],
    isLoading: correctionsLoading,
  } = useQuery({
    queryKey: ["owner-attendance-corrections", "pending"],
    queryFn: () => getOwnerAttendanceCorrections("pending"),
  });

  const invalidateAttendance = async () => {
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: ["owner-attendance-corrections"] }),
      queryClient.invalidateQueries({ queryKey: ["owner-attendance-report"] }),
      queryClient.invalidateQueries({ queryKey: ["owner-payroll-report"] }),
    ]);
  };

  const approveMutation = useMutation({
    mutationFn: (requestId: string) =>
      approveOwnerAttendanceCorrection(requestId),
    onSuccess: () => {
      toast.success("Correction approved. Attendance updated.");
      void invalidateAttendance();
    },
    onError: () => toast.error("Could not approve this correction."),
  });

  const rejectMutation = useMutation({
    mutationFn: ({
      requestId,
      note,
    }: {
      requestId: string;
      note: string;
    }) => rejectOwnerAttendanceCorrection(requestId, note),
    onSuccess: () => {
      toast.success("Correction rejected.");
      setRejectingId(null);
      setRejectNote("");
      void invalidateAttendance();
    },
    onError: () => toast.error("Could not reject this correction."),
  });

  const records = data?.records ?? [];
  const restDayWork =
    data?.rest_day_work ??
    records.filter((record) => record.is_rest_day && record.time_in);

  const summary = useMemo(() => {
    return records.reduce(
      (acc, record) => {
        if (record.status === "absent") acc.absent += 1;
        else if (record.status === "late") acc.late += 1;
        else acc.present += 1;
        if (record.is_rest_day && record.time_in) acc.restDay += 1;
        return acc;
      },
      { present: 0, late: 0, absent: 0, restDay: 0 }
    );
  }, [records]);

  const maxCount = Math.max(summary.present, summary.late, summary.absent, 1);
  const total = summary.present + summary.late + summary.absent;
  const presentPercent =
    total > 0 ? Math.round((summary.present / total) * 100) : 0;
  const restDayLabel = "Rest day";
  const hasActiveFilters = Boolean(date || debouncedSearch);

  return (
    <OwnerPage>
      <OwnerPageHeader title="Attendance" />

      <OwnerPageContent>
        <section className="rounded-2xl border border-amber-200 bg-amber-50/40 p-5 shadow-sm">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h2 className="text-base font-semibold text-[#1F2937]">
                Pending correction requests
              </h2>
              <p className="mt-1 text-sm text-[#6B7280]">
                Employees who forgot to clock in or out can request the actual
                time. Approve to update attendance and payroll.
              </p>
            </div>
            <span className="rounded-full bg-amber-100 px-3 py-1 text-xs font-semibold text-amber-800">
              {pendingCorrections.length} pending
            </span>
          </div>

          {correctionsLoading ? (
            <p className="mt-4 text-sm text-[#6B7280]">Loading requests…</p>
          ) : pendingCorrections.length === 0 ? (
            <p className="mt-4 text-sm text-[#6B7280]">
              No pending correction requests right now.
            </p>
          ) : (
            <div className="mt-4 grid gap-3">
              {pendingCorrections.map((item) => (
                <CorrectionCard
                  key={item.id}
                  item={item}
                  approving={
                    approveMutation.isPending &&
                    approveMutation.variables === item.id
                  }
                  rejecting={
                    rejectMutation.isPending &&
                    rejectMutation.variables?.requestId === item.id
                  }
                  isRejectOpen={rejectingId === item.id}
                  rejectNote={rejectingId === item.id ? rejectNote : ""}
                  onApprove={() => approveMutation.mutate(item.id)}
                  onOpenReject={() => {
                    setRejectingId(item.id);
                    setRejectNote("");
                  }}
                  onCancelReject={() => {
                    setRejectingId(null);
                    setRejectNote("");
                  }}
                  onRejectNoteChange={setRejectNote}
                  onConfirmReject={() => {
                    if (rejectNote.trim().length < 3) {
                      toast.error("Add a short rejection reason.");
                      return;
                    }
                    rejectMutation.mutate({
                      requestId: item.id,
                      note: rejectNote.trim(),
                    });
                  }}
                />
              ))}
            </div>
          )}
        </section>

        <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
          <div className="mx-auto max-w-3xl space-y-3">
            <div className="relative">
              <Search className="pointer-events-none absolute left-4 top-3 h-5 w-5 text-[#6B7280]" />
              <Input
                className="h-11 rounded-xl bg-[#FAFBFC] pl-12"
                placeholder="Search by name, position, or shift"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
              />
            </div>
            <div className="flex flex-wrap items-center gap-3">
              <label className="flex min-w-[200px] flex-1 flex-col gap-1 text-xs font-medium text-[#6B7280]">
                Date
                <Input
                  type="date"
                  className="h-10 rounded-xl bg-[#FAFBFC]"
                  value={date}
                  onChange={(e) => setDate(e.target.value)}
                />
              </label>
              <div className="flex items-end gap-2 pb-0.5">
                <button
                  type="button"
                  className="h-10 rounded-xl border border-slate-200 bg-white px-4 text-sm font-medium text-[#374151] hover:bg-slate-50"
                  onClick={() => setDate(todayIso())}
                >
                  Today
                </button>
                <button
                  type="button"
                  className="h-10 rounded-xl border border-slate-200 bg-white px-4 text-sm font-medium text-[#374151] hover:bg-slate-50"
                  onClick={() => {
                    setDate("");
                    setSearch("");
                    setDebouncedSearch("");
                  }}
                >
                  Clear
                </button>
              </div>
            </div>
            {hasActiveFilters && (
              <p className="text-xs text-[#6B7280]">
                Showing{date ? ` ${formatDisplayDate(date)}` : " all dates"}
                {debouncedSearch ? ` · matching “${debouncedSearch}”` : ""}
                {isFetching ? " · updating…" : ""}
              </p>
            )}
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
                <div
                  className="flex flex-1 flex-col items-center gap-2"
                  key={item.label}
                >
                  <div
                    className="w-full max-w-16 rounded-t-lg"
                    style={{
                      height: `${Math.max(
                        (item.value / maxCount) * 100,
                        item.value ? 14 : 0
                      )}%`,
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
              {restDayWork.length} record
              {restDayWork.length === 1 ? "" : "s"}
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
                        {formatDisplayDate(record.date)}
                        {record.weekday
                          ? ` · ${formatWeekday(record.weekday)}`
                          : ""}
                        {record.shift_name ? ` · ${record.shift_name}` : ""}
                      </p>
                      <p className="text-xs text-[#6B7280]">
                        In {formatTime(record.time_in)} · Out{" "}
                        {formatTime(record.time_out)}
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
          ) : isError ? (
            <div className="rounded-2xl border border-slate-200 bg-white p-6 text-sm text-[#6B7280] shadow-sm">
              <p>
                Couldn’t load attendance. Check your connection and try again.
              </p>
              <button
                type="button"
                className="mt-3 rounded-lg bg-slate-900 px-3 py-1.5 text-xs font-semibold text-white"
                onClick={() => void refetch()}
              >
                Retry
              </button>
            </div>
          ) : records.length === 0 ? (
            <div className="rounded-2xl border border-slate-200 bg-white p-6 text-sm text-[#6B7280] shadow-sm">
              No attendance records found
              {date ? ` for ${formatDisplayDate(date)}` : ""}
              {debouncedSearch ? ` matching “${debouncedSearch}”` : ""}.
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
                        {formatDisplayDate(record.date)}
                        {record.weekday
                          ? ` · ${formatWeekday(record.weekday)}`
                          : ""}
                        {record.shift_name
                          ? ` · ${record.shift_name}`
                          : record.position_title
                            ? ` · ${record.position_title}`
                            : ""}
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

function CorrectionCard({
  item,
  approving,
  rejecting,
  isRejectOpen,
  rejectNote,
  onApprove,
  onOpenReject,
  onCancelReject,
  onRejectNoteChange,
  onConfirmReject,
}: {
  item: OwnerAttendanceCorrection;
  approving: boolean;
  rejecting: boolean;
  isRejectOpen: boolean;
  rejectNote: string;
  onApprove: () => void;
  onOpenReject: () => void;
  onCancelReject: () => void;
  onRejectNoteChange: (value: string) => void;
  onConfirmReject: () => void;
}) {
  return (
    <div className="rounded-xl border border-amber-200 bg-white p-4">
      <div className="flex flex-wrap items-start gap-3">
        <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-amber-100 text-sm font-semibold text-amber-800">
          {initials(item.employee_name)}
        </div>
        <div className="min-w-0 flex-1">
          <h3 className="truncate text-sm font-semibold text-[#111827]">
            {item.employee_name}
          </h3>
          <p className="mt-0.5 text-xs text-[#6B7280]">
            {formatDisplayDate(item.work_date)}
            {item.shift_name ? ` · ${item.shift_name}` : ""}
            {item.shift_start && item.shift_end
              ? ` · ${item.shift_start} - ${item.shift_end}`
              : ""}
          </p>
          <div className="mt-2 grid gap-1 text-xs text-[#374151] sm:grid-cols-2">
            <p>
              Recorded: In {formatTime(item.recorded_time_in)} · Out{" "}
              {formatTime(item.recorded_time_out)}
            </p>
            <p>
              Requested: In {formatTime(item.requested_time_in)} · Out{" "}
              {formatTime(item.requested_time_out)}
            </p>
          </div>
          <p className="mt-2 text-sm text-[#4B5563]">
            <span className="font-medium text-[#111827]">Reason: </span>
            {item.reason}
          </p>
        </div>
      </div>

      {isRejectOpen ? (
        <div className="mt-3 space-y-2">
          <Input
            className="h-10 rounded-xl bg-[#FAFBFC]"
            placeholder="Rejection reason (required)"
            value={rejectNote}
            onChange={(e) => onRejectNoteChange(e.target.value)}
          />
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              className="rounded-lg bg-red-600 px-3 py-1.5 text-xs font-semibold text-white disabled:opacity-60"
              disabled={rejecting}
              onClick={onConfirmReject}
            >
              {rejecting ? "Rejecting…" : "Confirm reject"}
            </button>
            <button
              type="button"
              className="rounded-lg border border-slate-200 bg-white px-3 py-1.5 text-xs font-semibold text-[#374151]"
              onClick={onCancelReject}
            >
              Cancel
            </button>
          </div>
        </div>
      ) : (
        <div className="mt-3 flex flex-wrap gap-2">
          <button
            type="button"
            className="rounded-lg bg-emerald-600 px-3 py-1.5 text-xs font-semibold text-white disabled:opacity-60"
            disabled={approving || rejecting}
            onClick={onApprove}
          >
            {approving ? "Approving…" : "Approve"}
          </button>
          <button
            type="button"
            className="rounded-lg border border-slate-200 bg-white px-3 py-1.5 text-xs font-semibold text-[#374151]"
            disabled={approving || rejecting}
            onClick={onOpenReject}
          >
            Reject
          </button>
        </div>
      )}
    </div>
  );
}
