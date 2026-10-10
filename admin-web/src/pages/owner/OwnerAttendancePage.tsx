import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Check, Clock3, History, Search, X } from "lucide-react";
import { useEffect, useMemo, useState, type ReactNode } from "react";
import { Link } from "react-router-dom";
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
  approveOvertime,
  completeOwnerAttendance,
  getOwnerAttendanceCorrections,
  getOwnerAttendanceReport,
  listOvertimeApprovals,
  rejectOwnerAttendanceCorrection,
  rejectOvertime,
  type OwnerAttendanceCorrection,
  type OwnerAttendanceReport,
} from "@/lib/api";
import { formatAttendanceTime } from "@/lib/attendanceTime";

function todayIso() {
  const now = new Date();
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, "0");
  const d = String(now.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

function formatTime(value: string | null, timeZone?: string | null) {
  return formatAttendanceTime(value, timeZone);
}

function formatWeekday(value?: string) {
  if (!value) return "";
  return value.charAt(0).toUpperCase() + value.slice(1);
}

/** FastAPI string detail or `{ message }` object (e.g. payroll_finalized 409). */
function apiDetailMessage(error: unknown, fallback: string): string {
  if (
    typeof error !== "object" ||
    error === null ||
    !("response" in error)
  ) {
    return fallback;
  }
  const detail = (
    error as { response?: { data?: { detail?: { message?: string } | string } } }
  ).response?.data?.detail;
  if (typeof detail === "string" && detail.trim()) return detail;
  if (
    typeof detail === "object" &&
    detail !== null &&
    typeof detail.message === "string" &&
    detail.message.trim()
  ) {
    return detail.message;
  }
  return fallback;
}

function formatOtDuration(minutes: number | undefined) {
  if (typeof minutes !== "number" || !Number.isFinite(minutes)) return null;
  const total = Math.max(0, Math.round(minutes));
  const hours = Math.floor(total / 60);
  const mins = total % 60;
  if (hours > 0 && mins > 0) return `${hours}h ${mins}m`;
  if (hours > 0) return `${hours}h`;
  return `${mins}m`;
}

function formatSubmittedAt(value: string | null | undefined) {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
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
  const { isDemo, me } = useTenantMode();
  const [search, setSearch] = useState("");
  const [date, setDate] = useState(todayIso);
  const [debouncedSearch, setDebouncedSearch] = useState("");
  const [rejectingId, setRejectingId] = useState<string | null>(null);
  const [rejectNote, setRejectNote] = useState("");
  const [reviewCorrectionId, setReviewCorrectionId] = useState<string | null>(
    null
  );
  const [reviewOtId, setReviewOtId] = useState<string | null>(null);
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
  const attendanceTz = data?.timezone ?? me?.timezone;

  const {
    data: pendingCorrections = [],
    isLoading: correctionsLoading,
  } = useQuery({
    queryKey: ["owner-attendance-corrections", "pending"],
    queryFn: () => getOwnerAttendanceCorrections("pending"),
  });

  const {
    data: pendingOtData,
    isLoading: otLoading,
  } = useQuery({
    queryKey: ["owner-overtime-approvals", "pending"],
    queryFn: () => listOvertimeApprovals("pending"),
  });
  const pendingOt = pendingOtData?.items ?? [];
  const reviewCorrection =
    pendingCorrections.find((item) => item.id === reviewCorrectionId) ?? null;
  const reviewOt =
    pendingOt.find((item) => item.attendance_record_id === reviewOtId) ??
    null;

  const invalidateAttendance = async () => {
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: ["owner-attendance-corrections"] }),
      queryClient.invalidateQueries({ queryKey: ["owner-overtime-approvals"] }),
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
    onError: (error: unknown) =>
      toast.error(apiDetailMessage(error, "Could not approve this correction.")),
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

  const approveOtMutation = useMutation({
    mutationFn: (recordId: string) => approveOvertime(recordId),
    onSuccess: () => {
      toast.success("Overtime approved. It will be included as payable OT.");
      void invalidateAttendance();
    },
    onError: (error: unknown) => {
      const detail =
        typeof error === "object" &&
        error !== null &&
        "response" in error &&
        typeof (error as { response?: { data?: { detail?: { message?: string } | string } } })
          .response?.data?.detail === "object"
          ? String(
              (
                error as {
                  response?: { data?: { detail?: { message?: string } } };
                }
              ).response?.data?.detail?.message ?? "Could not approve overtime."
            )
          : typeof error === "object" &&
              error !== null &&
              "response" in error &&
              typeof (error as { response?: { data?: { detail?: string } } })
                .response?.data?.detail === "string"
            ? String(
                (error as { response?: { data?: { detail?: string } } }).response
                  ?.data?.detail
              )
            : "Could not approve overtime.";
      toast.error(detail);
    },
  });

  const rejectOtMutation = useMutation({
    mutationFn: (recordId: string) => rejectOvertime(recordId),
    onSuccess: () => {
      toast.success("Overtime rejected. Worked time is kept; OT is not paid.");
      void invalidateAttendance();
    },
    onError: (error: unknown) => {
      const detail =
        typeof error === "object" &&
        error !== null &&
        "response" in error &&
        typeof (error as { response?: { data?: { detail?: { message?: string } | string } } })
          .response?.data?.detail === "object"
          ? String(
              (
                error as {
                  response?: { data?: { detail?: { message?: string } } };
                }
              ).response?.data?.detail?.message ?? "Could not reject overtime."
            )
          : "Could not reject overtime.";
      toast.error(detail);
    },
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
      toast.error(apiDetailMessage(error, "Could not complete attendance."));
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
            : "Review Time In and Time Out records for your team."
        }
        actions={
          <Button asChild variant="outline" className="h-10 rounded-xl bg-white">
            <Link to="/owner/attendance/shift-history">
              <History className="mr-2 h-4 w-4" />
              Shift History
            </Link>
          </Button>
        }
      />

      <OwnerPageContent>
        <section className="owner-panel">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div className="min-w-0">
              <h2 className="owner-section-title">
                Pending correction requests
              </h2>
              <p className="mt-1 max-w-2xl text-sm text-[#6B7280]">
                Employees can request corrected Time In and Time Out for
                a shift. Approve to update attendance and payroll.
              </p>
            </div>
            <span className="rounded-full bg-[var(--owner-well)] px-2.5 py-1 text-xs font-medium text-[var(--owner-navy)]">
              {pendingCorrections.length} to review
            </span>
          </div>

          {correctionsLoading ? (
            <p className="mt-4 text-sm text-[#6B7280]">Loading requests…</p>
          ) : pendingCorrections.length === 0 ? (
            <ReviewEmptyState
              title="No pending correction requests"
              detail="New Time In and Time Out requests will appear here."
            />
          ) : (
            <div className="mt-4 divide-y divide-slate-100 overflow-hidden rounded-xl border border-slate-200">
              {pendingCorrections.map((item) => (
                <CorrectionCard
                  key={item.id}
                  item={item}
                  timeZone={attendanceTz}
                  approving={
                    approveMutation.isPending &&
                    approveMutation.variables === item.id
                  }
                  rejecting={
                    rejectMutation.isPending &&
                    rejectMutation.variables?.requestId === item.id
                  }
                  onOpen={() => setReviewCorrectionId(item.id)}
                  onApprove={() => approveMutation.mutate(item.id)}
                  onReject={() => {
                    setReviewCorrectionId(item.id);
                    setRejectingId(item.id);
                    setRejectNote("");
                  }}
                />
              ))}
            </div>
          )}
        </section>

        <section className="owner-panel">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div className="min-w-0">
              <h2 className="owner-section-title">
                Pending overtime approvals
              </h2>
              <p className="mt-1 max-w-2xl text-sm text-[#6B7280]">
                When OT Approval Required is on, qualifying overtime must be
                approved before it is paid. Rejecting OT keeps the recorded Time
                In / Time Out and only withholds OT pay.
              </p>
            </div>
            <span className="rounded-full bg-[var(--owner-well)] px-2.5 py-1 text-xs font-medium text-[var(--owner-navy)]">
              {pendingOt.length} to review
            </span>
          </div>

          {otLoading ? (
            <p className="mt-4 text-sm text-[#6B7280]">Loading overtime…</p>
          ) : pendingOt.length === 0 ? (
            <ReviewEmptyState
              title="No pending OT approvals"
              detail="Qualifying overtime will show up here for review."
            />
          ) : (
            <div className="mt-4 divide-y divide-slate-100 overflow-hidden rounded-xl border border-slate-200">
              {pendingOt.map((item) => {
                const duration = formatOtDuration(item.worked_ot_minutes);
                const busy =
                  approveOtMutation.isPending || rejectOtMutation.isPending;
                const approving =
                  approveOtMutation.isPending &&
                  approveOtMutation.variables === item.attendance_record_id;
                const rejecting =
                  rejectOtMutation.isPending &&
                  rejectOtMutation.variables === item.attendance_record_id;
                return (
                  <div
                    key={item.attendance_record_id}
                    className="flex flex-col gap-3 bg-white px-3 py-3 md:flex-row md:items-center md:px-4"
                  >
                    <button
                      type="button"
                      className="flex min-w-0 flex-1 items-start gap-3 rounded-lg text-left transition hover:bg-slate-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--owner-accent)]"
                      onClick={() =>
                        setReviewOtId(item.attendance_record_id)
                      }
                    >
                      <EmployeeAvatar
                        name={item.employee_name}
                        className="h-9 w-9 text-xs"
                        fallbackClassName="bg-[var(--owner-well)] text-[var(--owner-navy)]"
                      />
                      <span className="min-w-0">
                        <span className="block break-words text-sm font-semibold text-[#111827]">
                          {item.employee_name}
                        </span>
                        <span className="mt-0.5 block break-words text-xs text-[#6B7280]">
                          {item.work_date
                            ? formatDisplayDate(item.work_date)
                            : "Shift"}
                          {item.shift_name ? ` · ${item.shift_name}` : ""}
                        </span>
                      </span>
                    </button>
                    <div className="flex flex-wrap items-center gap-2 md:justify-end">
                      {duration ? (
                        <span className="rounded-md bg-[var(--owner-well)] px-2 py-1 text-xs font-semibold text-[var(--owner-navy)]">
                          {duration}
                        </span>
                      ) : null}
                      <span className="rounded-full bg-slate-100 px-2 py-0.5 text-[11px] font-medium text-[#4B5563]">
                        Pending
                      </span>
                      <ReviewDecisionButtons
                        approveLabel={approving ? "Approving…" : "Approve"}
                        rejectLabel={rejecting ? "Rejecting…" : "Reject"}
                        disabled={busy}
                        onApprove={() =>
                          approveOtMutation.mutate(item.attendance_record_id)
                        }
                        onReject={() =>
                          rejectOtMutation.mutate(item.attendance_record_id)
                        }
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </section>

        <section className="owner-toolbar">
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
          <div className="owner-panel">
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

          <div className="owner-panel flex items-center justify-center">
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

        <section className="owner-panel">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h2 className="owner-section-title">
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
                        In {formatTime(record.time_in, attendanceTz)} · Out{" "}
                        {formatTime(record.time_out, attendanceTz)}
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
            <div className="owner-panel px-6 py-10 text-center text-sm text-[#6B7280]">
              Loading attendance...
            </div>
          ) : isError ? (
            <div className="owner-panel px-6 py-10 text-center text-sm text-[#6B7280]">
              <p>
                Couldn’t load attendance. Check your connection and try again.
              </p>
              <button
                type="button"
                className="mt-3 rounded-xl bg-slate-900 px-3 py-1.5 text-xs font-semibold text-white"
                onClick={() => void refetch()}
              >
                Retry
              </button>
            </div>
          ) : records.length === 0 ? (
            <div className="owner-empty">
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
                    className="owner-list-row flex cursor-pointer items-center gap-4"
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
                              : formatTime(record.time_in, attendanceTz)}
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
                  value={formatTime(detailsEmployee.time_in, attendanceTz)}
                />
                <EmployeeInfoRow
                  label="Time Out"
                  value={formatTime(detailsEmployee.time_out, attendanceTz)}
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
                {formatTime(completing.time_in, attendanceTz)}.
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

      <CorrectionReviewDialog
        item={reviewCorrection}
        timeZone={attendanceTz}
        open={reviewCorrection != null}
        onOpenChange={(open) => {
          if (!open) {
            setReviewCorrectionId(null);
            setRejectingId(null);
            setRejectNote("");
          }
        }}
        approving={
          reviewCorrection != null &&
          approveMutation.isPending &&
          approveMutation.variables === reviewCorrection.id
        }
        rejecting={
          reviewCorrection != null &&
          rejectMutation.isPending &&
          rejectMutation.variables?.requestId === reviewCorrection.id
        }
        isRejectOpen={
          reviewCorrection != null && rejectingId === reviewCorrection.id
        }
        rejectNote={rejectNote}
        onApprove={() => {
          if (!reviewCorrection) return;
          approveMutation.mutate(reviewCorrection.id);
        }}
        onOpenReject={() => {
          if (!reviewCorrection) return;
          setRejectingId(reviewCorrection.id);
          setRejectNote("");
        }}
        onCancelReject={() => {
          setRejectingId(null);
          setRejectNote("");
        }}
        onRejectNoteChange={setRejectNote}
        onConfirmReject={() => {
          if (!reviewCorrection) return;
          if (rejectNote.trim().length < 3) {
            toast.error("Add a short rejection reason.");
            return;
          }
          rejectMutation.mutate({
            requestId: reviewCorrection.id,
            note: rejectNote.trim(),
          });
        }}
      />

      <OvertimeReviewDialog
        item={reviewOt}
        timeZone={attendanceTz}
        open={reviewOt != null}
        onOpenChange={(open) => {
          if (!open) setReviewOtId(null);
        }}
        approving={
          reviewOt != null &&
          approveOtMutation.isPending &&
          approveOtMutation.variables === reviewOt.attendance_record_id
        }
        rejecting={
          reviewOt != null &&
          rejectOtMutation.isPending &&
          rejectOtMutation.variables === reviewOt.attendance_record_id
        }
        disabled={approveOtMutation.isPending || rejectOtMutation.isPending}
        onApprove={() => {
          if (!reviewOt) return;
          approveOtMutation.mutate(reviewOt.attendance_record_id);
        }}
        onReject={() => {
          if (!reviewOt) return;
          rejectOtMutation.mutate(reviewOt.attendance_record_id);
        }}
      />
    </OwnerPage>
  );
}

const reviewApproveClass =
  "inline-flex h-8 items-center gap-1.5 rounded-lg border border-emerald-200 bg-emerald-50 px-2.5 text-xs font-medium text-emerald-800 transition hover:bg-emerald-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-700/30 active:bg-emerald-100 disabled:cursor-not-allowed disabled:opacity-50";

const reviewRejectClass =
  "inline-flex h-8 items-center gap-1.5 rounded-lg border border-rose-200 bg-rose-50 px-2.5 text-xs font-medium text-rose-800 transition hover:bg-rose-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-rose-700/30 active:bg-rose-100 disabled:cursor-not-allowed disabled:opacity-50";

function ReviewDecisionButtons({
  approveLabel,
  rejectLabel,
  disabled,
  onApprove,
  onReject,
}: {
  approveLabel: string;
  rejectLabel: string;
  disabled?: boolean;
  onApprove: () => void;
  onReject: () => void;
}) {
  return (
    <div className="flex flex-wrap gap-1.5">
      <button
        type="button"
        className={reviewRejectClass}
        disabled={disabled}
        onClick={onReject}
      >
        <X className="h-3.5 w-3.5" aria-hidden />
        {rejectLabel}
      </button>
      <button
        type="button"
        className={reviewApproveClass}
        disabled={disabled}
        onClick={onApprove}
      >
        <Check className="h-3.5 w-3.5" aria-hidden />
        {approveLabel}
      </button>
    </div>
  );
}

function ReviewEmptyState({
  title,
  detail,
}: {
  title: string;
  detail: string;
}) {
  return (
    <div className="mt-4 flex items-start gap-3 rounded-xl border border-dashed border-slate-200 px-4 py-4">
      <Clock3 className="mt-0.5 h-4 w-4 shrink-0 text-[#9CA3AF]" aria-hidden />
      <div className="min-w-0">
        <p className="text-sm font-medium text-[#1F2937]">{title}</p>
        <p className="mt-0.5 text-xs leading-5 text-[#6B7280]">{detail}</p>
      </div>
    </div>
  );
}

function ReviewField({
  label,
  children,
}: {
  label: string;
  children: ReactNode;
}) {
  return (
    <div className="min-w-0">
      <p className="text-[11px] font-medium uppercase tracking-[0.08em] text-[#9CA3AF]">
        {label}
      </p>
      <div className="mt-1 text-sm leading-6 text-[#1F2937]">{children}</div>
    </div>
  );
}

function CorrectionCard({
  item,
  timeZone,
  approving,
  rejecting,
  onOpen,
  onApprove,
  onReject,
}: {
  item: OwnerAttendanceCorrection;
  timeZone?: string | null;
  approving: boolean;
  rejecting: boolean;
  onOpen: () => void;
  onApprove: () => void;
  onReject: () => void;
}) {
  return (
    <div className="flex flex-col gap-3 bg-white px-3 py-3 md:flex-row md:items-center md:px-4">
      <button
        type="button"
        className="flex min-w-0 flex-1 items-start gap-3 rounded-lg text-left transition hover:bg-slate-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--owner-accent)]"
        onClick={onOpen}
      >
        <EmployeeAvatar
          name={item.employee_name}
          imageUrl={item.profile_image_url}
          className="h-9 w-9 text-xs"
          fallbackClassName="bg-[var(--owner-well)] text-[var(--owner-navy)]"
        />
        <span className="min-w-0">
          <span className="block break-words text-sm font-semibold text-[#111827]">
            {item.employee_name}
          </span>
          <span className="mt-0.5 block break-words text-xs text-[#6B7280]">
            {formatDisplayDate(item.work_date)}
            {item.shift_name ? ` · ${item.shift_name}` : ""}
          </span>
          <span className="mt-1 block truncate text-xs text-[#4B5563]">
            Requested {formatTime(item.requested_time_in, timeZone)} –{" "}
            {formatTime(item.requested_time_out, timeZone)}
          </span>
        </span>
      </button>
      <div className="flex flex-wrap items-center gap-2 md:justify-end">
        <span className="rounded-full bg-slate-100 px-2 py-0.5 text-[11px] font-medium capitalize text-[#4B5563]">
          {item.status.replace(/_/g, " ")}
        </span>
        <ReviewDecisionButtons
          approveLabel={approving ? "Approving…" : "Approve"}
          rejectLabel="Reject"
          disabled={approving || rejecting}
          onApprove={onApprove}
          onReject={onReject}
        />
      </div>
    </div>
  );
}

function CorrectionReviewDialog({
  item,
  timeZone,
  open,
  onOpenChange,
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
  item: OwnerAttendanceCorrection | null;
  timeZone?: string | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
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
  const submitted = item ? formatSubmittedAt(item.created_at) : null;
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        overlayClassName="bg-slate-900/20"
        className="max-h-[min(85vh,40rem)] w-[min(32rem,calc(100vw-2rem))] max-w-lg gap-0 overflow-y-auto rounded-2xl p-0"
      >
        <DialogHeader className="border-b border-slate-100 px-5 pb-4 pr-12 pt-5 text-left">
          <p className="text-[11px] font-medium uppercase tracking-[0.12em] text-[#9CA3AF]">
            Correction request
          </p>
          <DialogTitle className="text-lg font-semibold tracking-tight text-[#111827]">
            {item?.employee_name ?? "Request"}
          </DialogTitle>
          {item ? (
            <span className="mt-2 inline-flex w-fit rounded-full bg-slate-100 px-2 py-0.5 text-[11px] font-medium capitalize text-[#4B5563]">
              {item.status.replace(/_/g, " ")}
            </span>
          ) : null}
        </DialogHeader>
        {item ? (
          <div className="space-y-5 px-5 py-5">
            <ReviewField label="Employee">{item.employee_name}</ReviewField>
            <ReviewField label="Request">
              <p>{formatDisplayDate(item.work_date)}</p>
              <p className="text-[#4B5563]">
                {item.shift_name ?? "Shift"}
                {item.shift_start && item.shift_end
                  ? ` · ${item.shift_start} – ${item.shift_end}`
                  : ""}
              </p>
              <p className="mt-2 text-[#4B5563]">
                Recorded {formatTime(item.recorded_time_in, timeZone)} –{" "}
                {formatTime(item.recorded_time_out, timeZone)}
              </p>
              <p>
                Requested {formatTime(item.requested_time_in, timeZone)} –{" "}
                {formatTime(item.requested_time_out, timeZone)}
              </p>
            </ReviewField>
            <ReviewField label="Reason">
              <p className="whitespace-pre-wrap rounded-xl bg-[#F8FAFC] px-3 py-3 text-[#374151]">
                {item.reason}
              </p>
            </ReviewField>
            {submitted ? (
              <ReviewField label="Submitted">{submitted}</ReviewField>
            ) : null}
          </div>
        ) : null}
        <DialogFooter className="gap-2 border-t border-slate-100 px-5 py-4 sm:justify-end">
          {isRejectOpen ? (
            <div className="flex w-full flex-col gap-2">
              <Input
                className="h-10 rounded-xl bg-[#FAFBFC]"
                placeholder="Rejection reason (required)"
                value={rejectNote}
                onChange={(event) => onRejectNoteChange(event.target.value)}
              />
              <div className="flex flex-wrap justify-end gap-2">
                <button
                  type="button"
                  className="inline-flex h-8 items-center rounded-lg border border-slate-200 bg-white px-2.5 text-xs font-medium text-[#374151] hover:bg-slate-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400/40"
                  onClick={onCancelReject}
                >
                  Cancel
                </button>
                <button
                  type="button"
                  className={reviewRejectClass}
                  disabled={rejecting}
                  onClick={onConfirmReject}
                >
                  <X className="h-3.5 w-3.5" aria-hidden />
                  {rejecting ? "Rejecting…" : "Confirm reject"}
                </button>
              </div>
            </div>
          ) : (
            <ReviewDecisionButtons
              approveLabel={approving ? "Approving…" : "Approve"}
              rejectLabel="Reject"
              disabled={approving || rejecting}
              onApprove={onApprove}
              onReject={onOpenReject}
            />
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function OvertimeReviewDialog({
  item,
  timeZone,
  open,
  onOpenChange,
  approving,
  rejecting,
  disabled,
  onApprove,
  onReject,
}: {
  item: {
    attendance_record_id: string;
    employee_name: string;
    work_date: string | null;
    shift_name: string | null;
    time_in: string | null;
    time_out: string | null;
    worked_ot_minutes?: number;
    ot_approval_status: string | null;
  } | null;
  timeZone?: string | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  approving: boolean;
  rejecting: boolean;
  disabled: boolean;
  onApprove: () => void;
  onReject: () => void;
}) {
  const duration = formatOtDuration(item?.worked_ot_minutes);
  const status = item?.ot_approval_status?.replace(/_/g, " ") || "Pending";
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        overlayClassName="bg-slate-900/20"
        className="max-h-[min(85vh,40rem)] w-[min(32rem,calc(100vw-2rem))] max-w-lg gap-0 overflow-y-auto rounded-2xl p-0"
      >
        <DialogHeader className="border-b border-slate-100 px-5 pb-4 pr-12 pt-5 text-left">
          <p className="text-[11px] font-medium uppercase tracking-[0.12em] text-[#9CA3AF]">
            Overtime approval
          </p>
          <DialogTitle className="text-lg font-semibold tracking-tight text-[#111827]">
            {item?.employee_name ?? "Request"}
          </DialogTitle>
          <span className="mt-2 inline-flex w-fit rounded-full bg-slate-100 px-2 py-0.5 text-[11px] font-medium capitalize text-[#4B5563]">
            {status}
          </span>
        </DialogHeader>
        {item ? (
          <div className="space-y-5 px-5 py-5">
            <ReviewField label="Employee">{item.employee_name}</ReviewField>
            <ReviewField label="Request">
              <p>
                {item.work_date ? formatDisplayDate(item.work_date) : "Shift"}
                {item.shift_name ? ` · ${item.shift_name}` : ""}
              </p>
              <p className="text-[#4B5563]">
                In {formatTime(item.time_in, timeZone)} · Out{" "}
                {formatTime(item.time_out, timeZone)}
              </p>
              {duration ? (
                <p className="mt-2 font-medium text-[var(--owner-navy)]">
                  Worked OT {duration}
                </p>
              ) : null}
            </ReviewField>
          </div>
        ) : null}
        <DialogFooter className="border-t border-slate-100 px-5 py-4 sm:justify-end">
          <ReviewDecisionButtons
            approveLabel={approving ? "Approving…" : "Approve"}
            rejectLabel={rejecting ? "Rejecting…" : "Reject"}
            disabled={disabled}
            onApprove={onApprove}
            onReject={onReject}
          />
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
