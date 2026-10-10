import { useMemo, useState, type Dispatch, type SetStateAction } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ChevronDown, ChevronUp, History, Search } from "lucide-react";
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
  OwnerCard,
  OwnerPage,
  OwnerPageBackLink,
  OwnerPageContent,
  OwnerPageHeader,
} from "@/components/owner/layout/OwnerPageLayout";
import {
  getOwnerShiftHistory,
  resolveOwnerDailyWorkdayRate,
  resolveOwnerHistoricalRate,
  type OwnerShiftHistoryItem,
  type PayBasis,
} from "@/lib/api";
import { formatAttendanceTime } from "@/lib/attendanceTime";
import {
  buildEmployeeDayBlocks,
  displayedShiftNet,
  dateLevelAdditionalPay,
  dateLevelPay,
  historyDayTotal,
  presentShiftPay,
  shiftHistoryStatusLabel,
  shiftIndexLabel,
} from "@/lib/shiftHistoryGrouping";
import {
  buildAdditionalPayLines,
  buildDeductionLines,
} from "@/lib/shiftHistoryPayBreakdown";
import { useTenantMode } from "@/lib/tenantMode";

function todayIso() {
  const now = new Date();
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, "0");
  const d = String(now.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

function money(value: number | null | undefined) {
  if (value == null || Number.isNaN(Number(value))) return "—";
  return new Intl.NumberFormat("en-PH", {
    style: "currency",
    currency: "PHP",
  }).format(Number(value));
}

function formatHours(
  hoursValue: number | null | undefined,
  minutesValue?: number | null
) {
  const minutes =
    minutesValue != null && Number.isFinite(Number(minutesValue))
      ? Math.round(Number(minutesValue))
      : Math.round(Number(hoursValue ?? 0) * 60);
  if (!Number.isFinite(minutes) || minutes <= 0) return "0h";
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (m === 0) return `${h}h`;
  return `${h}h ${String(m).padStart(2, "0")}m`;
}

function formatPeriod(start?: string, end?: string) {
  if (!start || !end) return "Current pay period";
  const a = new Date(`${start}T00:00:00`);
  const b = new Date(`${end}T00:00:00`);
  if (Number.isNaN(a.getTime()) || Number.isNaN(b.getTime())) {
    return `${start} – ${end}`;
  }
  const opts: Intl.DateTimeFormatOptions = {
    month: "short",
    day: "numeric",
    year: "numeric",
  };
  return `${a.toLocaleDateString(undefined, opts)} – ${b.toLocaleDateString(undefined, opts)}`;
}

function formatDateHeading(iso: string) {
  const d = new Date(`${iso}T00:00:00`);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleDateString(undefined, {
    weekday: "short",
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

function statusLabel(status: string, payrollStatus?: string | null, item?: OwnerShiftHistoryItem) {
  return shiftHistoryStatusLabel({
    status,
    payroll_status: payrollStatus,
    earned: item?.earned,
    shift_net: item?.shift_net,
  });
}

function statusClass(status: string, payrollStatus?: string | null) {
  if (payrollStatus === "historical_rate_required") {
    return "bg-amber-50 text-amber-900";
  }
  if (status === "complete" || status === "holiday_paid") {
    return "bg-emerald-50 text-emerald-800";
  }
  if (status === "late") return "bg-amber-50 text-amber-800";
  if (status === "absent") return "bg-rose-50 text-rose-800";
  if (status === "incomplete" || status === "in_progress") {
    return "bg-blue-50 text-blue-800";
  }
  if (status === "on_leave") return "bg-violet-50 text-violet-800";
  return "bg-slate-100 text-slate-700";
}

function rowKey(item: OwnerShiftHistoryItem) {
  return `${item.employee_id}_${item.date}_${item.shift_name ?? ""}_${item.status}`;
}

function payBasisLabelFor(item: OwnerShiftHistoryItem) {
  if (item.pay_basis_used === "hourly") return "Hourly";
  if (item.pay_basis_used === "monthly") return "Monthly";
  if (item.pay_basis_used === "daily") return "Daily";
  return item.pay_basis_used || "—";
}

function rateLabelFor(item: OwnerShiftHistoryItem) {
  if (item.historical_rate_required) return "Historical rate required";
  if (item.rate_used != null && item.pay_basis_used) {
    const suffix =
      item.pay_basis_used === "hourly"
        ? "/hour"
        : item.pay_basis_used === "monthly"
          ? "/month"
          : "/day";
    return `${money(item.rate_used)}${suffix}`;
  }
  return "—";
}

function attendanceLabelFor(item: OwnerShiftHistoryItem) {
  if (item.status === "holiday_paid") return "Not Worked";
  if (item.status === "absent") return "Absent";
  if (item.status === "incomplete") return "Incomplete";
  if (item.status === "in_progress") return "In progress";
  if (item.status === "on_leave" || item.status === "late" || item.status === "complete") {
    if (item.status === "on_leave") {
      return statusLabel(item.status, item.payroll_status, item);
    }
    return "Worked";
  }
  if (item.time_in) return "Worked";
  return statusLabel(item.status, item.payroll_status, item);
}

export function OwnerShiftHistoryPage() {
  const { me } = useTenantMode();
  const queryClient = useQueryClient();
  const [asOf, setAsOf] = useState(todayIso());
  const [search, setSearch] = useState("");
  const [expanded, setExpanded] = useState<Record<string, boolean>>({});
  const [resolveItem, setResolveItem] = useState<OwnerShiftHistoryItem | null>(
    null
  );
  const [payBasis, setPayBasis] = useState<PayBasis>("daily");
  const [rate, setRate] = useState("");
  const [resolveError, setResolveError] = useState<string | null>(null);

  const { data, isLoading, isError, refetch, isFetching } = useQuery({
    queryKey: ["owner-shift-history", asOf],
    queryFn: () => getOwnerShiftHistory(asOf || undefined),
  });

  const resolveMutation = useMutation({
    mutationFn: async () => {
      if (!resolveItem) throw new Error("No attendance selected");
      const amount = Number(rate);
      if (!Number.isFinite(amount) || amount <= 0) {
        throw new Error("Enter a positive rate.");
      }
      if (resolveItem.daily_rate_conflict) {
        return resolveOwnerDailyWorkdayRate({
          employee_id: resolveItem.employee_id,
          work_date: resolveItem.date,
          daily_rate: amount,
        });
      }
      if (!resolveItem.attendance_record_id) {
        throw new Error("No attendance selected");
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
      return resolveOwnerHistoricalRate(
        resolveItem.attendance_record_id,
        payload
      );
    },
    onSuccess: async () => {
      toast.success("Historical pay rate saved.");
      setResolveItem(null);
      setRate("");
      setResolveError(null);
      await queryClient.invalidateQueries({ queryKey: ["owner-shift-history"] });
      await queryClient.invalidateQueries({ queryKey: ["owner-payroll-report"] });
    },
    onError: (err) => {
      const detail =
        err &&
        typeof err === "object" &&
        "response" in err &&
        (err as { response?: { data?: { detail?: unknown } } }).response?.data
          ?.detail;
      if (typeof detail === "string") setResolveError(detail);
      else if (err instanceof Error) setResolveError(err.message);
      else setResolveError("Could not save historical rate.");
    },
  });

  const timeZone = data?.timezone ?? me?.timezone;
  const canResolve =
    me?.role === "owner" || me?.role === "manager";

  const filtered = useMemo(() => {
    const needle = search.trim().toLowerCase();
    const items = data?.items ?? [];
    if (!needle) return items;
    return items.filter((item) => {
      return (
        item.employee_name.toLowerCase().includes(needle) ||
        item.status.toLowerCase().includes(needle) ||
        (item.shift_name ?? "").toLowerCase().includes(needle)
      );
    });
  }, [data?.items, search]);

  const grouped = useMemo(() => {
    const map = new Map<string, OwnerShiftHistoryItem[]>();
    for (const item of filtered) {
      const key = item.date || "Unknown";
      const list = map.get(key) ?? [];
      list.push(item);
      map.set(key, list);
    }
    return Array.from(map.entries());
  }, [filtered]);

  return (
    <OwnerPage>
      <OwnerPageHeader
        back={
          <OwnerPageBackLink to="/owner/attendance" label="Attendance" />
        }
        title="Shift History"
        description="Historical shift attendance and day earnings from the current pay period’s payroll records."
        actions={
          <Button
            type="button"
            variant="outline"
            onClick={() => void refetch()}
            disabled={isFetching}
            className="rounded-xl"
          >
            Refresh
          </Button>
        }
      />

      <OwnerPageContent>
        {/* Cohesive filter toolbar — same Pay Period + Search behavior */}
        <section className="owner-toolbar">
          <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between lg:gap-6">
            <div className="flex min-w-0 flex-1 flex-col gap-3 sm:flex-row sm:items-end sm:gap-4">
              <label className="flex w-full min-w-[180px] max-w-[220px] flex-col gap-1.5 text-xs font-medium text-[#6B7280]">
                Pay period
                <Input
                  type="date"
                  value={asOf}
                  onChange={(e) => setAsOf(e.target.value)}
                  className="h-10 rounded-xl border-slate-200 bg-[#FAFBFC]"
                  aria-label="Pay period date"
                />
              </label>
              <div className="min-w-0 pb-0.5 sm:pb-2">
                <p className="truncate text-sm font-semibold text-[#111827]">
                  {formatPeriod(data?.period_start, data?.period_end)}
                </p>
                <p className="mt-0.5 text-xs text-[#6B7280]">
                  Period resolved from the selected date
                </p>
              </div>
            </div>

            <div className="relative w-full lg:max-w-[280px]">
              <Search className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-[#9CA3AF]" />
              <Input
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Search employee, status, or shift"
                className="h-10 rounded-xl border-slate-200 bg-[#FAFBFC] pl-10"
                aria-label="Search shift history"
              />
            </div>
          </div>
        </section>

        {isLoading ? (
          <OwnerCard>
            <p className="text-sm text-[#6B7280]">Loading shift history…</p>
          </OwnerCard>
        ) : isError ? (
          <OwnerCard>
            <p className="text-sm text-[#6B7280]">
              Unable to load shift history. Please try again.
            </p>
            <Button className="mt-3" onClick={() => void refetch()}>
              Retry
            </Button>
          </OwnerCard>
        ) : grouped.length === 0 ? (
          <OwnerCard className="py-12 text-center">
            <History className="mx-auto h-9 w-9 text-[#9CA3AF]" />
            <p className="mt-3 text-sm font-semibold text-[#374151]">
              No shift history for this pay period.
            </p>
            <p className="mt-1 text-sm text-[#6B7280]">
              Choose another date to view a different pay period.
            </p>
          </OwnerCard>
        ) : (
          <div className="space-y-6">
            {grouped.map(([date, rows]) => (
              <section key={date} className="space-y-3">
                <h2 className="text-sm font-semibold text-[#6B7280]">
                  {formatDateHeading(date)}
                </h2>
                <div className="owner-card overflow-hidden">
                  <div className="hidden grid-cols-[minmax(0,1.4fr)_104px_minmax(0,1fr)_78px_110px_36px] gap-3 border-b border-[#E5E7EB] bg-[#F8FAFC] px-4 py-2.5 text-[11px] font-medium uppercase tracking-[0.08em] text-[#6B7280] lg:grid">
                    <span>Employee</span>
                    <span>Status</span>
                    <span>Time In → Time Out</span>
                    <span>Hours</span>
                    <span>Shift Total</span>
                    <span />
                  </div>
                  <div className="divide-y divide-[#EEF2F7]">
                    {buildEmployeeDayBlocks(rows).map((block) => {
                      if (block.kind === "multi") {
                        return (
                          <MultiShiftDayGroup
                            key={`multi-${block.items[0]!.employee_id}-${block.items[0]!.date}`}
                            items={block.items}
                            timeZone={timeZone}
                            expanded={expanded}
                            setExpanded={setExpanded}
                            canResolve={canResolve}
                            onResolve={(item) => {
                              setResolveItem(item);
                              setPayBasis(
                                item.daily_rate_conflict
                                  ? "daily"
                                  : ((item.pay_basis_used as PayBasis | null) ??
                                      "daily")
                              );
                              setRate("");
                              setResolveError(null);
                            }}
                          />
                        );
                      }
                      const item = block.item;
                      const key = rowKey(item);
                      const open = Boolean(expanded[key]);
                      const face = presentShiftPay(item, [item]);
                      const net = face.shiftTotal ?? displayedShiftNet(item);
                      const timeIn = formatAttendanceTime(
                        item.time_in ?? null,
                        timeZone
                      );
                      const timeOut = formatAttendanceTime(
                        item.time_out ?? null,
                        timeZone
                      );
                      const shownIn =
                        item.status === "holiday_paid"
                          ? formatAttendanceTime(item.scheduled_start ?? null, timeZone)
                          : timeIn;
                      const shownOut =
                        item.status === "holiday_paid"
                          ? formatAttendanceTime(item.scheduled_end ?? null, timeZone)
                          : timeOut;
                      return (
                        <div key={key}>
                          <button
                            type="button"
                            onClick={() =>
                              setExpanded((prev) => ({
                                ...prev,
                                [key]: !prev[key],
                              }))
                            }
                            className="grid w-full grid-cols-1 gap-3 px-4 py-3.5 text-left transition-colors hover:bg-[#F8FAFC] lg:grid-cols-[minmax(0,1.4fr)_104px_minmax(0,1fr)_78px_110px_36px] lg:items-center lg:gap-3"
                          >
                            <div className="min-w-0">
                              <div className="flex items-start justify-between gap-3">
                                <div className="min-w-0">
                                  <p className="truncate text-sm font-semibold text-[#111827]">
                                    {item.employee_name}
                                  </p>
                                  {item.shift_name ? (
                                    <p className="mt-0.5 truncate text-xs text-[#6B7280]">
                                      {item.shift_name}
                                    </p>
                                  ) : null}
                                  {item.holiday_name ? (
                                    <p className="mt-0.5 truncate text-xs font-medium text-[#0F766E]">
                                      {item.holiday_name}
                                    </p>
                                  ) : null}
                                </div>
                                <div className="flex shrink-0 items-center gap-2 lg:hidden">
                                  <span
                                    className={`inline-flex rounded-full px-2.5 py-1 text-[11px] font-semibold ${statusClass(item.status, item.payroll_status)}`}
                                  >
                                    {statusLabel(item.status, item.payroll_status, item)}
                                  </span>
                                  {open ? (
                                    <ChevronUp className="h-4 w-4 text-[#9CA3AF]" />
                                  ) : (
                                    <ChevronDown className="h-4 w-4 text-[#9CA3AF]" />
                                  )}
                                </div>
                              </div>
                              <div className="mt-3 rounded-xl bg-[#F8FAFC] px-3 py-2.5 lg:hidden">
                                <p className="text-sm font-semibold text-[#111827]">
                                  {shownIn}
                                  <span className="mx-1.5 font-medium text-[#9CA3AF]">
                                    →
                                  </span>
                                  {shownOut}
                                </p>
                                <div className="mt-1.5 flex items-center justify-between gap-3">
                                  <p className="text-sm font-semibold text-[#374151]">
                                    {formatHours(
                                      item.hours_worked,
                                      item.worked_minutes
                                    )}
                                  </p>
                                  <p className="text-sm font-bold text-emerald-700">
                                    {item.historical_rate_required
                                      ? "Unresolved"
                                      : money(net)}
                                  </p>
                                </div>
                              </div>
                            </div>
                            <div className="hidden lg:block">
                              <span
                                className={`inline-flex rounded-full px-2.5 py-1 text-[11px] font-semibold ${statusClass(item.status, item.payroll_status)}`}
                              >
                                {statusLabel(item.status, item.payroll_status, item)}
                              </span>
                            </div>
                            <p className="hidden text-sm font-semibold text-[#111827] lg:block">
                              {shownIn}
                              <span className="mx-1.5 font-medium text-[#9CA3AF]">
                                →
                              </span>
                              {shownOut}
                            </p>
                            <p className="hidden text-sm font-semibold text-[#374151] lg:block">
                              {formatHours(
                                item.hours_worked,
                                item.worked_minutes
                              )}
                            </p>
                            <p className="hidden text-sm font-bold text-emerald-700 lg:block">
                              {item.historical_rate_required
                                ? "Unresolved"
                                : money(net)}
                            </p>
                            <div className="hidden justify-end text-[#9CA3AF] lg:flex">
                              {open ? (
                                <ChevronUp className="h-4 w-4" />
                              ) : (
                                <ChevronDown className="h-4 w-4" />
                              )}
                            </div>
                          </button>
                          {open ? (
                            <div className="border-t border-[#EEF2F7] bg-[#FCFCFD] px-4 py-4 text-sm">
                              <ShiftDetailBands
                                item={item}
                                siblings={[item]}
                                timeZone={timeZone}
                                canResolve={canResolve}
                                onResolve={() => {
                                  setResolveItem(item);
                                  setPayBasis("daily");
                                  setRate("");
                                  setResolveError(null);
                                }}
                              />
                            </div>
                          ) : null}
                        </div>
                      );
                    })}
                  </div>
                </div>
              </section>
            ))}
          </div>
        )}
      </OwnerPageContent>

      <Dialog
        open={Boolean(resolveItem)}
        onOpenChange={(open) => {
          if (!open) {
            setResolveItem(null);
            setResolveError(null);
          }
        }}
      >
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Set historical pay rate</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-[#6B7280]">
            {resolveItem
              ? `${resolveItem.employee_name} · ${resolveItem.date}. `
              : ""}
            {resolveItem?.daily_rate_conflict
              ? "Multiple Daily shifts on this date have different historical rates. Choose one Daily rate for the workday. Hourly shifts on the same date are unchanged."
              : "Enter the rate that applied when this attendance was completed. The employee's current rate is not used."}
          </p>
          {resolveItem?.daily_rate_conflict ? (
            <p className="mt-2 text-xs font-medium text-amber-800">
              Pay basis is fixed to Daily for workday resolution.
            </p>
          ) : (
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
          )}
          <label className="mt-3 block text-xs font-medium text-[#6B7280]">
            {resolveItem?.daily_rate_conflict || payBasis === "daily"
              ? "Daily rate"
              : payBasis === "hourly"
                ? "Hourly rate"
                : "Monthly salary"}
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
          {resolveError ? (
            <p className="mt-2 text-xs font-medium text-red-700">
              {resolveError}
            </p>
          ) : null}
          <DialogFooter className="mt-4">
            <Button
              variant="outline"
              onClick={() => setResolveItem(null)}
              disabled={resolveMutation.isPending}
            >
              Cancel
            </Button>
            <Button
              onClick={() => resolveMutation.mutate()}
              disabled={resolveMutation.isPending || !rate}
            >
              {resolveMutation.isPending
                ? "Saving…"
                : "Confirm historical rate"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </OwnerPage>
  );
}

function ShiftDetailBands({
  item,
  siblings,
  timeZone,
  canResolve,
  onResolve,
}: {
  item: OwnerShiftHistoryItem;
  siblings: OwnerShiftHistoryItem[];
  timeZone?: string | null;
  canResolve: boolean;
  onResolve: () => void;
}) {
  const face = presentShiftPay(item, siblings);
  const total = face.shiftTotal ?? displayedShiftNet(item);
  const scheduled = `${formatAttendanceTime(item.scheduled_start ?? null, timeZone)} → ${formatAttendanceTime(item.scheduled_end ?? null, timeZone)}`;
  const timeIn = formatAttendanceTime(item.time_in ?? null, timeZone);
  const timeOut = formatAttendanceTime(item.time_out ?? null, timeZone);
  const additional = buildAdditionalPayLines({
    ...item,
    holiday_pay: face.holidayPay,
    rest_day_premium_pay: face.restPay,
    additional_pay: null,
  });
  const deductions = buildDeductionLines(item);
  const unresolved = Boolean(item.historical_rate_required);

  return (
    <div className="flex flex-col gap-5 md:flex-row md:items-start">
      <div className="hidden md:block md:w-44 md:shrink-0" aria-hidden="true" />

      <div className="min-w-0 flex-1 md:flex md:justify-center md:px-4">
        <div className="w-full max-w-md space-y-1.5">
          <h3 className="text-[11px] font-bold uppercase tracking-[0.08em] text-[#6B7280]">
            Shift summary
          </h3>
          <DetailRow label="Scheduled" value={scheduled} />
          <DetailRow label="Attendance" value={attendanceLabelFor(item)} />
          {item.status === "holiday_paid" ? null : (
            <DetailRow label="Time In → Out" value={`${timeIn} → ${timeOut}`} />
          )}
          <DetailRow
            label="Hours Worked"
            value={formatHours(item.hours_worked, item.worked_minutes)}
          />
          <DetailRow label="Pay Basis" value={payBasisLabelFor(item)} />
          <DetailRow label="Rate Used" value={rateLabelFor(item)} />
        </div>
      </div>

      <div className="w-full min-w-0 md:w-64 md:shrink-0 md:border-l md:border-[#EEF2F7] md:pl-5">
        <h3 className="text-[11px] font-bold uppercase tracking-[0.08em] text-[#6B7280]">
          Pay summary
        </h3>
        <div className="mt-1.5 space-y-1.5">
          {face.showEarned ? (
            <DetailRow
              label={face.baseLabel}
              value={unresolved ? "Unresolved" : money(face.earned)}
              valueClassName="text-emerald-700"
            />
          ) : null}
          {additional.map((line) => (
            <DetailRow
              key={line.key}
              label={line.label}
              value={line.amount > 0 ? money(line.amount) : "—"}
              valueClassName={line.amount > 0 ? "text-emerald-700" : undefined}
            />
          ))}
          {deductions.map((line) => (
            <DetailRow
              key={line.key}
              label={line.label}
              value={line.amount > 0 ? `−${money(line.amount)}` : "—"}
              valueClassName={line.amount > 0 ? "text-rose-700" : undefined}
            />
          ))}
          {face.hideShiftTotal ? null : (
            <div className="mt-1 flex items-center justify-between gap-4 border-t border-emerald-200 pt-2">
              <span className="text-[11px] font-extrabold uppercase tracking-[0.08em] text-emerald-900">
                Shift Total
              </span>
              <span className="text-base font-extrabold tabular-nums text-emerald-700">
                {unresolved ? "Unresolved" : money(total)}
              </span>
            </div>
          )}
          {unresolved ? (
            <DetailRow
              label={
                item.daily_rate_conflict
                  ? "Daily Rate Conflict"
                  : "Historical Rate Required"
              }
              value="Owner resolution needed"
              valueClassName="text-amber-800"
            />
          ) : null}
          {unresolved && canResolve ? (
            <div className="pt-1">
              <Button
                type="button"
                size="sm"
                variant="outline"
                className="rounded-lg"
                onClick={onResolve}
              >
                {item.daily_rate_conflict
                  ? "Resolve Daily rate for this day"
                  : "Resolve historical rate"}
              </Button>
            </div>
          ) : null}
        </div>
      </div>
    </div>
  );
}

function MultiShiftDayGroup({
  items,
  timeZone,
  expanded,
  setExpanded,
  canResolve,
  onResolve,
}: {
  items: OwnerShiftHistoryItem[];
  timeZone?: string | null;
  expanded: Record<string, boolean>;
  setExpanded: Dispatch<SetStateAction<Record<string, boolean>>>;
  canResolve: boolean;
  onResolve: (item: OwnerShiftHistoryItem) => void;
}) {
  const groupKey = `multi-${items[0]!.employee_id}_${items[0]!.date}`;
  const open = Boolean(expanded[groupKey]);
  const netSum = historyDayTotal(items, money);
  const finalLabel = netSum.unresolved
    ? "Unresolved"
    : netSum.total == null
      ? "—"
      : money(netSum.total);
  const equation = netSum.unresolved ? null : netSum.equation;
  const holidayName = items.find((item) => item.holiday_name)?.holiday_name;
  const datePay = dateLevelPay(items);
  const dateAdditionalPay = dateLevelAdditionalPay(items);

  return (
    <div>
      <button
        type="button"
        onClick={() =>
          setExpanded((prev) => ({
            ...prev,
            [groupKey]: !prev[groupKey],
          }))
        }
        className="grid w-full grid-cols-1 gap-3 px-4 py-3.5 text-left transition-colors hover:bg-[#F8FAFC] lg:grid-cols-[minmax(0,1.4fr)_104px_minmax(0,1fr)_78px_110px_36px] lg:items-center lg:gap-3"
      >
        <div className="min-w-0">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <p className="truncate text-sm font-semibold text-[#111827]">
                {items[0]!.employee_name}
              </p>
              <p className="mt-0.5 text-xs font-semibold text-[#4B5563]">
                {items.length} shifts on this date
              </p>
              {holidayName ? (
                <p className="mt-0.5 truncate text-xs font-medium text-[#0F766E]">
                  {holidayName}
                </p>
              ) : null}
              <p className="mt-0.5 truncate text-xs text-[#6B7280]">
                {items
                  .map((s, i) => shiftIndexLabel(i, s.shift_name))
                  .join(" · ")}
              </p>
            </div>
            <div className="flex shrink-0 items-center gap-2 lg:hidden">
              <span className="inline-flex rounded-full bg-slate-100 px-2.5 py-1 text-[11px] font-semibold text-slate-700">
                {items.length} Shifts
              </span>
              {open ? (
                <ChevronUp className="h-4 w-4 text-[#9CA3AF]" />
              ) : (
                <ChevronDown className="h-4 w-4 text-[#9CA3AF]" />
              )}
            </div>
          </div>
          <div className="mt-3 rounded-xl bg-[#F8FAFC] px-3 py-2.5 lg:hidden">
            <p className="text-[11px] font-bold uppercase tracking-[0.08em] text-[#6B7280]">
              Day Total
            </p>
            <p className="mt-1 text-sm font-bold text-emerald-700">{finalLabel}</p>
          </div>
        </div>
        <div className="hidden lg:block">
          <span className="inline-flex rounded-full bg-slate-100 px-2.5 py-1 text-[11px] font-semibold text-slate-700">
            {items.length} Shifts
          </span>
        </div>
        <p className="hidden text-sm font-semibold text-[#6B7280] lg:block">
          Same-day multi-shift
        </p>
        <p className="hidden text-sm font-semibold text-[#374151] lg:block">
          {items.length}
        </p>
        <p className="hidden text-sm font-bold text-emerald-700 lg:block">
          {finalLabel}
        </p>
        <div className="hidden justify-end text-[#9CA3AF] lg:flex">
          {open ? (
            <ChevronUp className="h-4 w-4" />
          ) : (
            <ChevronDown className="h-4 w-4" />
          )}
        </div>
      </button>
      {open ? (
        <div className="border-t border-[#EEF2F7] bg-[#FCFCFD] px-4 py-4 text-sm">
          <div className="space-y-4">
            {datePay?.dailyEntitlement != null ? (
              <div className="rounded-xl border border-[#E5E7EB] bg-white px-3.5 py-3">
                <h3 className="text-[11px] font-bold uppercase tracking-[0.08em] text-[#6B7280]">
                  This date
                </h3>
                <div className="mt-2 space-y-1.5">
                  <DetailRow
                    label="Daily Entitlement"
                    value={money(datePay.dailyEntitlement)}
                    valueClassName="text-emerald-700"
                  />
                </div>
              </div>
            ) : null}
            {items.map((item, index) => {
              const timeIn = formatAttendanceTime(item.time_in ?? null, timeZone);
              const timeOut = formatAttendanceTime(item.time_out ?? null, timeZone);
              const rowFace = presentShiftPay(item, items);
              const additional = buildAdditionalPayLines({
                ...item,
                holiday_pay: rowFace.holidayPay,
                rest_day_premium_pay: rowFace.restPay,
                additional_pay: null,
              });
              const deductions = buildDeductionLines(item);
              return (
                <section
                  key={rowKey(item)}
                  className="rounded-xl border border-[#E5E7EB] bg-white px-3.5 py-3"
                >
                  <h3 className="text-[12px] font-extrabold tracking-[0.04em] text-[#111827]">
                    {shiftIndexLabel(index, item.shift_name)}
                  </h3>
                  <div className="mt-2 grid gap-2 sm:grid-cols-2">
                    <DetailRow
                      label="Status"
                      value={statusLabel(item.status, item.payroll_status, item)}
                    />
                    <DetailRow
                      label="Time In → Out"
                      value={
                        item.status === "holiday_paid"
                          ? "Not worked"
                          : `${timeIn} → ${timeOut}`
                      }
                    />
                    <DetailRow
                      label="Hours Worked"
                      value={formatHours(item.hours_worked, item.worked_minutes)}
                    />
                    <DetailRow
                      label="Scheduled"
                      value={`${formatAttendanceTime(item.scheduled_start ?? null, timeZone)} → ${formatAttendanceTime(item.scheduled_end ?? null, timeZone)}`}
                    />
                    <DetailRow label="Pay Basis" value={payBasisLabelFor(item)} />
                    <DetailRow label="Rate Used" value={rateLabelFor(item)} />
                    {rowFace.showEarned ? (
                      <DetailRow
                        label={rowFace.baseLabel}
                        value={
                          item.historical_rate_required
                            ? "Unresolved"
                            : money(rowFace.earned)
                        }
                        valueClassName="text-emerald-700"
                      />
                    ) : null}
                  </div>
                  {additional.length > 0 || deductions.length > 0 ? (
                    <div className="mt-3 space-y-2 border-t border-[#EEF2F7] pt-2.5">
                      {additional.length > 0 ? (
                        <div className="space-y-1.5">
                          <p className="text-[11px] font-bold uppercase tracking-[0.08em] text-[#6B7280]">
                            Additional pay
                          </p>
                          {additional.map((line) => (
                            <DetailRow
                              key={line.key}
                              label={line.label}
                              value={
                                line.amount > 0 ? `+${money(line.amount)}` : "—"
                              }
                              valueClassName={
                                line.amount > 0 ? "text-emerald-700" : undefined
                              }
                            />
                          ))}
                        </div>
                      ) : null}
                      {deductions.length > 0 ? (
                        <div className="space-y-1.5">
                          <p className="text-[11px] font-bold uppercase tracking-[0.08em] text-[#6B7280]">
                            Deductions
                          </p>
                          {deductions.map((line) => (
                            <DetailRow
                              key={line.key}
                              label={line.label}
                              value={
                                line.amount > 0 ? `−${money(line.amount)}` : "—"
                              }
                              valueClassName={
                                line.amount > 0 ? "text-rose-700" : undefined
                              }
                            />
                          ))}
                        </div>
                      ) : null}
                    </div>
                  ) : null}
                  {rowFace.hideShiftTotal ? null : (
                    <div className="mt-3 flex items-center justify-between rounded-xl border border-emerald-200 bg-emerald-50 px-3 py-2.5">
                      <span className="text-[11px] font-extrabold tracking-[0.08em] text-emerald-900">
                        Shift Total
                      </span>
                      <span className="text-base font-extrabold text-emerald-700">
                        {item.historical_rate_required
                          ? "Unresolved"
                          : money(rowFace.shiftTotal)}
                      </span>
                    </div>
                  )}
                  {item.historical_rate_required && canResolve ? (
                    <div className="pt-2">
                      <Button
                        type="button"
                        size="sm"
                        variant="outline"
                        className="rounded-lg"
                        onClick={() => onResolve(item)}
                      >
                        {item.daily_rate_conflict
                          ? "Resolve Daily rate for this day"
                          : "Resolve historical rate"}
                      </Button>
                    </div>
                  ) : null}
                </section>
              );
            })}
            {dateAdditionalPay.length > 0 ? (
              <section className="rounded-xl border border-[#E5E7EB] bg-white px-3.5 py-3">
                <h3 className="text-[11px] font-bold uppercase tracking-[0.08em] text-[#6B7280]">
                  Additional pay
                </h3>
                <div className="mt-2 space-y-1.5">
                  {dateAdditionalPay.map((line) => (
                    <DetailRow
                      key={line.key}
                      label={line.label}
                      value={`+${money(line.amount)}`}
                      valueClassName="text-emerald-700"
                    />
                  ))}
                </div>
              </section>
            ) : null}
            <div className="rounded-xl border border-emerald-200 bg-emerald-50 px-3.5 py-3">
              <div className="flex items-center justify-between gap-3">
                <span className="text-[11px] font-extrabold tracking-[0.08em] text-emerald-900">
                  Day Total
                </span>
                <span className="text-base font-extrabold text-emerald-700">
                  {finalLabel}
                </span>
              </div>
              {equation ? (
                <p className="mt-1.5 text-xs font-medium text-emerald-800">
                  {equation}
                </p>
              ) : null}
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}

function DetailRow({
  label,
  value,
  valueClassName,
}: {
  label: string;
  value: string;
  valueClassName?: string;
}) {
  return (
    <div className="flex items-start justify-between gap-3">
      <p className="text-xs font-medium text-[#6B7280]">{label}</p>
      <p
        className={`text-right text-sm font-semibold tabular-nums text-[#111827] ${valueClassName ?? ""}`}
      >
        {value}
      </p>
    </div>
  );
}
