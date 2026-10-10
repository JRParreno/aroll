import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Download, Pencil, Plus, Search, Trash2 } from "lucide-react";
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
import {
  createPayrollAdjustment,
  deletePayrollAdjustment,
  finalizeOwnerPayroll,
  unfinalizeOwnerPayroll,
  getMe,
  getEmployeePayslip,
  getOwnerPayrollReport,
  getPayrollAdjustmentTypes,
  resolveOwnerHistoricalRate,
  updatePayrollAdjustment,
  type EmployeePayslip,
  type PayBasis,
  type PayrollAdjustment,
} from "@/lib/api";
import { ME_QUERY_KEY } from "@/lib/authSession";
import {
  PAYSLIP_SAMPLE_LINE_1,
  PAYSLIP_SAMPLE_LINE_2,
  sessionIsDemo,
} from "@/lib/tenantMode";
import {
  formatSalaryRate,
  salaryRateLabel,
} from "@/lib/salaryRate";
import { downloadStandardPayslipPdf } from "@/lib/standardPayslipPdf";

function money(value: number) {
  return new Intl.NumberFormat("en-PH", {
    style: "currency",
    currency: "PHP",
  }).format(value);
}

function isUnfinalizedPending(item: {
  pending_attendance_count?: number;
  worked_days?: number;
}) {
  return (item.pending_attendance_count ?? 0) > 0 && !(item.worked_days);
}

function moneyOrPending(value: number, pending: boolean) {
  return pending ? "â€”" : money(value);
}

function hoursLabel(value: number | undefined, pending: boolean) {
  if (pending) return "â€”";
  return `${Number(value ?? 0).toFixed(2)} hrs`;
}

function overtimeHoursLabel(item: {
  overtime_hours?: number;
  overtime_minutes?: number;
  pending?: boolean;
}) {
  if (item.pending) return "â€”";
  const hours =
    item.overtime_hours != null
      ? Number(item.overtime_hours)
      : Number(item.overtime_minutes ?? 0) / 60;
  return `${hours.toFixed(2)} hrs`;
}

function asOfForMonth(year: number, month: number) {
  const lastDay = new Date(year, month, 0).getDate();
  const day = Math.min(new Date().getDate(), lastDay);
  return `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

export function OwnerPayrollPage() {
  const now = new Date();
  const queryClient = useQueryClient();
  const [search, setSearch] = useState("");
  const [selectedYear, setSelectedYear] = useState(now.getFullYear());
  const [selectedMonth, setSelectedMonth] = useState(now.getMonth() + 1);
  const [selectedEmployeeId, setSelectedEmployeeId] = useState<string | null>(null);
  const [editingAdjustment, setEditingAdjustment] =
    useState<PayrollAdjustment | null>(null);
  const [showAdjustmentForm, setShowAdjustmentForm] = useState(false);
  const [unfinalizeOpen, setUnfinalizeOpen] = useState(false);
  const [payslipSettings, setPayslipSettings] = useState({
    title: "Payslip",
    employeeSection: "Employee Information",
    earningsSection: "Earnings/Income",
    deductionsSection: "Deductions",
    netPaySection: "NET PAY",
    notes: "(Total Earnings less deductions)",
    headerColor: "#E5E7EB",
    earningsColor: "#FDE68A",
    deductionsColor: "#FECACA",
    netColor: "#BBF7D0",
  });
  const asOf = asOfForMonth(selectedYear, selectedMonth);
  const { data: me } = useQuery({
    queryKey: ME_QUERY_KEY,
    queryFn: getMe,
  });
  const { data, isLoading } = useQuery({
    queryKey: ["owner-payroll-report", asOf],
    queryFn: () => getOwnerPayrollReport(asOf),
  });
  const { data: payslip, isLoading: payslipLoading } = useQuery({
    queryKey: ["employee-payslip", selectedEmployeeId, asOf],
    queryFn: () => getEmployeePayslip(selectedEmployeeId!, asOf),
    enabled: Boolean(selectedEmployeeId),
  });
  const { data: adjustmentTypes } = useQuery({
    queryKey: ["payroll-adjustment-types"],
    queryFn: getPayrollAdjustmentTypes,
  });

  const refreshPayroll = async () => {
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: ["owner-payroll-report"] }),
      queryClient.invalidateQueries({ queryKey: ["employee-payslip"] }),
    ]);
  };

  const finalizeMutation = useMutation({
    mutationFn: () => finalizeOwnerPayroll(asOf),
    onSuccess: async () => {
      await refreshPayroll();
    },
  });
  const unfinalizeMutation = useMutation({
    mutationFn: () => unfinalizeOwnerPayroll(asOf),
    onSuccess: async () => {
      toast.success("Payroll period reopened successfully.");
      setUnfinalizeOpen(false);
      finalizeMutation.reset();
      await refreshPayroll();
    },
  });

  const items = useMemo(() => {
    const needle = search.toLowerCase();
    return (data?.items ?? []).filter((item) =>
      [item.employee_name, item.position_title ?? ""]
        .join(" ")
        .toLowerCase()
        .includes(needle)
    );
  }, [data, search]);
  const businessName =
    me?.business_name ?? localStorage.getItem("aroll_business_name") ?? "Business";
  const businessLogo = me?.branding?.logo_url ?? null;
  const themeButtonColor = me?.branding?.theme.button_color || "#1E3A5F";
  const themeButtonHoverColor = me?.branding?.theme.secondary_color || "#284B73";
  const canEditPayslip = me?.role === "owner" || me?.role === "manager";
  const canUnfinalize = me?.role === "owner";
  const isDemo = sessionIsDemo(me);
  const incompleteCount = data?.incomplete_attendance_count ?? 0;
  const pendingCount = data?.pending_attendance_count ?? 0;
  const unresolvedHistoricalCount =
    data?.unresolved_historical_rate_count ?? 0;
  const canFinalize = Boolean(data?.can_finalize);
  const isFinalized = Boolean(data?.is_finalized);
  const finalizeError = (() => {
    const error = finalizeMutation.error;
    if (!error || typeof error !== "object" || error === null) return null;
    const detail = (
      error as { response?: { data?: { detail?: unknown } } }
    ).response?.data?.detail;
    if (
      typeof detail === "object" &&
      detail !== null &&
      "message" in detail &&
      typeof (detail as { message?: unknown }).message === "string"
    ) {
      return (detail as { message: string }).message;
    }
    if (typeof detail === "string") return detail;
    if (error instanceof Error) return error.message;
    return "Could not finalize payroll.";
  })();
  const unfinalizeError = (() => {
    const error = unfinalizeMutation.error;
    if (!error || typeof error !== "object" || error === null) return null;
    const detail = (
      error as { response?: { data?: { detail?: unknown } } }
    ).response?.data?.detail;
    if (
      typeof detail === "object" &&
      detail !== null &&
      "message" in detail &&
      typeof (detail as { message?: unknown }).message === "string"
    ) {
      return (detail as { message: string }).message;
    }
    if (typeof detail === "string") return detail;
    if (error instanceof Error) return error.message;
    return "Could not unfinalize payroll.";
  })();

  return (
    <OwnerPage>
      <OwnerPageHeader
        title={isDemo ? "Sample Payroll" : "Payroll History"}
        description={
          isDemo
            ? "Demonstration payroll only. Not for actual salary payment."
            : "Review pay periods and employee earnings."
        }
      />

      <OwnerPageContent>
        <section className="owner-toolbar">
          <div className="mb-4 flex items-start gap-3">
            <div className="owner-icon-well h-9 w-9 shrink-0">
              <Search className="h-4 w-4" />
            </div>
            <div>
              <h2 className="text-sm font-semibold text-[#1F2937]">Payroll filters</h2>
              <p className="text-xs text-[#6B7280]">
                Search employees and choose the pay period to review.
              </p>
            </div>
          </div>
          <div className="grid gap-3 lg:grid-cols-[1fr_auto_auto_auto_auto_auto]">
            <div className="relative">
              <Search className="absolute left-3 top-2.5 h-4 w-4 text-[#9CA3AF]" />
              <Input className="h-10 pl-9" placeholder="Search employee" value={search} onChange={(e) => setSearch(e.target.value)} />
            </div>
            <select
              className="h-10 rounded-xl border border-slate-200 bg-white px-3 text-sm"
              value={selectedMonth}
              onChange={(e) => setSelectedMonth(Number(e.target.value))}
            >
              {[
                "January",
                "February",
                "March",
                "April",
                "May",
                "June",
                "July",
                "August",
                "September",
                "October",
                "November",
                "December",
              ].map((label, index) => (
                <option key={label} value={index + 1}>
                  {label}
                </option>
              ))}
            </select>
            <select
              className="h-10 rounded-xl border border-slate-200 bg-white px-3 text-sm"
              value={selectedYear}
              onChange={(e) => setSelectedYear(Number(e.target.value))}
            >
              {Array.from({ length: 5 }, (_, i) => now.getFullYear() - i).map(
                (year) => (
                  <option key={year} value={year}>
                    {year}
                  </option>
                )
              )}
            </select>
            <Button variant="outline" className="h-10 gap-2 rounded-xl">
              <Download className="h-4 w-4" />
              Download Summary
            </Button>
            <Button
              className="h-10 gap-2 rounded-xl text-white"
              style={{ backgroundColor: themeButtonColor }}
              disabled={
                !canEditPayslip ||
                isFinalized ||
                incompleteCount > 0 ||
                pendingCount > 0 ||
                unresolvedHistoricalCount > 0 ||
                !canFinalize ||
                finalizeMutation.isPending
              }
              onClick={() => finalizeMutation.mutate()}
              onMouseEnter={(e) => {
                e.currentTarget.style.backgroundColor = themeButtonHoverColor;
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.backgroundColor = themeButtonColor;
              }}
            >
              {finalizeMutation.isPending
                ? "Finalizingâ€¦"
                : isFinalized
                  ? isDemo
                    ? "Sample finalized"
                    : "Finalized"
                  : isDemo
                    ? "Finalize sample payroll"
                    : "Finalize Payroll"}
            </Button>
            {isFinalized && canUnfinalize ? (
              <Button
                variant="outline"
                className="gap-2"
                disabled={unfinalizeMutation.isPending}
                onClick={() => setUnfinalizeOpen(true)}
              >
                {unfinalizeMutation.isPending
                  ? "Reopeningâ€¦"
                  : "Unfinalize Payroll"}
              </Button>
            ) : null}
          </div>
          {data?.period_start && data?.period_end ? (
            <div className="mt-3 inline-flex items-center gap-2 rounded-xl bg-[var(--owner-well)] px-3 py-2 text-xs font-medium text-[var(--owner-navy)]">
              <span>
                Period {data.period_start} to {data.period_end}
                {data.payroll_status ? ` Â· ${data.payroll_status}` : ""}
                {isFinalized ? " Â· finalized" : ""}
              </span>
            </div>
          ) : null}
          {incompleteCount > 0 ? (
            <div className="mt-3 rounded-xl border border-amber-200 bg-amber-50 px-3 py-2 text-xs font-medium text-amber-900">
              Payroll cannot be finalized because there are employees with
              incomplete attendance ({incompleteCount}). Resolve all attendance
              corrections first. You can still preview payslips.
            </div>
          ) : pendingCount > 0 ? (
            <div className="mt-3 rounded-xl border border-amber-200 bg-amber-50 px-3 py-2 text-xs font-medium text-amber-900">
              Payroll cannot be finalized because there are employees with
              pending scheduled assignments ({pendingCount}). Resolve all
              pending attendance first. You can still preview payslips.
            </div>
          ) : unresolvedHistoricalCount > 0 ? (
            <div className="mt-3 rounded-xl border border-amber-200 bg-amber-50 px-3 py-2 text-xs font-medium text-amber-900">
              Payroll cannot be finalized because a completed attendance has an
              unresolved historical pay rate ({unresolvedHistoricalCount}).
              Resolve the historical rate before finalizing. You can still
              preview payslips.
            </div>
          ) : null}
          {finalizeError ? (
            <div className="mt-3 rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-xs font-medium text-red-800">
              {finalizeError}
            </div>
          ) : null}
          {unfinalizeError ? (
            <div className="mt-3 rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-xs font-medium text-red-800">
              {unfinalizeError}
            </div>
          ) : null}
          {finalizeMutation.isSuccess &&
          !incompleteCount &&
          !pendingCount &&
          !unresolvedHistoricalCount ? (
            <div className="mt-3 rounded-xl border border-emerald-200 bg-emerald-50 px-3 py-2 text-xs font-medium text-emerald-800">
              {isDemo
                ? "Sample payroll period marked complete for demonstration."
                : "Payroll period finalized successfully."}
            </div>
          ) : null}
        </section>

        <section className="grid gap-5 xl:grid-cols-2">
          {isLoading ? (
            <p className="text-sm text-[#6B7280]">Loading payroll...</p>
          ) : items.length === 0 ? (
            <div className="owner-empty">
              No payroll records found.
            </div>
          ) : (
            items.map((item) => {
              const finalNet =
                (item as { final_net_pay?: number }).final_net_pay ??
                item.net_pay ??
                item.total_salary;
              const pendingOnly = isUnfinalizedPending(item);
              const initials = item.employee_name
                .split(" ")
                .filter(Boolean)
                .slice(0, 2)
                .map((part) => part[0]?.toUpperCase() ?? "")
                .join("");
              return (
              <div
                className="owner-card overflow-hidden"
                key={item.employee_id}
              >
                <div className="p-5">
                  <div className="flex items-start justify-between gap-4">
                    <div className="flex min-w-0 items-start gap-3">
                      <div className="flex h-11 w-11 shrink-0 items-center justify-center overflow-hidden rounded-full bg-[var(--owner-well)] text-sm font-semibold text-[var(--owner-navy)]">
                        {item.profile_image_url ? (
                          <img
                            alt={item.employee_name}
                            className="h-full w-full object-cover"
                            src={item.profile_image_url}
                          />
                        ) : (
                          initials || "E"
                        )}
                      </div>
                      <div className="min-w-0">
                        <h2 className="truncate text-base font-semibold text-[#1F2937]">
                          {item.employee_name}
                        </h2>
                        <p className="text-sm text-[#6B7280]">
                          {item.position_title ?? "Employee"}
                        </p>
                        <p className="mt-1 text-xs text-[#9CA3AF]">
                          {item.period_start} to {item.period_end}
                        </p>
                      </div>
                    </div>
                    <div className="flex shrink-0 flex-col items-end gap-2">
                      <span className="rounded-full border border-slate-200 bg-[#F9FAFB] px-2.5 py-1 text-[11px] font-semibold capitalize text-[#374151]">
                        {item.payroll_status ?? "current"}
                      </span>
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => setSelectedEmployeeId(item.employee_id)}
                      >
                        View Payslip
                      </Button>
                    </div>
                  </div>
                  <div className="mt-5 space-y-2.5 text-sm">
                    {(item.pending_attendance_count ?? 0) > 0 ? (
                      <p className="rounded-lg bg-amber-50 px-3 py-2 text-xs text-amber-800">
                        Pending attendance is not included in payroll until Time
                        Out is recorded.
                      </p>
                    ) : null}
                    {item.has_unresolved_historical_rate ? (
                      <p className="rounded-lg bg-amber-50 px-3 py-2 text-xs text-amber-800">
                        Historical pay rate required for{" "}
                        {item.unresolved_historical_rate_count ?? 1} completed
                        day
                        {(item.unresolved_historical_rate_count ?? 1) === 1
                          ? ""
                          : "s"}
                        . Open the payslip to resolve before finalizing.
                      </p>
                    ) : null}
                    <Row
                      label={salaryRateLabel()}
                      value={formatSalaryRate(item)}
                    />
                    <Row label="Worked Days" value={`${item.worked_days} days`} />
                    <Row
                      label="Hours Worked"
                      value={hoursLabel(item.hours_worked, pendingOnly)}
                    />
                    <Row
                      label="Overtime Hours"
                      value={overtimeHoursLabel({
                        overtime_hours: item.overtime_hours,
                        pending: pendingOnly,
                      })}
                    />
                    <Row
                      label="Overtime Pay"
                      value={moneyOrPending(item.overtime_pay, pendingOnly)}
                    />
                    <Row
                      label="Late Deductions"
                      value={moneyOrPending(item.late_deductions ?? 0, pendingOnly)}
                    />
                    <Row
                      label="Undertime Deductions"
                      value={moneyOrPending(
                        item.undertime_deductions ?? 0,
                        pendingOnly
                      )}
                    />
                    <Row
                      label="Gross Pay"
                      value={moneyOrPending(
                        item.gross_pay ?? item.total_salary + item.deductions,
                        pendingOnly
                      )}
                    />
                    <Row
                      label="Attendance Deductions"
                      value={moneyOrPending(item.deductions, pendingOnly)}
                    />
                    <Row
                      label="Payroll Adjustments"
                      value={money(
                        (item as { payroll_adjustments_total?: number })
                          .payroll_adjustments_total ?? 0
                      )}
                    />
                  </div>
                </div>
                <div className="flex items-center justify-between border-t border-emerald-100 bg-[#F0FDF4] px-5 py-3">
                  <span className="text-sm font-semibold text-[#166534]">
                    Final Net Pay
                  </span>
                  <span className="text-base font-bold text-emerald-700">
                    {moneyOrPending(finalNet, pendingOnly)}
                  </span>
                </div>
              </div>
              );
            })
          )}
        </section>
      </OwnerPageContent>

      <Dialog
        open={Boolean(selectedEmployeeId)}
        onOpenChange={(open) => {
          if (!open) {
            setSelectedEmployeeId(null);
            setShowAdjustmentForm(false);
            setEditingAdjustment(null);
          }
        }}
      >
        <DialogContent className="flex max-h-[92vh] max-w-5xl flex-col overflow-hidden">
          <DialogHeader>
            <DialogTitle>
              {payslip
                ? `${isDemo ? "Sample payslip" : "Payslip"} Â· ${payslip.employee_name}`
                : isDemo
                  ? "Sample payslip"
                  : "Payslip"}
            </DialogTitle>
            {payslip ? (
              <p className="text-sm text-[#6B7280]">
                {payslip.period_start} to {payslip.period_end} Â·{" "}
                {payslip.position_title ?? "Employee"}
              </p>
            ) : null}
          </DialogHeader>
          <div className="min-h-0 flex-1 overflow-y-auto pr-1">
            {payslipLoading ? (
              <p className="text-sm text-[#6B7280]">Generating payslip...</p>
            ) : payslip ? (
              <div className="grid gap-6 lg:grid-cols-[1fr_280px]">
                <div className="space-y-4">
                  <div className="rounded-2xl border border-emerald-100 bg-[#F0FDF4] px-4 py-3">
                    <p className="text-xs font-medium text-[#166534]">
                      Final Net Pay
                    </p>
                    <p className="text-xl font-bold text-emerald-700">
                      {moneyOrPending(
                        payslip.final_net_pay ?? payslip.net_pay,
                        isUnfinalizedPending(payslip)
                      )}
                    </p>
                  </div>
                  <PayslipPreview
                    businessName={businessName}
                    businessLogo={businessLogo}
                    payslip={payslip}
                    settings={payslipSettings}
                    sample={isDemo}
                  />
                  <HistoricalRateResolvePanel
                    payslip={payslip}
                    canEdit={Boolean(canEditPayslip && !isFinalized)}
                    onResolved={refreshPayroll}
                  />
                  <PayrollAdjustmentsPanel
                    payslip={payslip}
                    canEdit={Boolean(canEditPayslip && payslip.adjustments_editable)}
                    deductionTypes={adjustmentTypes?.deduction_types ?? []}
                    allowanceTypes={adjustmentTypes?.allowance_types ?? []}
                    showForm={showAdjustmentForm}
                    editing={editingAdjustment}
                    asOf={asOf}
                    onShowForm={(open) => {
                      setShowAdjustmentForm(open);
                      if (!open) setEditingAdjustment(null);
                    }}
                    onEdit={(item) => {
                      setEditingAdjustment(item);
                      setShowAdjustmentForm(true);
                    }}
                    onChanged={refreshPayroll}
                  />
                </div>
                {canEditPayslip && (
                  <PayslipEditor
                    settings={payslipSettings}
                    onChange={setPayslipSettings}
                  />
                )}
              </div>
            ) : (
              <p className="text-sm text-[#6B7280]">Payslip not found.</p>
            )}
          </div>
          <DialogFooter className="border-t border-slate-100 pt-4">
            <Button variant="outline" onClick={() => setSelectedEmployeeId(null)}>
              Close
            </Button>
            <Button
              className="gap-2 text-white"
              style={{ backgroundColor: themeButtonColor }}
              disabled={!payslip}
              onClick={() => {
                if (!payslip) return;
                void downloadStandardPayslipPdf({
                  payslip,
                  businessName,
                  sample: isDemo,
                }).catch(() => {
                  toast.error("Unable to download payslip PDF.");
                });
              }}
              onMouseEnter={(event) => {
                event.currentTarget.style.backgroundColor = themeButtonHoverColor;
              }}
              onMouseLeave={(event) => {
                event.currentTarget.style.backgroundColor = themeButtonColor;
              }}
            >
              <Download className="h-4 w-4" />
              Download PDF
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
      <Dialog open={unfinalizeOpen} onOpenChange={setUnfinalizeOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Unfinalize Payroll?</DialogTitle>
          </DialogHeader>
          <p className="text-sm leading-6 text-[#4B5563]">
            This will reopen the payroll period and allow attendance and payroll
            calculations to be recalculated using the current records. The
            current finalized payslips will no longer be treated as final.
          </p>
          <DialogFooter className="border-t border-slate-100 pt-4">
            <Button
              variant="outline"
              onClick={() => setUnfinalizeOpen(false)}
              disabled={unfinalizeMutation.isPending}
            >
              Cancel
            </Button>
            <Button
              disabled={unfinalizeMutation.isPending}
              onClick={() => unfinalizeMutation.mutate()}
            >
              {unfinalizeMutation.isPending
                ? "Reopeningâ€¦"
                : "Unfinalize Payroll"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </OwnerPage>
  );
}

function Row({ label, value, strong = false }: { label: string; value: string; strong?: boolean }) {
  return (
    <div className="flex items-center justify-between gap-3 border-b border-slate-100 py-1.5 last:border-b-0">
      <span className="text-[#6B7280]">{label}</span>
      <span
        className={
          strong
            ? "font-semibold text-emerald-700"
            : "font-medium text-[#1F2937]"
        }
      >
        {value}
      </span>
    </div>
  );
}

type PayslipSettings = {
  title: string;
  employeeSection: string;
  earningsSection: string;
  deductionsSection: string;
  netPaySection: string;
  notes: string;
  headerColor: string;
  earningsColor: string;
  deductionsColor: string;
  netColor: string;
};

function PayslipPreview({
  payslip,
  businessName,
  businessLogo,
  settings,
  sample = false,
}: {
  payslip: EmployeePayslip;
  businessName: string;
  businessLogo: string | null;
  settings: PayslipSettings;
  sample?: boolean;
}) {
  return (
    <div className="mx-auto max-w-md rounded-2xl border border-slate-200 bg-white p-6 text-sm shadow-sm">
      {sample ? (
        <div className="mb-4 rounded-xl border border-orange-200 bg-orange-50 px-3 py-2 text-center">
          <p className="text-xs font-bold tracking-wide text-orange-900">
            {PAYSLIP_SAMPLE_LINE_1}
          </p>
          <p className="text-[11px] font-semibold text-orange-800">
            {PAYSLIP_SAMPLE_LINE_2}
          </p>
        </div>
      ) : null}
      <div
        className="mx-auto mb-4 w-44 rounded-full py-2 text-center text-sm font-semibold text-[#374151]"
        style={{ backgroundColor: settings.headerColor }}
      >
        {settings.title}
      </div>
      {businessLogo && (
        <img
          className="mx-auto mb-3 h-14 w-14 rounded-full object-cover ring-1 ring-slate-200"
          src={businessLogo}
          alt={`${businessName} logo`}
        />
      )}
      <h2 className="border-b border-slate-400 pb-1 text-center text-sm font-semibold">
        {businessName}
      </h2>
      <p className="mt-1 text-center text-xs text-[#6B7280]">Business Name</p>

      <Section title={settings.employeeSection}>
        <Row label="Employee Name" value={payslip.employee_name} />
        <Row label="No. of Working Days" value={`${payslip.worked_days}`} />
        <Row label="Period Date" value={`${payslip.period_start} to ${payslip.period_end}`} />
        <Row label="Position" value={payslip.position_title ?? "Employee"} />
        <Row label="Employment Type" value={payslip.employment_type.replace("_", "-")} />
      </Section>

      {(payslip.pending_attendance_count ?? 0) > 0 ? (
        <p className="mb-3 rounded-lg bg-amber-50 px-3 py-2 text-xs text-amber-800">
          Payroll Status: Pending. Open attendance is not finalized until Time
          Out is recorded.
        </p>
      ) : null}
      {payslip.has_unresolved_historical_rate ? (
        <p className="mb-3 rounded-lg bg-amber-50 px-3 py-2 text-xs text-amber-800">
          Historical rate required for{" "}
          {payslip.unresolved_historical_rate_count ?? 1} completed day
          {(payslip.unresolved_historical_rate_count ?? 1) === 1 ? "" : "s"}.
          Totals exclude unresolved days until an Owner sets the historical
          rate.
        </p>
      ) : null}

      <Section title={settings.earningsSection} color={settings.earningsColor}>
        <Row label={salaryRateLabel()} value={formatSalaryRate(payslip)} />
        <Row
          label="Hours Worked"
          value={hoursLabel(
            payslip.hours_worked,
            isUnfinalizedPending(payslip)
          )}
        />
        <Row
          label="Overtime Hours"
          value={overtimeHoursLabel({
            overtime_hours: payslip.overtime_hours,
            overtime_minutes: payslip.overtime_minutes,
            pending: isUnfinalizedPending(payslip),
          })}
        />
        <Row
          label="Basic Salary"
          value={moneyOrPending(
            payslip.regular_pay ?? 0,
            isUnfinalizedPending(payslip)
          )}
        />
        <Row
          label="Leave Pay"
          value={moneyOrPending(
            payslip.leave_pay ?? 0,
            isUnfinalizedPending(payslip)
          )}
        />
        <Row
          label={
            payslip.overtime_minutes || payslip.worked_overtime_minutes
              ? `Overtime (${Number(
                  payslip.payable_overtime_minutes ??
                    payslip.overtime_minutes ??
                    0
                ).toFixed(0)} min × ₱${Number(
                  payslip.overtime_per_minute ?? 0
                ).toFixed(2)})`
              : "Overtime"
          }
          value={moneyOrPending(
            payslip.overtime_pay,
            isUnfinalizedPending(payslip)
          )}
        />
        {(payslip.pending_overtime_minutes ?? 0) > 0 && (
          <Row
            label="OT pending approval"
            value={`${Number(payslip.pending_overtime_minutes).toFixed(0)} min (worked, not paid yet)`}
          />
        )}
        {(payslip.rejected_overtime_minutes ?? 0) > 0 && (
          <Row
            label="OT rejected"
            value={`${Number(payslip.rejected_overtime_minutes).toFixed(0)} min (worked, not paid)`}
          />
        )}
        {payslip.attendance_records
          ?.filter((row) => row.ot && (row.ot.worked_ot_minutes ?? 0) > 0)
          .map((row) => {
            const ot = row.ot!;
            return (
              <div
                key={`ot-${row.date}-${row.time_out ?? "out"}`}
                className="rounded-lg border border-slate-100 bg-slate-50/80 px-3 py-2 text-[11px] text-[#4B5563]"
              >
                <p className="font-medium text-[#111827]">
                  {row.date}
                  {ot.ot_approval_status
                    ? ` · ${ot.ot_approval_status}`
                    : ""}
                </p>
                <p className="mt-0.5">
                  Scheduled end{" "}
                  {ot.scheduled_end
                    ? new Date(ot.scheduled_end).toLocaleTimeString([], {
                        hour: "numeric",
                        minute: "2-digit",
                      })
                    : "--:--"}{" "}
                  · Time Out{" "}
                  {ot.time_out
                    ? new Date(ot.time_out).toLocaleTimeString([], {
                        hour: "numeric",
                        minute: "2-digit",
                      })
                    : "--:--"}
                </p>
                <p className="mt-0.5">
                  Worked OT {Number(ot.worked_ot_minutes ?? 0).toFixed(0)} min
                  {(ot.time_recovered_minutes ?? 0) > 0
                    ? ` · Recovered ${Number(ot.time_recovered_minutes).toFixed(0)} min`
                    : ""}{" "}
                  · Payable {Number(ot.payable_ot_minutes ?? 0).toFixed(0)} min ×
                  ₱{Number(ot.ot_rate_per_minute ?? 0).toFixed(2)}
                  {(ot.holiday_ot_premium_percent ?? 0) > 0
                    ? ` · Holiday OT premium ${Number(
                        ot.holiday_ot_premium_percent
                      ).toFixed(0)}%`
                    : ""}{" "}
                  = {money(ot.overtime_pay ?? 0)}
                </p>
              </div>
            );
          })}
        <Row label="Holiday Pay" value={money(payslip.holiday_pay)} />
        <Row
          label={`Rest Day Premium${
            payslip.rest_day_premium_percent
              ? ` (${payslip.rest_day_premium_percent}%)`
              : ""
          }`}
          value={money(payslip.rest_day_pay ?? 0)}
        />
        <Row
          label="Total Earnings"
          value={moneyOrPending(payslip.gross_pay, isUnfinalizedPending(payslip))}
          strong
        />
      </Section>

      {(payslip.rest_day_records?.length ?? 0) > 0 && (
        <Section title="Rest Day Work" color="#DBEAFE">
          <Row
            label="Rest day"
            value={
              payslip.rest_day_name
                ? payslip.rest_day_name.charAt(0).toUpperCase() +
                  payslip.rest_day_name.slice(1)
                : "Owner-approved rest day work"
            }
          />
          <Row label="Days worked" value={`${payslip.rest_day_days ?? 0}`} />
          {payslip.rest_day_records?.map((record) => (
            <div
              key={`${record.date}-${record.time_in ?? "in"}`}
              className="rounded-lg border border-sky-100 bg-sky-50/70 px-3 py-2 text-xs text-[#374151]"
            >
              <div className="flex items-center justify-between gap-2">
                <span className="font-medium">
                  {record.date}
                  {record.weekday
                    ? ` Â· ${record.weekday.charAt(0).toUpperCase()}${record.weekday.slice(1)}`
                    : ""}
                  {record.authorized === false && (
                    <span className="ml-2 rounded-full bg-amber-100 px-2 py-0.5 text-[10px] font-semibold text-amber-800">
                      Not permitted
                    </span>
                  )}
                </span>
                <span className="font-semibold text-sky-800">
                  {money(record.premium_pay)}
                </span>
              </div>
              <p className="mt-1 text-[#6B7280]">
                In{" "}
                {record.time_in
                  ? new Date(record.time_in).toLocaleTimeString([], {
                      hour: "numeric",
                      minute: "2-digit",
                    })
                  : "--:--"}{" "}
                Â· Out{" "}
                {record.time_out
                  ? new Date(record.time_out).toLocaleTimeString([], {
                      hour: "numeric",
                      minute: "2-digit",
                    })
                  : "--:--"}
                {record.shift_name ? ` Â· ${record.shift_name}` : ""}
              </p>
            </div>
          ))}
        </Section>
      )}

      <Section title={settings.deductionsSection} color={settings.deductionsColor}>
        <Row
          label={
            payslip.late_minutes
              ? `Late (${Number(payslip.late_minutes).toFixed(0)} min × ₱${Number(
                  payslip.late_deduction_per_minute ?? 0
                ).toFixed(2)})`
              : "Late Deduction"
          }
          value={moneyOrPending(
            payslip.late_deductions ?? 0,
            isUnfinalizedPending(payslip)
          )}
        />
        <Row
          label={
            payslip.undertime_minutes
              ? (() => {
                  const mins = Number(payslip.undertime_minutes);
                  const amt = Number(payslip.undertime_deductions ?? 0);
                  const rate = mins > 0 ? amt / mins : 0;
                  return `Undertime (${mins.toFixed(0)} min × ₱${rate.toFixed(2)})`;
                })()
              : "Undertime Deduction"
          }
          value={moneyOrPending(
            payslip.undertime_deductions ?? 0,
            isUnfinalizedPending(payslip)
          )}
        />
        <Row
          label="Attendance Deduction Total"
          value={moneyOrPending(payslip.deductions, isUnfinalizedPending(payslip))}
        />
        <Row label="Absent Days" value={`${payslip.absent_days}`} />
        <Row
          label="Paid Leave"
          value={`${payslip.paid_leave_days ?? 0} day${
            (payslip.paid_leave_days ?? 0) === 1 ? "" : "s"
          }`}
        />
        <Row
          label="Unpaid Leave"
          value={`${payslip.unpaid_leave_days ?? 0} day${
            (payslip.unpaid_leave_days ?? 0) === 1 ? "" : "s"
          }`}
        />
      </Section>

      <Section title="Payroll Adjustments" color="#FDE68A">
        {(payslip.payroll_adjustments?.length ?? 0) === 0 ? (
          <p className="text-xs text-[#6B7280]">No payroll adjustments for this period.</p>
        ) : (
          payslip.payroll_adjustments!.map((item) => (
            <div key={item.id} className="space-y-1 border-b border-slate-100 pb-2 last:border-b-0">
              <Row
                label={`${item.display_name}${item.kind === "allowance" ? " (+)" : " (âˆ’)"}`}
                value={money(item.amount)}
              />
              {item.description ? (
                <p className="text-[11px] text-[#6B7280]">{item.description}</p>
              ) : null}
              {item.created_at ? (
                <p className="text-[11px] text-[#9CA3AF]">
                  Added {new Date(item.created_at).toLocaleDateString()}
                </p>
              ) : null}
            </div>
          ))
        )}
      </Section>

      <Section title={settings.netPaySection} color={settings.netColor}>
        <Row
          label="Base Net Pay"
          value={moneyOrPending(
            payslip.base_net_pay ?? payslip.net_pay,
            isUnfinalizedPending(payslip)
          )}
        />
        <Row
          label="Final Net Pay"
          value={moneyOrPending(
            payslip.final_net_pay ?? payslip.net_pay,
            isUnfinalizedPending(payslip)
          )}
          strong
        />
      </Section>
      {settings.notes && (
        <p className="mt-3 text-xs italic text-[#6B7280]">{settings.notes}</p>
      )}
    </div>
  );
}

function PayrollAdjustmentsPanel({
  payslip,
  canEdit,
  deductionTypes,
  allowanceTypes,
  showForm,
  editing,
  asOf,
  onShowForm,
  onEdit,
  onChanged,
}: {
  payslip: EmployeePayslip;
  canEdit: boolean;
  deductionTypes: { key: string; label: string }[];
  allowanceTypes: { key: string; label: string }[];
  showForm: boolean;
  editing: PayrollAdjustment | null;
  asOf: string;
  onShowForm: (open: boolean) => void;
  onEdit: (item: PayrollAdjustment) => void;
  onChanged: () => Promise<void>;
}) {
  const [kind, setKind] = useState<"deduction" | "allowance">("deduction");
  const [typeKey, setTypeKey] = useState("broken_equipment");
  const [customName, setCustomName] = useState("");
  const [description, setDescription] = useState("");
  const [amount, setAmount] = useState("");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!showForm) return;
    if (editing) {
      setKind((editing.kind as "deduction" | "allowance") || "deduction");
      setTypeKey(editing.type_key);
      setCustomName(editing.custom_name || "");
      setDescription(editing.description || "");
      setAmount(String(editing.amount));
      return;
    }
    setKind("deduction");
    setTypeKey(deductionTypes[0]?.key || "broken_equipment");
    setCustomName("");
    setDescription("");
    setAmount("");
  }, [showForm, editing, deductionTypes]);

  const typeOptions = kind === "deduction" ? deductionTypes : allowanceTypes;

  const saveMutation = useMutation({
    mutationFn: async () => {
      const parsed = Number(amount);
      if (!typeKey.trim()) throw new Error("Deduction type is required.");
      if (!(parsed > 0)) throw new Error("Amount must be greater than zero.");
      if (typeKey === "other" && !customName.trim()) {
        throw new Error("Enter a custom name for Other.");
      }
      const payload = {
        kind,
        type_key: typeKey,
        custom_name: typeKey === "other" ? customName.trim() : null,
        description: description.trim() || null,
        amount: parsed,
      };
      if (editing) {
        return updatePayrollAdjustment(editing.id, payload);
      }
      return createPayrollAdjustment(payslip.employee_id, payload, asOf);
    },
    onSuccess: async () => {
      setError(null);
      onShowForm(false);
      await onChanged();
    },
    onError: (err: unknown) => {
      const message =
        (err as { response?: { data?: { detail?: string } }; message?: string })
          ?.response?.data?.detail ||
        (err as { message?: string })?.message ||
        "Unable to save adjustment.";
      setError(String(message));
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deletePayrollAdjustment(id),
    onSuccess: async () => {
      await onChanged();
    },
  });

  return (
    <section className="owner-panel p-4">
      <div className="flex items-center justify-between gap-3">
        <div>
          <h3 className="text-sm font-semibold text-[#1F2937]">Payroll Adjustments</h3>
          <p className="text-xs text-[#6B7280]">
            Applied after attendance payroll. Final net pay updates automatically.
          </p>
        </div>
        {canEdit && (
          <Button
            size="sm"
            className="gap-1"
            onClick={() => {
              setKind("deduction");
              setTypeKey(deductionTypes[0]?.key || "broken_equipment");
              setCustomName("");
              setDescription("");
              setAmount("");
              setError(null);
              onShowForm(true);
            }}
          >
            <Plus className="h-4 w-4" />
            Add Deduction
          </Button>
        )}
      </div>

      <div className="mt-3 space-y-2">
        {(payslip.payroll_adjustments?.length ?? 0) === 0 ? (
          <p className="text-xs text-[#6B7280]">No adjustments yet.</p>
        ) : (
          payslip.payroll_adjustments!.map((item) => (
            <div
              key={item.id}
              className="flex items-start justify-between gap-3 rounded-xl border border-slate-100 px-3 py-2"
            >
              <div>
                <p className="text-sm font-medium text-[#1F2937]">
                  {item.display_name}{" "}
                  <span className="text-xs text-[#6B7280]">
                    ({item.kind === "allowance" ? "Allowance" : "Deduction"})
                  </span>
                </p>
                {item.description ? (
                  <p className="text-xs text-[#6B7280]">{item.description}</p>
                ) : null}
                <p className="text-sm font-semibold text-[#1F2937]">
                  {money(item.amount)}
                </p>
              </div>
              {canEdit && (
                <div className="flex gap-1">
                  <Button
                    size="icon"
                    variant="ghost"
                    onClick={() => {
                      setKind((item.kind as "deduction" | "allowance") || "deduction");
                      setTypeKey(item.type_key);
                      setCustomName(item.custom_name || "");
                      setDescription(item.description || "");
                      setAmount(String(item.amount));
                      setError(null);
                      onEdit(item);
                    }}
                  >
                    <Pencil className="h-4 w-4" />
                  </Button>
                  <Button
                    size="icon"
                    variant="ghost"
                    onClick={() => deleteMutation.mutate(item.id)}
                  >
                    <Trash2 className="h-4 w-4 text-red-600" />
                  </Button>
                </div>
              )}
            </div>
          ))
        )}
      </div>

      {!canEdit && (
        <p className="mt-3 text-xs text-amber-700">
          This pay period has ended. Payroll adjustments are read-only.
        </p>
      )}

      {showForm && canEdit && (
        <div className="mt-4 space-y-3 rounded-xl border border-slate-200 bg-[#FAFBFC] p-3">
          <div className="grid gap-3 sm:grid-cols-2">
            <label className="text-xs font-medium text-[#6B7280]">
              Kind
              <select
                className="mt-1 h-9 w-full rounded-md border border-slate-200 bg-white px-2 text-sm"
                value={kind}
                onChange={(e) => {
                  const next = e.target.value as "deduction" | "allowance";
                  setKind(next);
                  const options = next === "deduction" ? deductionTypes : allowanceTypes;
                  setTypeKey(options[0]?.key || "other");
                }}
              >
                <option value="deduction">Deduction</option>
                <option value="allowance">Allowance</option>
              </select>
            </label>
            <label className="text-xs font-medium text-[#6B7280]">
              Type
              <select
                className="mt-1 h-9 w-full rounded-md border border-slate-200 bg-white px-2 text-sm"
                value={typeKey}
                onChange={(e) => setTypeKey(e.target.value)}
              >
                {typeOptions.map((option) => (
                  <option key={option.key} value={option.key}>
                    {option.label}
                  </option>
                ))}
              </select>
            </label>
          </div>
          {typeKey === "other" && (
            <label className="block text-xs font-medium text-[#6B7280]">
              Custom name
              <Input
                className="mt-1 h-9 bg-white"
                value={customName}
                onChange={(e) => setCustomName(e.target.value)}
                placeholder="e.g. Lost company property"
              />
            </label>
          )}
          <label className="block text-xs font-medium text-[#6B7280]">
            Description (optional)
            <Input
              className="mt-1 h-9 bg-white"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
            />
          </label>
          <label className="block text-xs font-medium text-[#6B7280]">
            Amount
            <Input
              className="mt-1 h-9 bg-white"
              type="number"
              min="0.01"
              step="0.01"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
            />
          </label>
          {error ? <p className="text-xs text-red-600">{error}</p> : null}
          <div className="flex justify-end gap-2">
            <Button variant="outline" size="sm" onClick={() => onShowForm(false)}>
              Cancel
            </Button>
            <Button
              size="sm"
              disabled={saveMutation.isPending}
              onClick={() => saveMutation.mutate()}
            >
              {editing ? "Save Changes" : "Add Adjustment"}
            </Button>
          </div>
        </div>
      )}
    </section>
  );
}

function Section({
  title,
  children,
  color,
}: {
  title: string;
  children: React.ReactNode;
  color?: string;
}) {
  return (
    <div className="mt-4">
      <div
        className="px-2 py-1 text-xs font-semibold text-[#1F2937]"
        style={{ backgroundColor: color ?? "#E5E7EB" }}
      >
        {title}
      </div>
      <div className="mt-2 space-y-2">{children}</div>
    </div>
  );
}

function PayslipEditor({
  settings,
  onChange,
}: {
  settings: PayslipSettings;
  onChange: (settings: PayslipSettings) => void;
}) {
  function update<K extends keyof PayslipSettings>(
    key: K,
    value: PayslipSettings[K]
  ) {
    onChange({ ...settings, [key]: value });
  }

  return (
    <aside className="owner-panel-muted p-4">
      <h3 className="text-sm font-semibold text-[#1F2937]">Edit Payslip</h3>
      <p className="mt-1 text-xs text-[#6B7280]">
        Owners can customize labels, notes, and colors. Payroll values remain
        tied to live employee records.
      </p>
      <div className="mt-4 space-y-3">
        <EditorField label="Title" value={settings.title} onChange={(value) => update("title", value)} />
        <EditorField label="Employee Section" value={settings.employeeSection} onChange={(value) => update("employeeSection", value)} />
        <EditorField label="Earnings Section" value={settings.earningsSection} onChange={(value) => update("earningsSection", value)} />
        <EditorField label="Deductions Section" value={settings.deductionsSection} onChange={(value) => update("deductionsSection", value)} />
        <EditorField label="Net Pay Section" value={settings.netPaySection} onChange={(value) => update("netPaySection", value)} />
        <EditorField label="Notes" value={settings.notes} onChange={(value) => update("notes", value)} />
        <ColorField label="Header" value={settings.headerColor} onChange={(value) => update("headerColor", value)} />
        <ColorField label="Earnings" value={settings.earningsColor} onChange={(value) => update("earningsColor", value)} />
        <ColorField label="Deductions" value={settings.deductionsColor} onChange={(value) => update("deductionsColor", value)} />
        <ColorField label="Net Pay" value={settings.netColor} onChange={(value) => update("netColor", value)} />
      </div>
    </aside>
  );
}

function EditorField({
  label,
  value,
  onChange,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
}) {
  return (
    <label className="block text-xs font-medium text-[#6B7280]">
      {label}
      <Input
        className="mt-1 h-9 bg-white text-sm"
        value={value}
        onChange={(event) => onChange(event.target.value)}
      />
    </label>
  );
}

function ColorField({
  label,
  value,
  onChange,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
}) {
  return (
    <label className="flex items-center justify-between text-xs font-medium text-[#6B7280]">
      {label}
      <input
        className="h-8 w-10 rounded border border-slate-200 bg-white"
        type="color"
        value={value}
        onChange={(event) => onChange(event.target.value)}
      />
    </label>
  );
}

function HistoricalRateResolvePanel({
  payslip,
  canEdit,
  onResolved,
}: {
  payslip: EmployeePayslip;
  canEdit: boolean;
  onResolved: () => Promise<void> | void;
}) {
  const unresolved = (payslip.attendance_records ?? []).filter(
    (row) => row.historical_rate_required && row.attendance_record_id
  );
  const [activeId, setActiveId] = useState<string | null>(null);
  const [payBasis, setPayBasis] = useState<PayBasis>("daily");
  const [rate, setRate] = useState("");
  const [error, setError] = useState<string | null>(null);

  const mutation = useMutation({
    mutationFn: async () => {
      if (!activeId) throw new Error("No attendance selected");
      const amount = Number(rate);
      if (!Number.isFinite(amount) || amount <= 0) {
        throw new Error("Enter a positive rate.");
      }
      const payload: {
        pay_basis: PayBasis;
        daily_rate?: number;
        hourly_rate?: number;
        monthly_salary?: number;
      } = { pay_basis: payBasis };
      if (payBasis === "daily") payload.daily_rate = amount;
      else if (payBasis === "hourly") payload.hourly_rate = amount;
      else payload.monthly_salary = amount;
      return resolveOwnerHistoricalRate(activeId, payload);
    },
    onSuccess: async () => {
      toast.success("Historical pay rate saved.");
      setActiveId(null);
      setRate("");
      setError(null);
      await onResolved();
    },
    onError: (err) => {
      const detail =
        err &&
        typeof err === "object" &&
        "response" in err &&
        (err as { response?: { data?: { detail?: unknown } } }).response?.data
          ?.detail;
      if (typeof detail === "string") setError(detail);
      else if (err instanceof Error) setError(err.message);
      else setError("Could not save historical rate.");
    },
  });

  if (unresolved.length === 0) return null;

  return (
    <section className="rounded-2xl border border-amber-200 bg-amber-50/60 p-4">
      <h3 className="text-sm font-semibold text-amber-950">
        Unresolved historical pay rate
      </h3>
      <p className="mt-1 text-xs text-amber-900">
        These completed days have no recorded rate from clock-out. Do not use
        the employee&apos;s current rate. Enter the historical rate that applied
        when the work was completed.
      </p>
      <div className="mt-3 space-y-2">
        {unresolved.map((row) => (
          <div
            key={row.attendance_record_id}
            className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-amber-100 bg-white px-3 py-2"
          >
            <div>
              <p className="text-sm font-semibold text-[#111827]">{row.date}</p>
              <p className="text-xs text-[#6B7280]">
                Earned: unresolved · Rate: not recorded
              </p>
            </div>
            {canEdit ? (
              <Button
                size="sm"
                variant="outline"
                onClick={() => {
                  setActiveId(row.attendance_record_id!);
                  setPayBasis("daily");
                  setRate("");
                  setError(null);
                }}
              >
                Resolve rate
              </Button>
            ) : null}
          </div>
        ))}
      </div>

      <Dialog
        open={Boolean(activeId)}
        onOpenChange={(open) => {
          if (!open) {
            setActiveId(null);
            setError(null);
          }
        }}
      >
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Set historical pay rate</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-[#6B7280]">
            This stamps the completed attendance only. Later Role or rate
            changes will not overwrite it.
          </p>
          <label className="mt-3 block text-xs font-medium text-[#6B7280]">
            Pay basis
            <select
              className="mt-1 h-10 w-full rounded-md border border-slate-200 bg-white px-3 text-sm"
              value={payBasis}
              onChange={(e) => setPayBasis(e.target.value as PayBasis)}
            >
              <option value="daily">Daily</option>
              <option value="hourly">Hourly</option>
              <option value="monthly">Monthly</option>
            </select>
          </label>
          <label className="mt-3 block text-xs font-medium text-[#6B7280]">
            {payBasis === "hourly"
              ? "Hourly rate"
              : payBasis === "monthly"
                ? "Monthly salary"
                : "Daily rate"}
            <Input
              className="mt-1"
              type="number"
              min="0"
              step="0.01"
              value={rate}
              onChange={(e) => setRate(e.target.value)}
              placeholder="e.g. 500"
            />
          </label>
          {error ? (
            <p className="mt-2 text-xs font-medium text-red-700">{error}</p>
          ) : null}
          <DialogFooter className="mt-4">
            <Button
              variant="outline"
              onClick={() => setActiveId(null)}
              disabled={mutation.isPending}
            >
              Cancel
            </Button>
            <Button
              onClick={() => mutation.mutate()}
              disabled={mutation.isPending || !rate}
            >
              {mutation.isPending ? "Saving…" : "Confirm historical rate"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </section>
  );
}

