import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  CalendarDays,
  ChevronDown,
  ChevronRight,
  HelpCircle,
  Pencil,
  Plus,
  Settings2,
} from "lucide-react";
import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { toast } from "sonner";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import {
  createHoliday,
  getPayrollConfig,
  listHolidays,
  seedDefaultHolidays,
  updateHoliday,
  updatePayrollConfig,
  type Holiday,
  type HolidayRulesMode,
  type PayrollConfig,
} from "@/lib/api";
import {
  HOLIDAY_OT_OPTIONS,
  HOLIDAY_PAY_RATE_OPTIONS,
  HOLIDAY_TERMS,
  HOW_HOLIDAY_PAY_WORKS_PRIMARY,
  buildRuleSummary,
  compactRuleLine,
  findDuplicateActiveHoliday,
  holidayPayRateParts,
  holidayTypeLabel,
  isHolidayPayRatePreset,
  multiplierToPercentInput,
  multiplierWarning,
  otPremiumNote,
  workedRateNote,
  percentToPayMultiplier,
  rulesModeDescription,
  rulesModeLabel,
  unworkedRulePresentation,
} from "@/lib/holidayManagementCopy";
import { cn } from "@/lib/utils";
import {
  WizardField,
  WizardNotice,
  WizardToggle,
  wizardInputClass,
  wizardOutlineBtnClass,
  wizardPrimaryBtnClass,
} from "@/components/owner/setup/wizardUi";

type AreaTab = "holidays" | "rules" | "help";
type ListFilter = "all" | "regular" | "special_non_working" | "company";

function isCustomHoliday(holiday: Holiday) {
  return holiday.holiday_type === "company";
}

function formatHolidayDate(value: string, month: "short" | "long" = "short") {
  const parsed = new Date(`${value}T00:00:00`);
  if (Number.isNaN(parsed.getTime())) return value;
  return parsed.toLocaleDateString(undefined, {
    month,
    day: "numeric",
    year: "numeric",
  });
}

function holidayIsActive(holiday: Holiday) {
  return holiday.is_active !== false;
}

function sortByDate(items: Holiday[]) {
  return [...items].sort((a, b) => a.holiday_date.localeCompare(b.holiday_date));
}

function parseOptionalPercent(value: string): number | null | false {
  const trimmed = value.trim();
  if (!trimmed) return null;
  const parsed = Number(trimmed);
  if (Number.isNaN(parsed) || parsed < 0) return false;
  return parsed;
}

function CompactRuleDetails({
  name,
  holidayType,
  mode,
  isPaid,
  payMultiplier,
  otPremiumRaw,
}: {
  name: string;
  holidayType: string;
  mode: HolidayRulesMode;
  isPaid: boolean;
  payMultiplier: number;
  otPremiumRaw: string;
}) {
  const [open, setOpen] = useState(false);
  const summary = buildRuleSummary({
    name,
    holidayType,
    mode,
    isPaid,
    payMultiplier,
    otPremiumRaw,
  });
  const line = compactRuleLine({
    mode,
    holidayType,
    isPaid,
    payMultiplier,
  });

  return (
    <div className="rounded-xl border border-slate-200 bg-[#F8FAFC] px-3 py-2.5">
      <div className="flex items-start justify-between gap-3">
        <p className="text-xs leading-5 text-[#4B5563]">{line}</p>
        <button
          type="button"
          className="shrink-0 text-xs font-semibold text-[var(--owner-navy)]"
          onClick={() => setOpen((v) => !v)}
        >
          {open ? "Hide details" : "View details"}
        </button>
      </div>
      {open ? (
        <div className="mt-3 space-y-2 border-t border-slate-200 pt-3 text-xs leading-5 text-[#4B5563]">
          <p>
            <span className="font-semibold text-[#1F2937]">Worked: </span>
            {summary.worked.join(" ")}
          </p>
          <p>
            <span className="font-semibold text-[#1F2937]">Unworked: </span>
            {summary.unworked[0]}
          </p>
          <p>
            <span className="font-semibold text-[#1F2937]">Overtime: </span>
            {summary.overtime.join(" ")}
          </p>
          <p>
            <span className="font-semibold text-[#1F2937]">Shifts: </span>
            {summary.multipleShifts.join(" ")}
          </p>
        </div>
      ) : null}
    </div>
  );
}

export function HolidaySetupSection() {
  const qc = useQueryClient();
  const [area, setArea] = useState<AreaTab>("holidays");
  const [listFilter, setListFilter] = useState<ListFilter>("all");
  const [showAdd, setShowAdd] = useState(false);
  const [customForm, setCustomForm] = useState({
    name: "",
    holiday_date: "",
    pay_multiplier: "1.0",
    ot_premium_percent: "",
    is_paid: true,
  });
  const [bulkMultiplier, setBulkMultiplier] = useState("1.0");
  const [bulkOt, setBulkOt] = useState("");
  const [editingId, setEditingId] = useState<string | null>(null);
  const [seedAttempted, setSeedAttempted] = useState(false);
  const [advancedOpen, setAdvancedOpen] = useState(false);
  const [rulesLearnMore, setRulesLearnMore] = useState(false);
  const [helpOpenId, setHelpOpenId] = useState<string | null>(null);

  const { data: holidays = [], isLoading, isError } = useQuery({
    queryKey: ["holidays", "management"],
    queryFn: () => listHolidays(true),
  });

  const { data: payroll } = useQuery({
    queryKey: ["payroll-config"],
    queryFn: getPayrollConfig,
  });

  const rulesMode: HolidayRulesMode =
    payroll?.holiday_rules_mode === "custom_company"
      ? "custom_company"
      : "philippine_labor";

  const seedDefaults = useMutation({
    mutationFn: seedDefaultHolidays,
    onSuccess: (created) => {
      if (created.length > 0) {
        toast.success(`Loaded ${created.length} Philippine holidays`);
      }
      qc.invalidateQueries({ queryKey: ["holidays"] });
      qc.invalidateQueries({ queryKey: ["setup-status"] });
    },
    onError: () => toast.error("Could not load default holidays"),
  });

  useEffect(() => {
    if (!isLoading && holidays.length === 0 && !seedAttempted) {
      setSeedAttempted(true);
      seedDefaults.mutate();
    }
  }, [isLoading, holidays.length, seedAttempted]);

  const updateRow = useMutation({
    mutationFn: ({
      id,
      payload,
    }: {
      id: string;
      payload: {
        is_paid?: boolean;
        pay_multiplier?: number;
        ot_premium_percent?: number | null;
        name?: string;
        holiday_date?: string;
      };
    }) => updateHoliday(id, payload),
    onSuccess: () => {
      toast.success("Holiday updated");
      setEditingId(null);
      qc.invalidateQueries({ queryKey: ["holidays"] });
      qc.invalidateQueries({ queryKey: ["setup-status"] });
    },
    onError: () => toast.error("Could not update holiday"),
  });

  const saveRulesMode = useMutation({
    mutationFn: async (mode: HolidayRulesMode) => {
      if (!payroll) throw new Error("Payroll config not loaded");
      return updatePayrollConfig({
        pay_period_type: payroll.pay_period_type,
        next_payday_date: payroll.next_payday_date,
        auto_reset_payroll_cycle: payroll.auto_reset_payroll_cycle,
        late_deduction_enabled: payroll.late_deduction_enabled,
        late_deduction_per_minute: payroll.late_deduction_per_minute,
        overtime_enabled: payroll.overtime_enabled,
        overtime_per_minute: payroll.overtime_per_minute,
        enable_late_overtime_balancing: payroll.enable_late_overtime_balancing,
        overtime_approval_required: payroll.overtime_approval_required,
        holiday_rules_mode: mode,
        weekly_payday_weekday: payroll.weekly_payday_weekday,
        semi_monthly_payday_1: payroll.semi_monthly_payday_1,
        semi_monthly_payday_2: payroll.semi_monthly_payday_2,
        monthly_payday_day: payroll.monthly_payday_day,
      } as Partial<PayrollConfig>);
    },
    onSuccess: () => {
      toast.success("Holiday rules updated");
      qc.invalidateQueries({ queryKey: ["payroll-config"] });
      qc.invalidateQueries({ queryKey: ["setup-status"] });
    },
    onError: () => toast.error("Could not update holiday rules"),
  });

  const addCustom = useMutation({
    mutationFn: () => {
      const multiplier = Number(customForm.pay_multiplier);
      if (!customForm.name.trim()) {
        throw new Error("Please enter a holiday name");
      }
      if (!customForm.holiday_date) {
        throw new Error("Please choose a holiday date");
      }
      if (Number.isNaN(multiplier) || multiplier <= 0) {
        throw new Error("Holiday Pay Rate must be greater than 0%");
      }
      const otPremium = parseOptionalPercent(customForm.ot_premium_percent);
      if (otPremium === false) {
        throw new Error("Holiday OT Premium must be 0 or greater, or left blank");
      }
      return createHoliday({
        name: customForm.name.trim(),
        holiday_date: customForm.holiday_date,
        is_paid: customForm.is_paid,
        pay_multiplier: multiplier,
        ot_premium_percent: otPremium,
        holiday_type: "company",
      });
    },
    onSuccess: () => {
      toast.success("Holiday added");
      setCustomForm({
        name: "",
        holiday_date: "",
        pay_multiplier: "1.0",
        ot_premium_percent: "",
        is_paid: true,
      });
      setAdvancedOpen(false);
      setShowAdd(false);
      qc.invalidateQueries({ queryKey: ["holidays"] });
      qc.invalidateQueries({ queryKey: ["setup-status"] });
    },
    onError: (error: Error) => toast.error(error.message || "Could not add holiday"),
  });

  const applyDefaults = useMutation({
    mutationFn: async () => {
      const multiplier = Number(bulkMultiplier);
      if (Number.isNaN(multiplier) || multiplier <= 0) {
        throw new Error("Holiday Pay Rate must be greater than 0%");
      }
      const otPremium = parseOptionalPercent(bulkOt);
      if (otPremium === false) {
        throw new Error("Holiday OT Premium must be 0 or greater, or left blank");
      }
      for (const holiday of holidays) {
        await updateHoliday(holiday.id, {
          pay_multiplier: multiplier,
          ot_premium_percent: otPremium,
        });
      }
    },
    onSuccess: () => {
      toast.success("Holiday updated");
      qc.invalidateQueries({ queryKey: ["holidays"] });
      qc.invalidateQueries({ queryKey: ["setup-status"] });
    },
    onError: (error: Error) => {
      toast.error(
        error.message.startsWith("Holiday")
          ? error.message
          : "Could not update holiday"
      );
      qc.invalidateQueries({ queryKey: ["holidays"] });
    },
  });

  const toggleActive = useMutation({
    mutationFn: ({ id, is_active }: { id: string; is_active: boolean }) =>
      updateHoliday(id, { is_active }),
    onMutate: async ({ id, is_active }) => {
      await qc.cancelQueries({ queryKey: ["holidays", "management"] });
      const previous = qc.getQueryData<Holiday[]>(["holidays", "management"]);
      qc.setQueryData<Holiday[]>(["holidays", "management"], (rows) =>
        rows?.map((row) => (row.id === id ? { ...row, is_active } : row))
      );
      return { previous };
    },
    onError: (_error, _vars, context) => {
      if (context?.previous) {
        qc.setQueryData(["holidays", "management"], context.previous);
      }
      toast.error("Could not update holiday");
    },
    onSettled: () => {
      qc.invalidateQueries({ queryKey: ["holidays"] });
      qc.invalidateQueries({ queryKey: ["setup-status"] });
    },
  });

  const filteredHolidays = useMemo(() => {
    const sorted = sortByDate(holidays);
    if (listFilter === "all") return sorted;
    return sorted.filter((h) => h.holiday_type === listFilter);
  }, [holidays, listFilter]);

  const grouped = useMemo(() => {
    const groups: { key: string; title: string; items: Holiday[] }[] = [
      { key: "regular", title: "Regular Holidays", items: [] },
      { key: "special_non_working", title: "Special Non-Working Days", items: [] },
      { key: "company", title: "Company Holidays", items: [] },
    ];
    for (const holiday of filteredHolidays) {
      if (holiday.holiday_type === "regular") groups[0].items.push(holiday);
      else if (holiday.holiday_type === "special_non_working")
        groups[1].items.push(holiday);
      else if (holiday.holiday_type === "company") groups[2].items.push(holiday);
    }
    return groups.filter((g) => g.items.length > 0);
  }, [filteredHolidays]);

  const editingHoliday = editingId
    ? holidays.find((h) => h.id === editingId) ?? null
    : null;

  const createDuplicate = findDuplicateActiveHoliday(
    holidays,
    customForm.holiday_date
  );
  const createMultiplier = Number(customForm.pay_multiplier);
  const createMultWarn = multiplierWarning(
    Number.isNaN(createMultiplier) ? null : createMultiplier
  );
  const createUnworked = unworkedRulePresentation(
    rulesMode,
    "company",
    customForm.is_paid
  );

  const tabs: { id: AreaTab; label: string; icon: typeof CalendarDays }[] = [
    { id: "holidays", label: HOLIDAY_TERMS.holidays, icon: CalendarDays },
    { id: "rules", label: HOLIDAY_TERMS.holidayRules, icon: Settings2 },
    { id: "help", label: "How it works", icon: HelpCircle },
  ];

  const filters: { id: ListFilter; label: string }[] = [
    { id: "all", label: "All" },
    { id: "regular", label: "Regular" },
    { id: "special_non_working", label: "Special" },
    { id: "company", label: "Company" },
  ];

  return (
    <div className="min-w-0 space-y-4">
      <div className="flex flex-wrap gap-1 rounded-xl border border-slate-200 bg-[#F8FAFC] p-1">
        {tabs.map((tab) => {
          const Icon = tab.icon;
          const active = area === tab.id;
          return (
            <button
              key={tab.id}
              type="button"
              onClick={() => {
                setArea(tab.id);
                setShowAdd(false);
                setEditingId(null);
              }}
              className={cn(
                "inline-flex min-w-0 flex-1 items-center justify-center gap-1.5 rounded-lg px-3 py-2 text-sm font-medium transition sm:flex-none",
                active
                  ? "bg-white text-[var(--owner-navy)] shadow-sm"
                  : "text-[#6B7280] hover:text-[#1F2937]"
              )}
            >
              <Icon className="h-4 w-4 shrink-0" />
              <span className="truncate">{tab.label}</span>
            </button>
          );
        })}
      </div>

      {area === "holidays" && (
        <div className="space-y-4">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div className="min-w-0">
              <h3 className="text-base font-semibold text-[#1F2937]">Holidays</h3>
              <p className="mt-0.5 text-sm text-[#6B7280]">
                Turn a holiday off to keep it out of schedules and pay. It stays
                in this list.
              </p>
            </div>
            <Button
              className={wizardPrimaryBtnClass}
              onClick={() => {
                setShowAdd(true);
                setEditingId(null);
              }}
            >
              <Plus className="mr-1.5 h-4 w-4" />
              Add holiday
            </Button>
          </div>

          <div className="flex flex-wrap gap-1.5">
            {filters.map((f) => (
              <button
                key={f.id}
                type="button"
                onClick={() => setListFilter(f.id)}
                className={cn(
                  "rounded-full px-3 py-1 text-xs font-semibold transition",
                  listFilter === f.id
                    ? "bg-[var(--owner-button)] text-white"
                    : "bg-[var(--owner-well)] text-[var(--owner-navy)] hover:bg-[var(--owner-well)]"
                )}
              >
                {f.label}
              </button>
            ))}
          </div>

          {isLoading && (
            <p className="text-sm text-[#6B7280]">Loading holidays…</p>
          )}
          {isError && (
            <WizardNotice tone="error">
              Unable to load holidays. Please try again.
            </WizardNotice>
          )}

          {!isLoading && !isError && (
            <div className="space-y-3 rounded-2xl border border-slate-200 bg-white px-4 py-3">
              <p className="text-sm font-semibold text-[#1F2937]">
                Holiday Pay Defaults
              </p>
              <HolidayPayRateField
                multiplierRaw={bulkMultiplier}
                onMultiplierChange={setBulkMultiplier}
                disabled={applyDefaults.isPending}
              />
              <HolidayOtPremiumField
                valueRaw={bulkOt}
                onChange={setBulkOt}
                disabled={applyDefaults.isPending}
              />
              <Button
                className={wizardPrimaryBtnClass}
                disabled={applyDefaults.isPending || holidays.length === 0}
                onClick={() => applyDefaults.mutate()}
              >
                Apply to all holidays
              </Button>
            </div>
          )}

          {showAdd && (
            <HolidayEditorPanel
              title="Add company holiday"
              onClose={() => {
                setShowAdd(false);
                setAdvancedOpen(false);
              }}
            >
              <div className="space-y-4">
                <SectionLabel>Basic details</SectionLabel>
                <div className="grid gap-3 sm:grid-cols-2">
                  <WizardField label="Holiday name">
                    <Input
                      className={wizardInputClass}
                      value={customForm.name}
                      onChange={(e) =>
                        setCustomForm({ ...customForm, name: e.target.value })
                      }
                      placeholder="Company Foundation Day"
                    />
                  </WizardField>
                  <WizardField label="Holiday date">
                    <Input
                      className={wizardInputClass}
                      type="date"
                      value={customForm.holiday_date}
                      onChange={(e) =>
                        setCustomForm({
                          ...customForm,
                          holiday_date: e.target.value,
                        })
                      }
                    />
                  </WizardField>
                </div>
                <p className="text-xs text-[#6B7280]">
                  Type: {holidayTypeLabel("company")} · Status: Active
                </p>
                {createDuplicate ? (
                  <WizardNotice tone="warning">
                    Another active holiday already exists on this date:{" "}
                    {createDuplicate.name} (
                    {holidayTypeLabel(createDuplicate.holiday_type)}).
                  </WizardNotice>
                ) : null}

                <SectionLabel>Holiday Pay</SectionLabel>
                <HolidayPayRateField
                  multiplierRaw={customForm.pay_multiplier}
                  onMultiplierChange={(next) =>
                    setCustomForm({ ...customForm, pay_multiplier: next })
                  }
                  warning={createMultWarn}
                />

                <SectionLabel>When employees don&apos;t work</SectionLabel>
                <div className="flex items-start justify-between gap-3 rounded-xl border border-slate-200 px-3 py-2.5">
                  <div className="min-w-0">
                    <p className="text-sm font-medium text-[#1F2937]">
                      {createUnworked.title}
                    </p>
                    <p className="mt-0.5 text-xs text-[#6B7280]">
                      {createUnworked.explanation}
                    </p>
                  </div>
                  {createUnworked.editable ? (
                    <WizardToggle
                      checked={customForm.is_paid}
                      onChange={(next) =>
                        setCustomForm({ ...customForm, is_paid: next })
                      }
                      label={createUnworked.title}
                    />
                  ) : (
                    <Badge className="shrink-0 border-0 bg-[var(--owner-well)] text-[var(--owner-navy)]">
                      {createUnworked.effectivePaysUnworked
                        ? "Pay Scheduled Day"
                        : "No pay"}
                    </Badge>
                  )}
                </div>

                <SectionLabel>Holiday Overtime</SectionLabel>
                <HolidayOtPremiumField
                  valueRaw={customForm.ot_premium_percent}
                  onChange={(next) =>
                    setCustomForm({ ...customForm, ot_premium_percent: next })
                  }
                />

                <button
                  type="button"
                  className="inline-flex items-center gap-1 text-xs font-semibold text-[var(--owner-navy)]"
                  onClick={() => setAdvancedOpen((v) => !v)}
                >
                  {advancedOpen ? (
                    <ChevronDown className="h-3.5 w-3.5" />
                  ) : (
                    <ChevronRight className="h-3.5 w-3.5" />
                  )}
                  Advanced notes
                </button>
                {advancedOpen ? (
                  <div className="space-y-1 rounded-xl border border-dashed border-slate-200 px-3 py-2 text-xs leading-5 text-[#6B7280]">
                    <p>
                      Holiday pay automatically follows the employee&apos;s
                      existing pay basis. Daily and Hourly employees use the
                      payroll rules already configured in Aroll+.
                    </p>
                    <p>
                      Employees with multiple shifts on the same day are handled
                      automatically according to their pay basis and holiday
                      rules.
                    </p>
                    <p>Rest-day premiums remain separate.</p>
                  </div>
                ) : null}

                <CompactRuleDetails
                  name={customForm.name}
                  holidayType="company"
                  mode={rulesMode}
                  isPaid={customForm.is_paid}
                  payMultiplier={
                    Number.isNaN(createMultiplier) ? 1 : createMultiplier
                  }
                  otPremiumRaw={customForm.ot_premium_percent}
                />

                <div className="flex flex-wrap gap-2">
                  <Button
                    className={wizardPrimaryBtnClass}
                    onClick={() => addCustom.mutate()}
                    disabled={addCustom.isPending}
                  >
                    Save holiday
                  </Button>
                  <Button
                    variant="outline"
                    className={wizardOutlineBtnClass}
                    onClick={() => {
                      setShowAdd(false);
                      setAdvancedOpen(false);
                    }}
                  >
                    Cancel
                  </Button>
                </div>
              </div>
            </HolidayEditorPanel>
          )}

          {editingHoliday && (
            <EditHolidayPanel
              holiday={editingHoliday}
              rulesMode={rulesMode}
              holidays={holidays}
              pending={updateRow.isPending}
              onClose={() => setEditingId(null)}
              onUpdate={(payload) =>
                updateRow.mutate({ id: editingHoliday.id, payload })
              }
            />
          )}

          {!isLoading && grouped.length === 0 && !showAdd && (
            <div className="rounded-2xl border border-dashed border-slate-200 bg-[#FAFBFC] px-4 py-8 text-center text-sm text-[#6B7280]">
              No holidays in this view yet.
            </div>
          )}

          {!isLoading &&
            grouped.map((group) => (
              <section key={group.key} className="min-w-0">
                <h4 className="mb-2 text-xs font-semibold uppercase tracking-[0.12em] text-[#9CA3AF]">
                  {group.title}
                </h4>
                <ul className="overflow-hidden rounded-2xl border border-slate-200 bg-white">
                  {group.items.map((holiday) => {
                    const active = holidayIsActive(holiday);
                    const toggling =
                      toggleActive.isPending &&
                      toggleActive.variables?.id === holiday.id;
                    return (
                        <li
                        key={holiday.id}
                        className={cn(
                          "border-b border-slate-100 px-4 py-2.5 last:border-b-0",
                          !active && "bg-[#F7F8FA]",
                          editingId === holiday.id && "bg-[var(--owner-well)]"
                        )}
                      >
                        <div className="flex items-center justify-between gap-3">
                          <div className="min-w-0">
                            <p
                              className={cn(
                                "truncate text-sm font-medium",
                                active ? "text-[#1F2937]" : "text-[#6B7280]"
                              )}
                            >
                              {holiday.name}
                            </p>
                            <p className="mt-0.5 truncate text-xs text-[#6B7280]">
                              {formatHolidayDate(holiday.holiday_date)} ·{" "}
                              {holidayTypeLabel(holiday.holiday_type)}
                            </p>
                          </div>
                          <div className="flex shrink-0 items-center gap-1">
                            <HolidayActiveSwitch
                              checked={active}
                              disabled={toggling}
                              label={
                                active
                                  ? `Turn ${holiday.name} off`
                                  : `Turn ${holiday.name} on`
                              }
                              onChange={(next) =>
                                toggleActive.mutate({
                                  id: holiday.id,
                                  is_active: next,
                                })
                              }
                            />
                            <button
                              type="button"
                              title={HOLIDAY_TERMS.editHolidayPay}
                              aria-label={`${HOLIDAY_TERMS.editHolidayPay} for ${holiday.name}`}
                              className="inline-flex h-8 w-8 items-center justify-center rounded-lg text-[var(--owner-accent)] hover:bg-[var(--owner-well)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[color-mix(in_srgb,var(--owner-accent)_40%,transparent)]"
                              onClick={() => {
                                setEditingId(holiday.id);
                                setShowAdd(false);
                              }}
                            >
                              <Pencil className="h-4 w-4" />
                            </button>
                          </div>
                        </div>
                      </li>
                    );
                  })}
                </ul>
              </section>
            ))}

          <Button
            variant="outline"
            className={wizardOutlineBtnClass}
            onClick={() => seedDefaults.mutate()}
            disabled={seedDefaults.isPending}
          >
            Load Philippine holidays
          </Button>
        </div>
      )}

      {area === "rules" && (
        <div className="space-y-4">
          <div>
            <h3 className="text-base font-semibold text-[#1F2937]">
              {HOLIDAY_TERMS.holidayRules}
            </h3>
            <p className="mt-0.5 text-sm text-[#6B7280]">
              Choose how holiday types are interpreted for worked and unworked
              days.
            </p>
          </div>
          <div className="space-y-2">
            {(["philippine_labor", "custom_company"] as HolidayRulesMode[]).map(
              (mode) => {
                const selected = rulesMode === mode;
                return (
                  <label
                    key={mode}
                    className={cn(
                      "flex cursor-pointer items-start gap-3 rounded-xl border bg-white px-4 py-3 text-sm",
                      selected
                        ? "border-[color-mix(in_srgb,var(--owner-accent)_45%,white)] bg-[var(--owner-well)]"
                        : "border-slate-200"
                    )}
                  >
                    <input
                      type="radio"
                      className="mt-1 accent-[var(--owner-accent)]"
                      name="holiday_rules_mode_holiday_mgmt"
                      checked={selected}
                      disabled={saveRulesMode.isPending || !payroll}
                      onChange={() => saveRulesMode.mutate(mode)}
                    />
                    <span>
                      <span className="font-medium text-[#1F2937]">
                        {rulesModeLabel(mode)}
                      </span>
                      <span className="mt-0.5 block text-xs text-[#6B7280]">
                        {rulesModeDescription(mode)}
                      </span>
                    </span>
                  </label>
                );
              }
            )}
          </div>
          <button
            type="button"
            className="inline-flex items-center gap-1 text-xs font-semibold text-[var(--owner-navy)]"
            onClick={() => setRulesLearnMore((v) => !v)}
          >
            {rulesLearnMore ? (
              <ChevronDown className="h-3.5 w-3.5" />
            ) : (
              <ChevronRight className="h-3.5 w-3.5" />
            )}
            Learn more
          </button>
          {rulesLearnMore ? (
            <div className="rounded-xl border border-slate-200 bg-[#F8FAFC] px-4 py-3 text-xs leading-5 text-[#4B5563]">
              <p>
                Current mode: <strong>{rulesModeLabel(rulesMode)}</strong>.
              </p>
              <p className="mt-2">
                Under Philippine labor rules, Regular and Special Non-Working
                Days use fixed unworked treatment. Company holidays still use
                Pay Scheduled Day When Not Working.
              </p>
              <p className="mt-2">
                Individual holiday premiums and Holiday OT Premium are set from
                the edit icon on each holiday.
              </p>
            </div>
          ) : null}
        </div>
      )}

      {area === "help" && (
        <div className="space-y-4">
          <div>
            <h3 className="text-base font-semibold text-[#1F2937]">
              {HOLIDAY_TERMS.howHolidayPayWorks}
            </h3>
            <p className="mt-0.5 text-sm text-[#6B7280]">
              Simple overview of how Aroll+ applies holiday settings. Not legal
              advice.
            </p>
          </div>
          <div className="divide-y divide-slate-100 overflow-hidden rounded-2xl border border-slate-200 bg-white">
            {HOW_HOLIDAY_PAY_WORKS_PRIMARY.map((section) => {
              const open = helpOpenId === section.title;
              return (
                <div key={section.title} className="px-4 py-3">
                  <button
                    type="button"
                    className="flex w-full items-start justify-between gap-3 text-left"
                    onClick={() =>
                      setHelpOpenId(open ? null : section.title)
                    }
                  >
                    <div className="min-w-0">
                      <p className="text-sm font-semibold text-[#1F2937]">
                        {section.title}
                      </p>
                      <p className="mt-1 text-xs leading-5 text-[#6B7280]">
                        {section.summary}
                      </p>
                    </div>
                    {open ? (
                      <ChevronDown className="mt-0.5 h-4 w-4 shrink-0 text-[#9CA3AF]" />
                    ) : (
                      <ChevronRight className="mt-0.5 h-4 w-4 shrink-0 text-[#9CA3AF]" />
                    )}
                  </button>
                  {open ? (
                    <p className="mt-2 text-xs leading-5 text-[#4B5563]">
                      {section.detail}
                    </p>
                  ) : null}
                </div>
              );
            })}
          </div>
        </div>
      )}

    </div>
  );
}

function HolidayActiveSwitch({
  checked,
  onChange,
  label,
  disabled,
}: {
  checked: boolean;
  onChange: (next: boolean) => void;
  label: string;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      disabled={disabled}
      onClick={() => onChange(!checked)}
      className={cn(
        "relative h-6 w-11 shrink-0 rounded-full transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[color-mix(in_srgb,var(--owner-accent)_40%,transparent)] focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-60",
        checked ? "bg-[var(--owner-button)]" : "bg-slate-300"
      )}
    >
      <span
        className={cn(
          "absolute left-0.5 top-0.5 h-5 w-5 rounded-full bg-white shadow-sm transition-transform duration-200",
          checked ? "translate-x-5" : "translate-x-0"
        )}
      />
    </button>
  );
}

function HolidayChoiceMenu({
  label,
  title,
  detail,
  options,
  selectedId,
  disabled,
  onSelect,
}: {
  label: string;
  title: string;
  detail: string;
  options: ReadonlyArray<{ id: string; title: string; detail: string }>;
  selectedId: string;
  disabled?: boolean;
  onSelect: (id: string) => void;
}) {
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    function onPointerDown(event: MouseEvent) {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    }
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") setOpen(false);
    }
    document.addEventListener("mousedown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("mousedown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [open]);

  return (
    <div ref={rootRef} className="relative">
      <button
        type="button"
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-label={`${label}, ${title}, ${detail}`}
        disabled={disabled}
        onClick={() => setOpen((value) => !value)}
        className="flex min-h-11 w-full min-w-0 items-center justify-between gap-3 rounded-xl border border-slate-200 bg-white px-3 py-1.5 text-left transition hover:border-[color-mix(in_srgb,var(--owner-accent)_35%,white)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[color-mix(in_srgb,var(--owner-accent)_35%,transparent)] disabled:cursor-not-allowed disabled:opacity-60"
      >
        <span className="min-w-0">
          <span className="block truncate text-sm font-medium text-[#1F2937]">
            {title}
          </span>
          <span className="block truncate text-xs text-[#6B7280]">{detail}</span>
        </span>
        <ChevronDown
          className={cn(
            "h-4 w-4 shrink-0 text-[#6B7280] transition",
            open && "rotate-180"
          )}
        />
      </button>
      {open ? (
        <ul
          role="listbox"
          aria-label={label}
          className="mt-1 max-h-96 w-full overflow-x-hidden overflow-y-auto rounded-xl border border-slate-200 bg-white py-1"
        >
          {options.map((option) => {
            const selected = option.id === selectedId;
            return (
              <li key={option.id} role="presentation">
                <button
                  type="button"
                  role="option"
                  aria-selected={selected}
                  className={cn(
                    "flex w-full min-w-0 flex-col px-3 py-2 text-left hover:bg-[var(--owner-well)] focus-visible:bg-[var(--owner-well)] focus-visible:outline-none",
                    selected && "bg-[var(--owner-well)]"
                  )}
                  onClick={() => {
                    onSelect(option.id);
                    setOpen(false);
                  }}
                >
                  <span className="text-sm font-medium text-[#1F2937]">
                    {option.title}
                  </span>
                  <span className="text-xs text-[#6B7280]">{option.detail}</span>
                </button>
              </li>
            );
          })}
        </ul>
      ) : null}
    </div>
  );
}

function SectionLabel({ children }: { children: ReactNode }) {
  return (
    <p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-[#9CA3AF]">
      {children}
    </p>
  );
}

function HolidayEditorPanel({
  title,
  onClose,
  children,
}: {
  title: string;
  onClose: () => void;
  children: ReactNode;
}) {
  return (
    <div className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
      <div className="mb-4 flex items-center justify-between gap-3">
        <h4 className="text-sm font-semibold text-[#1F2937]">{title}</h4>
        <button
          type="button"
          className="text-xs font-semibold text-[#6B7280] hover:text-[#1F2937]"
          onClick={onClose}
        >
          Close
        </button>
      </div>
      {children}
    </div>
  );
}

function EditHolidayPanel({
  holiday,
  rulesMode,
  holidays,
  pending,
  onClose,
  onUpdate,
}: {
  holiday: Holiday;
  rulesMode: HolidayRulesMode;
  holidays: Holiday[];
  pending: boolean;
  onClose: () => void;
  onUpdate: (payload: {
    is_paid?: boolean;
    pay_multiplier?: number;
    ot_premium_percent?: number | null;
    name?: string;
    holiday_date?: string;
  }) => void;
}) {
  const [name, setName] = useState(holiday.name);
  const [dateValue, setDateValue] = useState(holiday.holiday_date);
  const [multiplier, setMultiplier] = useState(String(holiday.pay_multiplier));
  const [otPremium, setOtPremium] = useState(
    holiday.ot_premium_percent == null ? "" : String(holiday.ot_premium_percent)
  );
  const [isPaid, setIsPaid] = useState(holiday.is_paid);
  const custom = isCustomHoliday(holiday);
  const unworked = unworkedRulePresentation(
    rulesMode,
    holiday.holiday_type,
    isPaid
  );
  const multNum = Number(multiplier);
  const multWarn = multiplierWarning(Number.isNaN(multNum) ? null : multNum);
  const dup = findDuplicateActiveHoliday(holidays, dateValue, holiday.id);

  useEffect(() => {
    setName(holiday.name);
    setDateValue(holiday.holiday_date);
    setMultiplier(String(holiday.pay_multiplier));
    setOtPremium(
      holiday.ot_premium_percent == null
        ? ""
        : String(holiday.ot_premium_percent)
    );
    setIsPaid(holiday.is_paid);
  }, [holiday]);

  function save() {
    const nextMult = Number(multiplier);
    if (Number.isNaN(nextMult) || nextMult <= 0) {
      toast.error("Holiday Pay Rate must be greater than 0%");
      return;
    }
    const ot = parseOptionalPercent(otPremium);
    if (ot === false) {
      toast.error("Holiday OT Premium must be 0 or greater, or left blank");
      return;
    }
    const payload: {
      is_paid?: boolean;
      pay_multiplier?: number;
      ot_premium_percent?: number | null;
      name?: string;
      holiday_date?: string;
    } = {
      pay_multiplier: nextMult,
      ot_premium_percent: ot,
    };
    if (unworked.editable) payload.is_paid = isPaid;
    if (custom) {
      if (name.trim()) payload.name = name.trim();
      if (dateValue) payload.holiday_date = dateValue;
    }
    onUpdate(payload);
  }

  const headerName = custom ? name.trim() || holiday.name : holiday.name;
  const headerDate = custom ? dateValue || holiday.holiday_date : holiday.holiday_date;

  return (
    <Dialog
      open
      onOpenChange={(open) => {
        if (!open && !pending) onClose();
      }}
    >
      <DialogContent className="max-h-[min(92vh,40rem)] gap-0 overflow-x-hidden overflow-y-auto rounded-2xl border-slate-200 p-0 sm:max-w-md">
      <DialogHeader className="space-y-1 px-5 pb-2 pr-12 pt-5 text-left">
        <DialogTitle className="text-lg font-semibold text-[#1F2937]">
          {headerName}
        </DialogTitle>
        <DialogDescription className="space-y-0.5 text-sm text-[#6B7280]">
          <span className="block font-medium text-[#374151]">
            {holidayTypeLabel(holiday.holiday_type)}
          </span>
          <span className="block">{formatHolidayDate(headerDate, "long")}</span>
        </DialogDescription>
        <p className="flex items-center gap-1.5 pt-1 text-xs font-medium text-[#4B5563]">
          <span
            className={cn(
              "h-1.5 w-1.5 rounded-full",
              holidayIsActive(holiday) ? "bg-[var(--owner-button)]" : "bg-slate-400"
            )}
          />
          {holidayIsActive(holiday) ? "Active" : "Inactive"}
        </p>
      </DialogHeader>
      <div className="space-y-4 px-5 pb-2">
        {custom ? (
          <div className="grid gap-3 sm:grid-cols-2">
            <WizardField label="Holiday name">
              <Input
                className={wizardInputClass}
                value={name}
                onChange={(e) => setName(e.target.value)}
              />
            </WizardField>
            <WizardField label="Holiday date">
              <Input
                className={wizardInputClass}
                type="date"
                value={dateValue}
                onChange={(e) => setDateValue(e.target.value)}
              />
            </WizardField>
          </div>
        ) : null}
        {dup ? (
          <WizardNotice tone="warning">
            Another active holiday already exists on this date: {dup.name} (
            {holidayTypeLabel(dup.holiday_type)}).
          </WizardNotice>
        ) : null}

        <div className="space-y-2 border-t border-slate-100 pt-3">
          <SectionLabel>Worked holiday</SectionLabel>
          <HolidayPayRateField
            key={`rate-${holiday.id}`}
            multiplierRaw={multiplier}
            onMultiplierChange={setMultiplier}
            warning={multWarn}
            disabled={pending}
          />
        </div>

        <div className="space-y-2 border-t border-slate-100 pt-3">
          <SectionLabel>Unworked holiday</SectionLabel>
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <p className="text-sm font-medium text-[#1F2937]">
                {HOLIDAY_TERMS.payScheduledDay}
              </p>
              <p className="mt-0.5 text-xs leading-5 text-[#6B7280]">
                {unworked.explanation}
              </p>
            </div>
            <HolidayActiveSwitch
              checked={
                unworked.editable ? isPaid : unworked.effectivePaysUnworked
              }
              disabled={!unworked.editable || pending}
              label={
                unworked.editable
                  ? unworked.title
                  : unworked.explanation
              }
              onChange={setIsPaid}
            />
          </div>
        </div>

        <div className="space-y-2 border-t border-slate-100 pt-3">
          <SectionLabel>Holiday OT</SectionLabel>
          <HolidayOtPremiumField
            key={`ot-${holiday.id}`}
            valueRaw={otPremium}
            onChange={setOtPremium}
            disabled={pending}
          />
        </div>

        <p className="text-xs leading-5 text-[#6B7280]">
          Holiday pay follows each employee&apos;s current pay basis. More than
          one shift on the same day is handled automatically.
        </p>
      </div>
      <DialogFooter className="gap-2 px-5 pb-5 pt-3 sm:space-x-0">
        <Button
          variant="outline"
          className={wizardOutlineBtnClass}
          onClick={onClose}
          disabled={pending}
        >
          Cancel
        </Button>
        <Button
          className={wizardPrimaryBtnClass}
          onClick={save}
          disabled={pending}
        >
          Save
        </Button>
      </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function HolidayPayRateField({
  multiplierRaw,
  onMultiplierChange,
  warning,
  disabled,
}: {
  multiplierRaw: string;
  onMultiplierChange: (next: string) => void;
  warning?: string | null;
  disabled?: boolean;
}) {
  const multNum = Number(multiplierRaw);
  const safeMult =
    Number.isFinite(multNum) && multNum > 0 ? multNum : Number.NaN;
  const [mode, setMode] = useState<"preset" | "custom">(() =>
    Number.isFinite(safeMult) && isHolidayPayRatePreset(safeMult)
      ? "preset"
      : "custom"
  );
  const [customPercent, setCustomPercent] = useState(() =>
    Number.isFinite(safeMult) ? multiplierToPercentInput(safeMult) : ""
  );
  const presetId =
    HOLIDAY_PAY_RATE_OPTIONS.find(
      (option) => Math.abs(option.multiplier - (safeMult || 0)) < 0.0001
    )?.multiplier.toFixed(1) ?? "custom";
  const selectedId = mode === "custom" ? "custom" : presetId;
  const parts = holidayPayRateParts(Number.isFinite(safeMult) ? safeMult : 1);
  const closed =
    selectedId === "custom"
      ? {
          title: "Custom",
          detail: customPercent.trim() ? `${customPercent.trim()}%` : "Enter a percent",
        }
      : parts;

  return (
    <div className="space-y-2">
      <p className="text-sm font-medium text-[#1F2937]">Holiday Pay Rate</p>
      <HolidayChoiceMenu
        label="Holiday Pay Rate"
        title={closed.title}
        detail={closed.detail}
        selectedId={selectedId}
        disabled={disabled}
        options={[
          ...HOLIDAY_PAY_RATE_OPTIONS.map((option) => ({
            id: option.multiplier.toFixed(1),
            title: option.title,
            detail: option.detail,
          })),
          { id: "custom", title: "Custom", detail: "Enter a percent" },
        ]}
        onSelect={(id) => {
          if (id === "custom") {
            setMode("custom");
            if (!customPercent.trim() && Number.isFinite(safeMult)) {
              setCustomPercent(multiplierToPercentInput(safeMult));
            }
            return;
          }
          setMode("preset");
          onMultiplierChange(id);
        }}
      />
      {mode === "custom" ? (
        <WizardField label="Custom total pay rate">
          <div className="relative">
            <Input
              className={cn(wizardInputClass, "pr-8")}
              type="number"
              min="1"
              step="any"
              value={customPercent}
              disabled={disabled}
              onChange={(e) => {
                const raw = e.target.value;
                setCustomPercent(raw);
                const pct = Number(raw);
                if (Number.isFinite(pct) && pct > 0) {
                  onMultiplierChange(String(percentToPayMultiplier(pct)));
                }
              }}
            />
            <span className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-sm text-[#6B7280]">
              %
            </span>
          </div>
        </WizardField>
      ) : null}
      <p className="text-xs leading-5 text-[#6B7280]">
        {workedRateNote(
          Number.isFinite(safeMult) ? safeMult : 1,
          selectedId === "custom"
        )}
      </p>
      {warning ? <p className="text-xs text-amber-700">{warning}</p> : null}
    </div>
  );
}

function HolidayOtPremiumField({
  valueRaw,
  onChange,
  disabled,
}: {
  valueRaw: string;
  onChange: (next: string) => void;
  disabled?: boolean;
}) {
  const trimmed = valueRaw.trim();
  const num = trimmed === "" ? null : Number(trimmed);
  const [mode, setMode] = useState<"0" | "30" | "custom">(() => {
    if (!trimmed || num === 0) return "0";
    if (num != null && !Number.isNaN(num) && Math.abs(num - 30) < 0.0001) {
      return "30";
    }
    return "custom";
  });
  const [customValue, setCustomValue] = useState(() =>
    mode === "custom" ? valueRaw : ""
  );

  const selected = HOLIDAY_OT_OPTIONS.find((option) => option.id === mode);
  const closed =
    mode === "custom"
      ? {
          title: "Custom",
          detail: customValue.trim() ? `${customValue.trim()}%` : "Enter a percent",
        }
      : {
          title: selected?.title ?? "No Extra OT",
          detail: selected?.detail ?? "0%",
        };

  return (
    <div className="space-y-2">
      <p className="text-sm font-medium text-[#1F2937]">
        {HOLIDAY_TERMS.holidayOtPremium}
      </p>
      <HolidayChoiceMenu
        label={HOLIDAY_TERMS.holidayOtPremium}
        title={closed.title}
        detail={closed.detail}
        selectedId={mode}
        disabled={disabled}
        options={HOLIDAY_OT_OPTIONS}
        onSelect={(id) => {
          if (id === "0") {
            setMode("0");
            onChange("");
            return;
          }
          if (id === "30") {
            setMode("30");
            onChange("30");
            return;
          }
          setMode("custom");
        }}
      />
      {mode === "custom" ? (
        <WizardField label="Custom holiday OT premium">
          <div className="relative">
            <Input
              className={cn(wizardInputClass, "pr-8")}
              type="number"
              min="0"
              step="any"
              value={customValue}
              disabled={disabled}
              onChange={(e) => {
                setCustomValue(e.target.value);
                onChange(e.target.value);
              }}
              placeholder="Blank = 0%"
            />
            <span className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-sm text-[#6B7280]">
              %
            </span>
          </div>
        </WizardField>
      ) : null}
      <p className="text-xs leading-5 text-[#6B7280]">{otPremiumNote(valueRaw)}</p>
    </div>
  );
}
