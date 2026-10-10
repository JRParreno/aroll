import { useMutation, useQuery, useQueryClient, useQueries } from "@tanstack/react-query";
import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { useParams } from "react-router-dom";
import { ChevronDown, X } from "lucide-react";
import { toast } from "sonner";
import {
  OwnerPage,
  OwnerPageContent,
  OwnerPageHeader,
} from "@/components/owner/layout/OwnerPageLayout";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import {
  approveOwnerLeaveCancellation,
  approveOwnerLeaveRequest,
  getOwnerLeaveRequest,
  getEmployeeLeaveBalances,
  listEmployees,
  listOwnerLeaveRequests,
  rejectOwnerLeaveCancellation,
  rejectOwnerLeaveRequest,
  type LeaveRequest,
  type LeaveRequestPreviousVersion,
} from "@/lib/api";
import { cn } from "@/lib/utils";

function employeeInitials(name: string | null | undefined) {
  const parts = (name ?? "E")
    .trim()
    .split(/\s+/)
    .filter(Boolean);
  if (parts.length === 0) return "E";
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return `${parts[0][0]}${parts[parts.length - 1][0]}`.toUpperCase();
}

function LeaveEmployeeAvatar({
  name,
  imageUrl,
  className = "h-11 w-11 text-sm",
}: {
  name: string | null | undefined;
  imageUrl?: string | null;
  className?: string;
}) {
  return (
    <div
      className={cn(
        "flex shrink-0 items-center justify-center overflow-hidden rounded-full bg-[#d8d8d8] font-extrabold text-[#333] ring-2 ring-white shadow-sm",
        className
      )}
    >
      {imageUrl ? (
        <img
          alt={name ?? "Employee"}
          className="h-full w-full object-cover"
          src={imageUrl}
        />
      ) : (
        employeeInitials(name)
      )}
    </div>
  );
}

function SupportingDocumentBlock({
  hasDocument,
  document,
}: {
  hasDocument: boolean;
  document?: string | null;
}) {
  if (!hasDocument) {
    return <InfoRow label="Supporting document">None</InfoRow>;
  }
  const isImage = !!document?.startsWith("data:image/");
  const isPdf = !!document?.toLowerCase().startsWith("data:application/pdf");

  return (
    <div className="space-y-2">
      <InfoRow label="Supporting document">
        {document ? (
          isImage ? (
            "Attached"
          ) : (
            <a
              href={document}
              target="_blank"
              rel="noreferrer"
              className="font-semibold text-[var(--owner-navy)] underline-offset-2 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--owner-navy)]"
            >
              {isPdf ? "View PDF" : "View document"}
            </a>
          )
        ) : (
          <span className="font-medium text-[#6B7280]">Loading document…</span>
        )}
      </InfoRow>
      {document && isImage ? (
        <a
          href={document}
          target="_blank"
          rel="noreferrer"
          className="block rounded-lg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--owner-navy)]"
        >
          <img
            src={document}
            alt="Supporting document"
            className="max-h-40 w-full rounded-lg border border-slate-200 object-contain"
          />
          <p className="mt-1.5 text-xs font-medium text-[var(--owner-navy)]">
            View full size
          </p>
        </a>
      ) : null}
    </div>
  );
}

const TABS = [
  { key: "pending", label: "Pending" },
  { key: "cancellation_pending", label: "Cancellations" },
  { key: "approved", label: "Approved" },
  { key: "rejected", label: "Rejected" },
  { key: "all", label: "History" },
] as const;

const LEAVE_TYPES = [
  { value: "", label: "All types" },
  { value: "sick", label: "Sick Leave" },
  { value: "vacation", label: "Vacation Leave" },
  { value: "emergency", label: "Emergency Leave" },
  { value: "maternity", label: "Maternity Leave" },
  { value: "paternity", label: "Paternity Leave" },
  { value: "unpaid", label: "Unpaid Leave" },
  { value: "other", label: "Other" },
];

function statusBadge(status: LeaveRequest["status"]) {
  if (status === "approved") {
    return "bg-emerald-100 text-emerald-800";
  }
  if (status === "rejected") {
    return "bg-red-100 text-red-800";
  }
  if (status === "cancellation_pending") {
    return "bg-orange-100 text-orange-900";
  }
  if (status === "cancelled") {
    return "bg-slate-100 text-slate-700";
  }
  return "bg-amber-100 text-amber-900";
}

function leaveActionError(error: unknown, fallback: string) {
  if (
    typeof error === "object" &&
    error !== null &&
    "response" in error &&
    typeof error.response === "object" &&
    error.response !== null &&
    "data" in error.response &&
    typeof error.response.data === "object" &&
    error.response.data !== null &&
    "detail" in error.response.data &&
    typeof error.response.data.detail === "string"
  ) {
    return error.response.data.detail;
  }
  return fallback;
}

function LeaveBalanceNote({
  employeeId,
  leaveType,
  startDate,
  endDate,
}: {
  employeeId: string;
  leaveType: string;
  startDate: string;
  endDate: string;
}) {
  const startYear = Number(startDate.slice(0, 4));
  const endYear = Number(endDate.slice(0, 4));
  const years: number[] = [];
  if (Number.isInteger(startYear) && Number.isInteger(endYear)) {
    for (let year = startYear; year <= endYear; year += 1) years.push(year);
  }
  const results = useQueries({
    queries: years.map((year) => ({
      queryKey: ["employee-leave-balances", employeeId, year],
      queryFn: () => getEmployeeLeaveBalances(employeeId, year),
    })),
  });
  return (
    <InfoRow label="Entitlement">
      <div className="space-y-1">
        {results.map((result, index) => {
          const year = years[index];
          const item = result.data?.items.find(
            (row) => row.leave_type === leaveType
          );
          if (result.isLoading) {
            return (
              <p key={year} className="text-sm text-[#6B7280]">
                Loading {year} balance…
              </p>
            );
          }
          if (item?.disabled) {
            return (
              <p key={year} className="text-sm text-amber-800">
                {year} {item.leave_type_label} is not available.
              </p>
            );
          }
          if (!item || !item.configured) {
            return (
              <p key={year} className="text-sm text-amber-800">
                No {year} allowance is set in Leave Policy.
              </p>
            );
          }
          return (
            <p key={year} className="text-sm text-[#111827]">
              {year}: {item.remaining_days} remaining of {item.allocated_days}{" "}
              allocated ({item.used_days} used)
            </p>
          );
        })}
      </div>
    </InfoRow>
  );
}

function formatLeaveDate(iso: string) {
  const [year, month, day] = iso.split("-").map(Number);
  if (!year || !month || !day) {
    return { short: iso, display: iso, weekday: "", full: iso };
  }
  const value = new Date(year, month - 1, day);
  return {
    short: value.toLocaleDateString(undefined, { month: "short", day: "numeric" }),
    display: value.toLocaleDateString(undefined, {
      month: "short",
      day: "numeric",
      year: "numeric",
    }),
    weekday: value.toLocaleDateString(undefined, { weekday: "long" }),
    full: value.toLocaleDateString(undefined, {
      month: "long",
      day: "numeric",
      year: "numeric",
    }),
  };
}

function LeaveDateRange({
  startDate,
  endDate,
  leaveDays,
}: {
  startDate: string;
  endDate: string;
  leaveDays: number;
}) {
  const start = formatLeaveDate(startDate);
  const end = formatLeaveDate(endDate);
  return (
    <div>
      <div className="grid grid-cols-2 gap-4">
        <div className="min-w-0">
          <p className="text-[11px] font-medium uppercase tracking-[0.14em] text-[#6B7280]">
            Start date
          </p>
          <p className="mt-1 truncate text-sm font-semibold text-[#111827]">
            {start.display}
          </p>
          <p className="truncate text-xs text-[#6B7280]">{start.weekday}</p>
        </div>
        <div className="min-w-0">
          <p className="text-[11px] font-medium uppercase tracking-[0.14em] text-[#6B7280]">
            End date
          </p>
          <p className="mt-1 truncate text-sm font-semibold text-[#111827]">
            {end.display}
          </p>
          <p className="truncate text-xs text-[#6B7280]">{end.weekday}</p>
        </div>
      </div>
      <p className="mt-3 text-sm font-medium text-[#374151]">
        {leaveDays} day{leaveDays === 1 ? "" : "s"}
      </p>
    </div>
  );
}

function InfoRow({
  label,
  children,
}: {
  label: string;
  children: ReactNode;
}) {
  return (
    <div className="grid grid-cols-[8.75rem_minmax(0,1fr)] items-baseline gap-3 border-b border-slate-100 py-2.5 last:border-b-0 max-[380px]:grid-cols-1 max-[380px]:gap-0.5">
      <p className="text-xs text-[#6B7280]">{label}</p>
      <div className="min-w-0 text-sm font-medium text-[#111827] [overflow-wrap:anywhere]">
        {children}
      </div>
    </div>
  );
}

function DrawerDisclosure({
  title,
  open,
  onToggle,
  children,
}: {
  title: string;
  open: boolean;
  onToggle: () => void;
  children: ReactNode;
}) {
  return (
    <section className="border-t border-slate-200">
      <button
        type="button"
        className="flex w-full items-center justify-between gap-3 px-4 py-3 text-left transition-colors hover:bg-slate-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--owner-navy)] sm:px-5"
        aria-expanded={open}
        onClick={onToggle}
      >
        <span className="text-[11px] font-medium uppercase tracking-[0.14em] text-[#6B7280]">
          {title}
        </span>
        <ChevronDown
          className={cn(
            "h-4 w-4 shrink-0 text-[#6B7280] transition-transform duration-150",
            open && "rotate-180"
          )}
          aria-hidden="true"
        />
      </button>
      {open ? <div className="px-4 pb-4 sm:px-5">{children}</div> : null}
    </section>
  );
}

function statusLabel(status: LeaveRequest["status"]) {
  if (status === "approved") return "Approved";
  if (status === "rejected") return "Rejected";
  if (status === "cancellation_pending") return "Cancellation Pending";
  if (status === "cancelled") return "Cancelled";
  return "Pending Approval";
}

function tabForLeaveStatus(
  status: LeaveRequest["status"]
): (typeof TABS)[number]["key"] {
  if (
    status === "pending" ||
    status === "cancellation_pending" ||
    status === "approved" ||
    status === "rejected"
  ) {
    return status;
  }
  return "all";
}

export function OwnerLeaveManagementPage() {
  const { requestId } = useParams<{ requestId?: string }>();
  const qc = useQueryClient();
  const [tab, setTab] = useState<(typeof TABS)[number]["key"]>("pending");
  const [leaveType, setLeaveType] = useState("");
  const [employeeId, setEmployeeId] = useState("");
  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [selected, setSelected] = useState<LeaveRequest | null>(null);
  const [remarks, setRemarks] = useState("");
  const [payrollIsPaid, setPayrollIsPaid] = useState(true);
  const [overrideReason, setOverrideReason] = useState("");
  const [detailLoading, setDetailLoading] = useState(false);
  const [requestInfoOpen, setRequestInfoOpen] = useState(true);
  const [reviewDetailsOpen, setReviewDetailsOpen] = useState(true);
  const openedDeepLinkId = useRef<string | null>(null);

  const selectRequest = async (request: LeaveRequest) => {
    setSelected(request);
    setRemarks(request.owner_remarks ?? "");
    setPayrollIsPaid(request.policy_is_paid ?? request.is_paid);
    setOverrideReason("");
    setDetailLoading(true);
    try {
      const full = await getOwnerLeaveRequest(request.id);
      setSelected(full);
      setRemarks(full.owner_remarks ?? "");
      setPayrollIsPaid(full.policy_is_paid ?? full.is_paid);
    } catch {
      toast.error("Could not load leave request details");
    } finally {
      setDetailLoading(false);
    }
  };

  const { data: employees = [] } = useQuery({
    queryKey: ["employees", "all"],
    queryFn: () => listEmployees(true),
  });

  const { data: requests = [], isLoading } = useQuery({
    queryKey: [
      "owner-leave-requests",
      tab,
      leaveType,
      employeeId,
      startDate,
      endDate,
    ],
    queryFn: () =>
      listOwnerLeaveRequests({
        status: tab === "all" ? "all" : tab,
        leave_type: leaveType || undefined,
        employee_id: employeeId || undefined,
        start_date: startDate || undefined,
        end_date: endDate || undefined,
      }),
  });

  const listMatch = useMemo(
    () => (requestId ? requests.find((item) => item.id === requestId) : undefined),
    [requestId, requests]
  );

  const { data: fetchedRequest, isError: deepLinkError } = useQuery({
    queryKey: ["owner-leave-request", requestId],
    queryFn: () => getOwnerLeaveRequest(requestId!),
    enabled: Boolean(requestId) && !isLoading && !listMatch,
    retry: false,
  });

  useEffect(() => {
    if (!requestId) {
      openedDeepLinkId.current = null;
      return;
    }
    if (openedDeepLinkId.current === requestId) return;

    const target = listMatch ?? fetchedRequest;
    if (!target) return;

    openedDeepLinkId.current = requestId;
    setTab(tabForLeaveStatus(target.status));
    if (listMatch) {
      void selectRequest(listMatch);
    } else {
      setSelected(target);
      setRemarks(target.owner_remarks ?? "");
      setPayrollIsPaid(target.policy_is_paid ?? target.is_paid);
      setOverrideReason("");
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [requestId, listMatch, fetchedRequest]);

  useEffect(() => {
    if (!deepLinkError || listMatch) return;
    toast.error("Could not load leave request details");
  }, [deepLinkError, listMatch]);

  useEffect(() => {
    setRequestInfoOpen(true);
    setReviewDetailsOpen(true);
  }, [selected?.id]);

  const invalidateLeaveQueries = () => {
    void qc.invalidateQueries({ queryKey: ["owner-leave-requests"] });
    void qc.invalidateQueries({ queryKey: ["weekly-schedule"] });
    void qc.invalidateQueries({ queryKey: ["owner-attendance-report"] });
    void qc.invalidateQueries({ queryKey: ["schedule-leave-availability"] });
  };

  const approve = useMutation({
    mutationFn: () =>
      approveOwnerLeaveRequest(selected!.id, remarks.trim() || undefined, {
        is_paid: payrollIsPaid,
        override_reason:
          payrollIsPaid !== (selected!.policy_is_paid ?? selected!.is_paid)
            ? overrideReason.trim() || undefined
            : undefined,
      }),
    onSuccess: () => {
      toast.success("Leave request approved");
      setSelected(null);
      setRemarks("");
      setOverrideReason("");
      invalidateLeaveQueries();
    },
    onError: (error) =>
      toast.error(leaveActionError(error, "Failed to approve leave request")),
  });

  const reject = useMutation({
    mutationFn: () =>
      rejectOwnerLeaveRequest(selected!.id, remarks.trim() || undefined),
    onSuccess: () => {
      toast.success("Leave request rejected");
      setSelected(null);
      setRemarks("");
      setOverrideReason("");
      invalidateLeaveQueries();
    },
    onError: () => toast.error("Failed to reject leave request"),
  });

  const approveCancellation = useMutation({
    mutationFn: () =>
      approveOwnerLeaveCancellation(selected!.id, remarks.trim() || undefined),
    onSuccess: () => {
      toast.success("Leave cancellation approved");
      setSelected(null);
      setRemarks("");
      setOverrideReason("");
      invalidateLeaveQueries();
    },
    onError: () => toast.error("Failed to approve cancellation"),
  });

  const rejectCancellation = useMutation({
    mutationFn: () =>
      rejectOwnerLeaveCancellation(selected!.id, remarks.trim() || undefined),
    onSuccess: () => {
      toast.success("Leave cancellation rejected");
      setSelected(null);
      setRemarks("");
      setOverrideReason("");
      invalidateLeaveQueries();
    },
    onError: () => toast.error("Failed to reject cancellation"),
  });

  const visible = useMemo(() => requests, [requests]);
  const reviewPending =
    approve.isPending ||
    reject.isPending ||
    approveCancellation.isPending ||
    rejectCancellation.isPending;

  return (
    <OwnerPage>
      <OwnerPageHeader
        title="Leave Management"
        description="Review employee leave requests and keep schedules, attendance, and payroll in sync."
      />
      <OwnerPageContent>
        <div className="owner-tabs mb-4">
          {TABS.map((item) => (
            <button
              key={item.key}
              className={cn(
                "owner-tab",
                tab === item.key ? "owner-tab-active" : "owner-tab-idle"
              )}
              onClick={() => setTab(item.key)}
              type="button"
            >
              {item.label}
            </button>
          ))}
        </div>

        <div className="owner-toolbar mb-5">
          <div className="owner-filter-grid">
          <select
            className="h-10 rounded-xl border border-slate-200 bg-white px-3 text-sm shadow-sm"
            value={employeeId}
            onChange={(event) => setEmployeeId(event.target.value)}
          >
            <option value="">All employees</option>
            {employees.map((employee) => (
              <option key={employee.id} value={employee.id}>
                {employee.full_name}
              </option>
            ))}
          </select>
          <select
            className="h-10 rounded-xl border border-slate-200 bg-white px-3 text-sm shadow-sm"
            value={leaveType}
            onChange={(event) => setLeaveType(event.target.value)}
          >
            {LEAVE_TYPES.map((type) => (
              <option key={type.value || "all"} value={type.value}>
                {type.label}
              </option>
            ))}
          </select>
          <Input
            className="h-10 rounded-xl shadow-sm"
            type="date"
            value={startDate}
            onChange={(event) => setStartDate(event.target.value)}
          />
          <Input
            className="h-10 rounded-xl shadow-sm"
            type="date"
            value={endDate}
            onChange={(event) => setEndDate(event.target.value)}
          />
          </div>
        </div>

        <div className="space-y-3">
          {isLoading ? (
            <div className="owner-panel px-6 py-10 text-center text-sm text-muted-foreground">
              Loading leave requests…
            </div>
          ) : visible.length === 0 ? (
            <div className="owner-empty">
              No leave requests in this view.
            </div>
          ) : (
            visible.map((request) => (
              <button
                key={request.id}
                className={cn(
                  "owner-list-row",
                  selected?.id === request.id && "owner-list-row-active"
                )}
                onClick={() => {
                  void selectRequest(request);
                }}
                type="button"
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="flex min-w-0 items-start gap-3">
                    <LeaveEmployeeAvatar
                      name={request.employee_name}
                      imageUrl={request.employee_profile_image_url}
                    />
                    <div className="min-w-0">
                      <p className="truncate font-semibold text-[#111827]">
                        {request.employee_name ?? "Employee"}
                      </p>
                      <p className="text-sm text-[#6B7280]">
                        {request.leave_type_label} · {request.leave_days} day
                        {request.leave_days === 1 ? "" : "s"}
                      </p>
                      {request.other_leave_specification ? (
                        <p className="text-sm text-[#374151]">
                          Other Leave Type: {request.other_leave_specification}
                        </p>
                      ) : null}
                      <p className="mt-1 text-xs font-medium text-[#4B5563]">
                        {request.start_date} – {request.end_date}
                      </p>
                      {request.has_pending_changes ? (
                        <p className="mt-1 text-xs font-semibold text-orange-700">
                          Updated request pending review
                        </p>
                      ) : null}
                    </div>
                  </div>
                  <span
                    className={cn(
                      "rounded-full px-2.5 py-1 text-[11px] font-bold",
                      statusBadge(request.status)
                    )}
                  >
                    {statusLabel(request.status)}
                  </span>
                </div>
              </button>
            ))
          )}
        </div>

        <Dialog
          open={Boolean(selected)}
          onOpenChange={(open) => {
            if (!open) {
              setSelected(null);
              setRemarks("");
              setOverrideReason("");
            }
          }}
        >
          <DialogContent
            hideClose
            overlayClassName="bg-slate-900/20"
            className="flex max-h-[min(85vh,42rem)] w-[min(30rem,calc(100vw-2rem))] max-w-[30rem] flex-col gap-0 overflow-hidden rounded-2xl border-slate-200/90 bg-white p-0 shadow-[0_1px_2px_rgba(15,23,42,0.05),0_16px_40px_rgba(15,23,42,0.12)] sm:rounded-2xl"
          >
            <DialogHeader className="shrink-0 space-y-0 border-b border-slate-200 px-4 py-4 text-left sm:px-5">
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="text-[11px] font-medium uppercase tracking-[0.14em] text-[#6B7280]">
                    Leave request
                  </p>
                  <DialogTitle className="mt-1.5 text-[1.15rem] font-semibold tracking-tight text-[#111827]">
                    Leave Details
                  </DialogTitle>
                  <DialogDescription className="mt-1 text-sm text-[#6B7280]">
                    Review leave request information
                  </DialogDescription>
                </div>
                <DialogClose className="inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-md text-[#4B5563] transition-colors hover:bg-slate-100 hover:text-[#111827] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--owner-navy)]">
                  <X className="h-4 w-4" aria-hidden="true" />
                  <span className="sr-only">Close</span>
                </DialogClose>
              </div>
            </DialogHeader>
            {selected ? (
              <>
                <div className="min-h-0 flex-1 overflow-y-auto">
                  <div className="border-b border-slate-200/80 bg-[var(--owner-well)] px-4 py-3.5 sm:px-5">
                    <div className="flex items-center gap-3">
                      <LeaveEmployeeAvatar
                        name={selected.employee_name}
                        imageUrl={selected.employee_profile_image_url}
                        className="h-11 w-11 text-sm"
                      />
                      <div className="min-w-0 flex-1">
                        <p
                          className="truncate text-[15px] font-semibold tracking-tight text-[#111827]"
                          title={selected.employee_name ?? "Employee"}
                        >
                          {selected.employee_name ?? "Employee"}
                        </p>
                        <p className="truncate text-sm text-[#6B7280]">
                          {selected.employee_position ?? "No role"}
                        </p>
                        {detailLoading ? (
                          <p className="mt-0.5 text-xs text-[#9CA3AF]">
                            Loading details…
                          </p>
                        ) : null}
                      </div>
                      <span
                        className={cn(
                          "shrink-0 rounded-full px-2.5 py-1 text-[11px] font-bold",
                          statusBadge(selected.status)
                        )}
                      >
                        {statusLabel(selected.status)}
                      </span>
                    </div>
                  </div>

                  <div className="space-y-4 px-4 py-4 sm:px-5">
                    <div>
                      <p className="text-[11px] font-medium uppercase tracking-[0.14em] text-[#6B7280]">
                        Leave type
                      </p>
                      <p className="mt-1 text-lg font-semibold tracking-tight text-[#111827]">
                        {selected.leave_type_label}
                      </p>
                      {selected.other_leave_specification ? (
                        <p className="mt-1 text-sm text-[#374151]">
                          Other Leave Type: {selected.other_leave_specification}
                        </p>
                      ) : null}
                    </div>
                    <LeaveDateRange
                      startDate={selected.start_date}
                      endDate={selected.end_date}
                      leaveDays={selected.leave_days}
                    />
                    <div>
                      <p className="text-[11px] font-medium uppercase tracking-[0.14em] text-[#6B7280]">
                        Reason
                      </p>
                      <p className="mt-2 whitespace-pre-wrap border-y border-slate-200 py-3 text-sm leading-6 text-[#111827]">
                        {selected.reason}
                      </p>
                    </div>
                  </div>

                  {selected.has_pending_changes && selected.previous_request ? (
                    <div className="border-t border-slate-200 px-4 py-4 sm:px-5">
                      <LeaveComparison
                        previous={selected.previous_request}
                        updated={selected}
                      />
                    </div>
                  ) : null}

                  <DrawerDisclosure
                    title="Request Information"
                    open={requestInfoOpen}
                    onToggle={() => setRequestInfoOpen((open) => !open)}
                  >
                    <InfoRow label="Submitted">
                      {selected.created_at
                        ? new Date(selected.created_at).toLocaleString()
                        : "—"}
                    </InfoRow>
                    <InfoRow label="Status">{statusLabel(selected.status)}</InfoRow>
                    <InfoRow label="Company policy">
                      {(selected.policy_is_paid ?? selected.is_paid)
                        ? "Paid Leave"
                        : "Unpaid Leave"}
                    </InfoRow>
                    {selected.status !== "pending" ? (
                      <InfoRow label="Payroll treatment">
                        {selected.is_paid ? "Paid Leave" : "Unpaid Leave"}
                      </InfoRow>
                    ) : null}
                    <LeaveBalanceNote
                      employeeId={selected.employee_id}
                      leaveType={selected.leave_type}
                      startDate={selected.start_date}
                      endDate={selected.end_date}
                    />
                    <SupportingDocumentBlock
                      hasDocument={selected.has_supporting_document}
                      document={selected.supporting_document}
                    />
                  </DrawerDisclosure>

                  {selected.status === "pending" ||
                  selected.status === "cancellation_pending" ? (
                    <div className="space-y-3 border-t border-slate-200 px-4 py-4 sm:px-5">
                      <p className="text-[11px] font-medium uppercase tracking-[0.14em] text-[#6B7280]">
                        Review
                      </p>
                      {selected.status === "cancellation_pending" ? (
                        <p className="text-sm text-orange-900">
                          This employee requested to cancel an approved leave.
                        </p>
                      ) : null}
                      {selected.status === "pending" ? (
                        <div className="space-y-2">
                          <p className="text-xs text-[#6B7280]">
                            Payroll treatment
                          </p>
                          <p className="text-xs text-[#6B7280]">
                            Defaults to company policy. Change only if needed.
                          </p>
                          <label className="flex items-center gap-2 text-sm text-[#111827]">
                            <input
                              type="radio"
                              name="payroll-treatment"
                              checked={payrollIsPaid}
                              onChange={() => setPayrollIsPaid(true)}
                            />
                            Paid Leave
                          </label>
                          <label className="flex items-center gap-2 text-sm text-[#111827]">
                            <input
                              type="radio"
                              name="payroll-treatment"
                              checked={!payrollIsPaid}
                              onChange={() => setPayrollIsPaid(false)}
                            />
                            Unpaid Leave
                          </label>
                          {payrollIsPaid !==
                          (selected.policy_is_paid ?? selected.is_paid) ? (
                            <Input
                              className="mt-1 h-10 rounded-lg"
                              placeholder="Reason for override (optional)"
                              value={overrideReason}
                              onChange={(event) =>
                                setOverrideReason(event.target.value)
                              }
                            />
                          ) : null}
                        </div>
                      ) : null}
                      <RemarksField remarks={remarks} onChange={setRemarks} />
                    </div>
                  ) : (
                    <DrawerDisclosure
                      title="Additional review details"
                      open={reviewDetailsOpen}
                      onToggle={() => setReviewDetailsOpen((open) => !open)}
                    >
                      <InfoRow label="Owner remarks">
                        {selected.owner_remarks || "None"}
                      </InfoRow>
                    </DrawerDisclosure>
                  )}
                </div>
                <div className="flex shrink-0 flex-wrap items-center justify-end gap-2 border-t border-slate-200 bg-white px-4 py-3 sm:px-5">
                  <DialogClose asChild>
                    <Button type="button" variant="ghost" size="sm">
                      Close
                    </Button>
                  </DialogClose>
                  {selected.status === "pending" ? (
                    <ReviewActions
                      disabled={reviewPending}
                      onApprove={() => approve.mutate()}
                      onReject={() => reject.mutate()}
                    />
                  ) : null}
                  {selected.status === "cancellation_pending" ? (
                    <ReviewActions
                      disabled={reviewPending}
                      approveLabel="Approve Cancellation"
                      rejectLabel="Reject Cancellation"
                      onApprove={() => approveCancellation.mutate()}
                      onReject={() => rejectCancellation.mutate()}
                    />
                  ) : null}
                </div>
              </>
            ) : null}
          </DialogContent>
        </Dialog>
      </OwnerPageContent>
    </OwnerPage>
  );
}


function LeaveComparison({
  previous,
  updated,
}: {
  previous: LeaveRequestPreviousVersion;
  updated: LeaveRequest;
}) {
  return (
    <div className="space-y-3">
      <p className="text-[11px] font-medium uppercase tracking-[0.14em] text-[#6B7280]">
        Previous vs updated
      </p>
      <div className="grid gap-3">
        <div className="rounded-lg border border-slate-200 bg-slate-50 p-3">
          <p className="mb-2 text-xs font-semibold text-[#6B7280]">
            Previous
          </p>
          <ComparisonDetails
            leaveTypeLabel={previous.leave_type_label}
            otherLeaveSpecification={previous.other_leave_specification}
            startDate={previous.start_date}
            endDate={previous.end_date ?? previous.start_date}
            leaveDays={previous.leave_days}
            isPaid={previous.is_paid}
            reason={previous.reason}
          />
        </div>
        <div className="rounded-lg border border-slate-200 bg-white p-3">
          <p className="mb-2 text-xs font-semibold text-[var(--owner-navy)]">
            Updated
          </p>
          <ComparisonDetails
            leaveTypeLabel={updated.leave_type_label}
            otherLeaveSpecification={updated.other_leave_specification}
            startDate={updated.start_date}
            endDate={updated.end_date}
            leaveDays={updated.leave_days}
            isPaid={updated.is_paid}
            reason={updated.reason}
          />
        </div>
      </div>
    </div>
  );
}

function ComparisonDetails({
  leaveTypeLabel,
  otherLeaveSpecification,
  startDate,
  endDate,
  leaveDays,
  isPaid,
  reason,
}: {
  leaveTypeLabel: string;
  otherLeaveSpecification: string | null;
  startDate: string;
  endDate: string;
  leaveDays: number;
  isPaid: boolean;
  reason: string;
}) {
  return (
    <div className="space-y-2 text-sm">
      <p className="font-medium text-[#111827]">{leaveTypeLabel}</p>
      {otherLeaveSpecification ? (
        <p className="text-[#374151]">
          Other Leave Type: {otherLeaveSpecification}
        </p>
      ) : null}
      <p className="text-[#6B7280]">
        {startDate} – {endDate}
      </p>
      <p className="text-[#6B7280]">
        {leaveDays} day{leaveDays === 1 ? "" : "s"} ·{" "}
        {isPaid ? "Paid" : "Unpaid"}
      </p>
      <p className="text-[#374151]">{reason}</p>
    </div>
  );
}

function RemarksField({
  remarks,
  onChange,
}: {
  remarks: string;
  onChange: (value: string) => void;
}) {
  return (
    <div className="space-y-2">
      <label className="text-xs text-[#6B7280]" htmlFor="leave-owner-remarks">
        Remarks (optional)
      </label>
      <textarea
        id="leave-owner-remarks"
        className="min-h-[88px] w-full rounded-lg border border-slate-200 px-3 py-2 text-sm outline-none transition-colors focus:border-[var(--owner-navy)] focus-visible:ring-2 focus-visible:ring-[var(--owner-navy)]"
        value={remarks}
        onChange={(event) => onChange(event.target.value)}
        placeholder="Add a short note for the employee"
      />
    </div>
  );
}

function ReviewActions({
  disabled,
  approveLabel = "Approve",
  rejectLabel = "Reject",
  onApprove,
  onReject,
}: {
  disabled: boolean;
  approveLabel?: string;
  rejectLabel?: string;
  onApprove: () => void;
  onReject: () => void;
}) {
  return (
    <>
      <Button
        className="rounded-md border-red-200 text-red-700 hover:bg-red-50 focus-visible:ring-red-700"
        disabled={disabled}
        onClick={onReject}
        type="button"
        size="sm"
        variant="outline"
      >
        {rejectLabel}
      </Button>
      <Button
        className="rounded-md bg-[var(--owner-button)] text-white hover:bg-[var(--owner-navy-soft)]"
        disabled={disabled}
        onClick={onApprove}
        size="sm"
        type="button"
      >
        {approveLabel}
      </Button>
    </>
  );
}

