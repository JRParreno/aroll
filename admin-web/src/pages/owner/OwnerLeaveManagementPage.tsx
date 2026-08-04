import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useMemo, useState } from "react";
import { useParams } from "react-router-dom";
import { toast } from "sonner";
import {
  OwnerPage,
  OwnerPageContent,
  OwnerPageHeader,
} from "@/components/owner/layout/OwnerPageLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  approveOwnerLeaveCancellation,
  approveOwnerLeaveRequest,
  getOwnerLeaveRequest,
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
    return <Detail label="Supporting document" value="None" />;
  }
  const isImage = !!document?.startsWith("data:image/");
  const isPdf = !!document?.toLowerCase().startsWith("data:application/pdf");

  return (
    <div className="space-y-2">
      <Detail label="Supporting document" value="Attached" />
      {document ? (
        <div className="rounded-xl border border-slate-200 bg-[#FAFBFC] p-3">
          {isImage ? (
            <a href={document} target="_blank" rel="noreferrer" className="block">
              <img
                src={document}
                alt="Supporting document"
                className="max-h-56 w-full rounded-lg object-contain"
              />
              <p className="mt-2 text-xs font-semibold text-[#1F456B]">
                Tap to view full size
              </p>
            </a>
          ) : isPdf ? (
            <a
              href={document}
              target="_blank"
              rel="noreferrer"
              className="inline-flex items-center rounded-lg bg-[#1F456B] px-3 py-2 text-sm font-semibold text-white"
            >
              View PDF
            </a>
          ) : (
            <a
              href={document}
              target="_blank"
              rel="noreferrer"
              className="text-sm font-semibold text-[#1F456B] underline"
            >
              View document
            </a>
          )}
        </div>
      ) : (
        <p className="text-xs text-[#6B7280]">Loading document…</p>
      )}
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

function statusLabel(status: LeaveRequest["status"]) {
  if (status === "approved") return "Approved";
  if (status === "rejected") return "Rejected";
  if (status === "cancellation_pending") return "Cancellation Pending";
  if (status === "cancelled") return "Cancelled";
  return "Pending Approval";
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

  useEffect(() => {
    if (!requestId || requests.length === 0) return;
    const match = requests.find((item) => item.id === requestId);
    if (match) {
      if (match.status === "cancellation_pending") {
        setTab("cancellation_pending");
      } else if (match.status === "pending") {
        setTab("pending");
      }
      void selectRequest(match);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [requestId, requests]);

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
    onError: () => toast.error("Failed to approve leave request"),
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
        <div className="mb-4 flex flex-wrap gap-2">
          {TABS.map((item) => (
            <button
              key={item.key}
              className={cn(
                "rounded-full px-3.5 py-1.5 text-sm font-semibold transition",
                tab === item.key
                  ? "bg-[#1F456B] text-white"
                  : "bg-white text-[#4B5563] ring-1 ring-slate-200 hover:bg-slate-50"
              )}
              onClick={() => setTab(item.key)}
              type="button"
            >
              {item.label}
            </button>
          ))}
        </div>

        <div className="mb-5 grid gap-3 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:grid-cols-2 lg:grid-cols-4">
          <select
            className="h-10 rounded-xl border border-slate-200 bg-white px-3 text-sm"
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
            className="h-10 rounded-xl border border-slate-200 bg-white px-3 text-sm"
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
            className="h-10 rounded-xl"
            type="date"
            value={startDate}
            onChange={(event) => setStartDate(event.target.value)}
          />
          <Input
            className="h-10 rounded-xl"
            type="date"
            value={endDate}
            onChange={(event) => setEndDate(event.target.value)}
          />
        </div>

        <div className="grid gap-4 lg:grid-cols-[1.2fr_0.8fr]">
          <div className="space-y-3">
            {isLoading ? (
              <p className="text-sm text-muted-foreground">Loading…</p>
            ) : visible.length === 0 ? (
              <div className="rounded-2xl border border-slate-200 bg-white p-6 text-sm text-muted-foreground shadow-sm">
                No leave requests in this view.
              </div>
            ) : (
              visible.map((request) => (
                <button
                  key={request.id}
                  className={cn(
                    "w-full rounded-2xl border bg-white p-4 text-left shadow-sm transition hover:shadow-md",
                    selected?.id === request.id
                      ? "border-[#1F456B]"
                      : "border-slate-200"
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

          <div className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
            {!selected ? (
              <p className="text-sm text-muted-foreground">
                Select a leave request to review details.
              </p>
            ) : (
              <div className="space-y-4">
                <div className="flex items-start gap-3">
                  <LeaveEmployeeAvatar
                    name={selected.employee_name}
                    imageUrl={selected.employee_profile_image_url}
                    className="h-14 w-14 text-base"
                  />
                  <div>
                    <h2 className="text-lg font-semibold text-[#111827]">
                      {selected.employee_name}
                    </h2>
                    <p className="text-sm text-[#6B7280]">
                      {selected.employee_position ?? "No role"}
                    </p>
                    {detailLoading ? (
                      <p className="mt-1 text-xs text-[#9CA3AF]">
                        Loading details…
                      </p>
                    ) : null}
                  </div>
                </div>

                {selected.has_pending_changes && selected.previous_request ? (
                  <LeaveComparison
                    previous={selected.previous_request}
                    updated={selected}
                  />
                ) : (
                  <>
                    <Detail label="Leave type" value={selected.leave_type_label} />
                    <Detail
                      label="Requested dates"
                      value={`${selected.start_date} – ${selected.end_date}`}
                    />
                    <Detail
                      label="Leave days"
                      value={`${selected.leave_days} day${
                        selected.leave_days === 1 ? "" : "s"
                      }`}
                    />
                    <Detail
                      label="Company Policy"
                      value={
                        (selected.policy_is_paid ?? selected.is_paid)
                          ? "Paid Leave"
                          : "Unpaid Leave"
                      }
                    />
                    {selected.status !== "pending" ? (
                      <Detail
                        label="Payroll Treatment"
                        value={
                          selected.is_paid ? "Paid Leave" : "Unpaid Leave"
                        }
                      />
                    ) : null}
                    <Detail label="Reason" value={selected.reason} />
                  </>
                )}

                <SupportingDocumentBlock
                  hasDocument={selected.has_supporting_document}
                  document={selected.supporting_document}
                />

                {selected.status === "pending" ? (
                  <>
                    <div className="space-y-2 rounded-xl border border-slate-200 bg-[#FAFBFC] p-3">
                      <p className="text-xs font-semibold uppercase tracking-wide text-[#6B7280]">
                        Payroll Treatment
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
                          className="mt-1 h-10 rounded-xl"
                          placeholder="Reason for override (optional)"
                          value={overrideReason}
                          onChange={(event) =>
                            setOverrideReason(event.target.value)
                          }
                        />
                      ) : null}
                    </div>
                    <RemarksField remarks={remarks} onChange={setRemarks} />
                    <ReviewActions
                      disabled={reviewPending}
                      onApprove={() => approve.mutate()}
                      onReject={() => reject.mutate()}
                    />
                  </>
                ) : selected.status === "cancellation_pending" ? (
                  <>
                    <p className="rounded-xl border border-orange-200 bg-orange-50 px-3 py-2 text-sm text-orange-900">
                      This employee requested to cancel an approved leave.
                    </p>
                    <RemarksField remarks={remarks} onChange={setRemarks} />
                    <ReviewActions
                      disabled={reviewPending}
                      approveLabel="Approve Cancellation"
                      rejectLabel="Reject Cancellation"
                      onApprove={() => approveCancellation.mutate()}
                      onReject={() => rejectCancellation.mutate()}
                    />
                  </>
                ) : (
                  <Detail
                    label="Owner remarks"
                    value={selected.owner_remarks || "None"}
                  />
                )}
              </div>
            )}
          </div>
        </div>
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
      <p className="text-xs font-semibold uppercase tracking-wide text-[#9CA3AF]">
        Previous vs Updated
      </p>
      <div className="grid gap-3 sm:grid-cols-2">
        <div className="rounded-xl border border-slate-200 bg-slate-50 p-3">
          <p className="mb-2 text-xs font-bold uppercase tracking-wide text-[#6B7280]">
            Previous
          </p>
          <ComparisonDetails
            leaveTypeLabel={previous.leave_type_label}
            startDate={previous.start_date}
            endDate={previous.end_date ?? previous.start_date}
            leaveDays={previous.leave_days}
            isPaid={previous.is_paid}
            reason={previous.reason}
          />
        </div>
        <div className="rounded-xl border border-[#1F456B]/20 bg-[#F8FAFC] p-3">
          <p className="mb-2 text-xs font-bold uppercase tracking-wide text-[#1F456B]">
            Updated
          </p>
          <ComparisonDetails
            leaveTypeLabel={updated.leave_type_label}
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
  startDate,
  endDate,
  leaveDays,
  isPaid,
  reason,
}: {
  leaveTypeLabel: string;
  startDate: string;
  endDate: string;
  leaveDays: number;
  isPaid: boolean;
  reason: string;
}) {
  return (
    <div className="space-y-2 text-sm">
      <p className="font-medium text-[#111827]">{leaveTypeLabel}</p>
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
      <label className="text-xs font-semibold uppercase tracking-wide text-[#9CA3AF]">
        Remarks (optional)
      </label>
      <textarea
        className="min-h-[90px] w-full rounded-xl border border-slate-200 px-3 py-2 text-sm outline-none focus:border-[#1F456B]"
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
    <div className="flex gap-2">
      <Button
        className="flex-1 rounded-xl bg-[#1F456B] text-white hover:bg-[#17395D]"
        disabled={disabled}
        onClick={onApprove}
      >
        {approveLabel}
      </Button>
      <Button
        className="flex-1 rounded-xl"
        variant="destructive"
        disabled={disabled}
        onClick={onReject}
      >
        {rejectLabel}
      </Button>
    </div>
  );
}

function Detail({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-[11px] font-semibold uppercase tracking-wide text-[#9CA3AF]">
        {label}
      </p>
      <p className="mt-1 text-sm font-medium text-[#111827]">{value}</p>
    </div>
  );
}
