import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Search } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import {
  OwnerPage,
  OwnerPageContent,
  OwnerPageHeader,
} from "@/components/owner/layout/OwnerPageLayout";
import { SimulatedBadge } from "@/components/tenant/SimulatedBadge";
import { useTenantMode } from "@/lib/tenantMode";
import {
  approveOwnerAttendanceCorrection,
  completeOwnerAttendance,
  getOwnerAttendanceCorrections,
  getOwnerAttendanceReport,
  rejectOwnerAttendanceCorrection,
  type OwnerAttendanceCorrection,
  type OwnerAttendanceReport,
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

function EmployeeAvatar({
  name,
  imageUrl,
  className = "h-14 w-14 text-sm",
  fallbackClassName = "bg-slate-100 text-[#374151]",
}: {
  name: string;
  imageUrl?: string | null;
  className?: string;
  fallbackClassName?: string;
}) {
  return (
    <div
      className={`flex shrink-0 items-center justify-center overflow-hidden rounded-full text-sm font-semibold ${className} ${
        imageUrl ? "bg-slate-100" : fallbackClassName
      }`}
    >
      {imageUrl ? (
        <img
          alt={name}
          className="h-full w-full object-cover"
          src={imageUrl}
        />
      ) : (
        initials(name)
      )}
    </div>
  );
}

function statusCopy(status: string) {
  if (status === "late") return "Arrived late";
  if (status === "absent") return "Marked absent";
  if (status === "in_progress") return "Timed in";
  if (status === "complete") return "Arrived on time";
  if (status === "on_leave") return "On Leave";
  if (status === "holiday_paid") return "Paid holiday (not worked)";
  if (status === "incomplete") {
    return "Incomplete Attendance · Waiting for Attendance Correction";
  }
  return status.replace("_", " ");
}

type AttendanceRecord = OwnerAttendanceReport["records"][number];

function employmentLabel(value?: string | null) {
  if (value === "full_time") return "Full Timer";
  if (value === "part_time") return "Part Timer";
  if (!value) return "Not set";
  return value
    .replaceAll("_", " ")
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

function rateLabel(value?: number | null) {
  if (value == null || Number.isNaN(Number(value))) return "Not set";
  const amount = Number(value);
  const formatted = new Intl.NumberFormat("en-PH", {
    style: "currency",
    currency: "PHP",
    minimumFractionDigits: Number.isInteger(amount) ? 0 : 2,
    maximumFractionDigits: 2,
  }).format(amount);
  return `${formatted}/day`;
}

function EmployeeInfoRow({
  label,
  value,
}: {
  label: string;
  value: string;
}) {
  return (
    <div className="flex items-start justify-between gap-3 py-2.5">
      <p className="text-[12.5px] font-semibold text-[#6B7280]">{label}</p>
      <p className="max-w-[60%] text-right text-[13.5px] font-semibold text-[#111827]">
        {value}
      </p>
    </div>
  );
}

export function OwnerAttendancePage() {
  const queryClient = useQueryClient();
  const { isDemo } = useTenantMode();
  const [search, setSearch] = useState("");
  const [date, setDate] = useState(todayIso);
  const [debouncedSearch, setDebouncedSearch] = useState("");
  const [rejectingId, setRejectingId] = useState<string | null>(null);
  const [rejectNote, setRejectNote] = useState("");
  const [detailsEmployee, setDetailsEmployee] =
    useState<AttendanceRecord | null>(null);
  const [completing, setCompleting] = useState<AttendanceRecord | null>(null);
  const [completeTime, setCompleteTime] = useState("");
  const [completeReason, setCompleteReason] = useState("");

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
      queryClient.invalidateQueries({ queryKey: ["owner-performance"] }),
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

  const completeMutation = useMutation({
    mutationFn: () => {
      if (!completing || !completeTime) {
        return Promise.reject(new Error("Time Out is required."));
      }
      const timeOut = new Date(`${completing.date}T${completeTime}:00`);
      if (Number.isNaN(timeOut.getTime())) {
        return Promise.reject(new Error("Enter a valid Time Out."));
      }
      return completeOwnerAttendance(completing.id, {
        time_out: timeOut.toISOString(),
        reason: completeReason.trim() || undefined,
      });
    },
    onSuccess: () => {
      toast.success("Attendance completed. Payroll will update automatically.");
      setCompleting(null);
      setCompleteTime("");
      setCompleteReason("");
      void invalidateAttendance();
    },
    onError: (error: unknown) => {
      const detail =
        typeof error === "object" &&
        error !== null &&
        "response" in error &&
        typeof (error as { response?: { data?: { detail?: unknown } } }).response
          ?.data?.detail === "string"
          ? String(
              (error as { response?: { data?: { detail?: string } } }).response
                ?.data?.detail
            )
          : "Could not complete attendance.";
      toast.error(detail);
    },
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
        else if (
          record.status === "complete" ||
          record.status === "in_progress"
        ) {
          acc.present += 1;
        }
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
  const chartHeight = 160;
  const maxBarHeight = 120;
  const restDayLabel = "Rest day";
  const hasActiveFilters = Boolean(date || debouncedSearch);

  return (
    <OwnerPage>
      <OwnerPageHeader
        title="Attendance"
        description={
          isDemo
            ? "Simulated Time In / Time Out records for demonstration only."
            : undefined
        }
      />

      <OwnerPageContent>
        <section className="rounded-2xl border border-amber-200 bg-amber-50/40 p-5 shadow-sm">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h2 className="text-base font-semibold text-[#1F2937]">
                Pending correction requests
              </h2>
              <p className="mt-1 text-sm text-[#6B7280]">
                Employees can request corrected Time In and Time Out for
                a shift. Approve to update attendance and payroll.
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
            <div
              className="flex items-end gap-12 border-b border-l border-slate-200 px-8"
              style={{ height: `${chartHeight}px` }}
            >
              {[
                { label: "on time", value: summary.present, color: "#BEF7A5" },
                { label: "late", value: summary.late, color: "#FDBA74" },
                { label: "absent", value: summary.absent, color: "#F87171" },
              ].map((item) => {
                const barHeight =
                  item.value > 0
                    ? Math.max(
                        14,
                        Math.round((item.value / maxCount) * maxBarHeight)
                      )
                    : 0;
                return (
                  <div
                    className="flex flex-1 flex-col items-center justify-end"
                    key={item.label}
                  >
                    <span className="mb-1 text-xs font-semibold text-[#374151]">
                      {item.value}
                    </span>
                    <div
                      className="w-full max-w-16 rounded-t-lg"
                      style={{
                        height: `${barHeight}px`,
                        backgroundColor: item.color,
                      }}
                    />
                    <span className="mt-2 text-xs text-[#6B7280]">
                      {item.label}
                    </span>
                  </div>
                );
              })}
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
                Employees who timed in or out on {restDayLabel}
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
                  <button
                    type="button"
                    className={`flex w-full items-center gap-4 rounded-xl border p-4 text-left transition hover:shadow-sm ${
                      unauthorized
                        ? "border-amber-200 bg-amber-50/70 hover:border-amber-300"
                        : "border-sky-100 bg-sky-50/60 hover:border-sky-200"
                    }`}
                    key={`rest-${record.id}`}
                    onClick={() => setDetailsEmployee(record)}
                  >
                    <EmployeeAvatar
                      name={record.employee_name}
                      imageUrl={record.profile_image_url}
                      className="h-12 w-12 text-sm"
                      fallbackClassName={
                        unauthorized
                          ? "bg-amber-100 text-amber-800"
                          : "bg-sky-100 text-sky-800"
                      }
                    />
                    <div className="min-w-0 flex-1">
                      <h3 className="truncate text-sm font-semibold text-[#111827]">
                        {record.employee_name}
                      </h3>
                      {isDemo ? (
                        <p className="mt-1">
                          <SimulatedBadge label="SIMULATED" />
                        </p>
                      ) : null}
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
                  </button>
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
                const incomplete = record.status === "incomplete";
                const onLeave = record.status === "on_leave";
                const holidayPaid = record.status === "holiday_paid";
                const restDay = Boolean(record.is_rest_day && record.time_in);
                return (
                  <div
                    className="flex cursor-pointer items-center gap-4 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm transition hover:border-[#C5D4E3] hover:shadow-md"
                    key={record.id}
                    onClick={() => setDetailsEmployee(record)}
                    onKeyDown={(event) => {
                      if (event.key === "Enter" || event.key === " ") {
                        event.preventDefault();
                        setDetailsEmployee(record);
                      }
                    }}
                    role="button"
                    tabIndex={0}
                  >
                    <EmployeeAvatar
                      name={record.employee_name}
                      imageUrl={record.profile_image_url}
                    />
                    <div className="min-w-0 flex-1">
                      <h2 className="truncate text-sm font-semibold text-[#111827]">
                        {record.employee_name}
                      </h2>
                      {isDemo ? (
                        <p className="mt-1">
                          <SimulatedBadge label="SIMULATED" />
                        </p>
                      ) : null}
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
                      <p
                        className={`text-xs ${
                          incomplete
                            ? "font-semibold text-amber-700"
                            : onLeave || holidayPaid
                              ? "font-semibold text-sky-700"
                              : "text-[#6B7280]"
                        }`}
                      >
                        {statusCopy(record.status)}
                        {restDay ? " · Rest day" : ""}
                      </p>
                      {incomplete ? (
                        <Button
                          className="mt-2 h-8 px-3 text-xs"
                          onClick={(event) => {
                            event.stopPropagation();
                            setCompleting(record);
                            setCompleteTime("");
                            setCompleteReason("");
                          }}
                          size="sm"
                          type="button"
                          variant="outline"
                        >
                          Complete Attendance
                        </Button>
                      ) : null}
                    </div>
                    <span
                      className={`rounded-full px-3 py-1 text-xs font-semibold ${
                        incomplete
                          ? "bg-amber-100 text-amber-800"
                          : absent
                            ? "bg-red-100 text-red-700"
                            : holidayPaid || onLeave
                              ? "bg-sky-100 text-sky-800"
                              : restDay
                                ? "bg-sky-100 text-sky-800"
                                : late
                                  ? "bg-orange-100 text-orange-700"
                                  : "bg-green-100 text-green-700"
                      }`}
                    >
                      {incomplete
                        ? "Incomplete"
                        : absent
                          ? "Absent"
                          : holidayPaid
                            ? "Holiday"
                            : onLeave
                              ? "Leave"
                              : formatTime(record.time_in)}
                    </span>
                  </div>
                );
              })}
            </div>
          )}
        </section>
      </OwnerPageContent>

      <Dialog
        open={Boolean(detailsEmployee)}
        onOpenChange={(open) => {
          if (!open) setDetailsEmployee(null);
        }}
      >
        <DialogContent className="max-w-md gap-0 overflow-hidden border-slate-200 p-0 sm:rounded-2xl">
          <div className="border-b border-[#E8EEF4] px-5 py-4">
            <DialogHeader>
              <DialogTitle className="text-[15px] font-extrabold text-[#111827]">
                Employee Details
              </DialogTitle>
            </DialogHeader>
            <p className="mt-1 text-xs text-[#6B7280]">
              Information from your employee records.
            </p>
          </div>
          {detailsEmployee ? (
            <div className="px-5 py-3">
              <div className="mb-3 flex items-center gap-3">
                <EmployeeAvatar
                  name={detailsEmployee.employee_name}
                  imageUrl={detailsEmployee.profile_image_url}
                  className="h-14 w-14 text-sm"
                />
                <div className="min-w-0">
                  <p className="truncate text-sm font-extrabold text-[#111827]">
                    Employee Information
                  </p>
                  <p className="text-[11.5px] text-[#6B7280]">
                    Stored employee profile details
                  </p>
                </div>
              </div>
              <div className="divide-y divide-[#E8EEF4]">
                <EmployeeInfoRow
                  label="Complete Name"
                  value={detailsEmployee.employee_name || "Not set"}
                />
                <EmployeeInfoRow
                  label="Role"
                  value={detailsEmployee.position_title || "Not set"}
                />
                <EmployeeInfoRow
                  label="Employment"
                  value={employmentLabel(detailsEmployee.employment_type)}
                />
                <EmployeeInfoRow
                  label="Rate"
                  value={rateLabel(detailsEmployee.daily_rate)}
                />
                <EmployeeInfoRow
                  label="Time In"
                  value={formatTime(detailsEmployee.time_in)}
                />
                <EmployeeInfoRow
                  label="Time Out"
                  value={formatTime(detailsEmployee.time_out)}
                />
              </div>
            </div>
          ) : null}
          <DialogFooter className="border-t border-[#E8EEF4] px-5 py-3">
            <Button
              onClick={() => setDetailsEmployee(null)}
              type="button"
              variant="outline"
            >
              Close
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog
        open={Boolean(completing)}
        onOpenChange={(open) => {
          if (!open) {
            setCompleting(null);
            setCompleteTime("");
            setCompleteReason("");
          }
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Complete Attendance</DialogTitle>
          </DialogHeader>
          {completing ? (
            <div className="space-y-3">
              <p className="text-sm text-[#6B7280]">
                Enter the correct Time Out for{" "}
                <span className="font-semibold text-[#111827]">
                  {completing.employee_name}
                </span>{" "}
                on {formatDisplayDate(completing.date)}. Time In was{" "}
                {formatTime(completing.time_in)}.
              </p>
              <div>
                <label className="mb-1 block text-xs font-semibold text-[#374151]">
                  Time Out
                </label>
                <Input
                  onChange={(event) => setCompleteTime(event.target.value)}
                  type="time"
                  value={completeTime}
                />
              </div>
              <div>
                <label className="mb-1 block text-xs font-semibold text-[#374151]">
                  Reason (optional)
                </label>
                <Input
                  onChange={(event) => setCompleteReason(event.target.value)}
                  placeholder="Employee forgot to time out"
                  value={completeReason}
                />
              </div>
            </div>
          ) : null}
          <DialogFooter>
            <Button
              onClick={() => {
                setCompleting(null);
                setCompleteTime("");
                setCompleteReason("");
              }}
              type="button"
              variant="outline"
            >
              Cancel
            </Button>
            <Button
              disabled={!completeTime || completeMutation.isPending}
              onClick={() => completeMutation.mutate()}
              type="button"
            >
              {completeMutation.isPending ? "Saving…" : "Save Time Out"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
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
        <EmployeeAvatar
          name={item.employee_name}
          imageUrl={item.profile_image_url}
          className="h-12 w-12 text-sm"
          fallbackClassName="bg-amber-100 text-amber-800"
        />
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
