import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useMemo, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import {
  createHoliday,
  deleteHoliday,
  listHolidays,
  seedDefaultHolidays,
  updateHoliday,
  type Holiday,
} from "@/lib/api";
import { cn } from "@/lib/utils";
import {
  WizardField,
  WizardNotice,
  WizardSection,
  WizardToggle,
  wizardInputClass,
  wizardOutlineBtnClass,
  wizardPrimaryBtnClass,
} from "@/components/owner/setup/wizardUi";

function isCustomHoliday(holiday: Holiday) {
  return holiday.holiday_type === "company";
}

function holidayTypeMeta(type: string) {
  if (type === "regular") {
    return { label: "Regular holiday", group: "Regular" };
  }
  if (type === "special_non_working") {
    return { label: "Special non-working", group: "Special non-working" };
  }
  if (type === "company") {
    return { label: "Company holiday", group: "Company" };
  }
  return { label: type, group: "Other" };
}

function formatHolidayDate(value: string) {
  const parsed = new Date(`${value}T00:00:00`);
  if (Number.isNaN(parsed.getTime())) return value;
  return parsed.toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
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

export function HolidaySetupSection() {
  const qc = useQueryClient();
  const [customForm, setCustomForm] = useState({
    name: "",
    holiday_date: "",
    pay_multiplier: "1.0",
    ot_premium_percent: "",
    is_paid: true,
  });
  const [editingId, setEditingId] = useState<string | null>(null);
  const [seedAttempted, setSeedAttempted] = useState(false);

  const { data: holidays = [], isLoading, isError } = useQuery({
    queryKey: ["holidays"],
    queryFn: listHolidays,
  });

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
      qc.invalidateQueries({ queryKey: ["holidays"] });
      qc.invalidateQueries({ queryKey: ["setup-status"] });
    },
    onError: () => toast.error("Could not update holiday"),
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
      if (multiplier <= 0) {
        throw new Error("Please enter a holiday pay rate greater than 0");
      }
      const otPremium = parseOptionalPercent(customForm.ot_premium_percent);
      if (otPremium === false) {
        throw new Error("OT premium must be 0 or greater, or left blank");
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
      qc.invalidateQueries({ queryKey: ["holidays"] });
      qc.invalidateQueries({ queryKey: ["setup-status"] });
    },
    onError: (error: Error) => toast.error(error.message || "Could not add holiday"),
  });

  const removeCustom = useMutation({
    mutationFn: deleteHoliday,
    onSuccess: () => {
      toast.success("Holiday removed");
      setEditingId(null);
      qc.invalidateQueries({ queryKey: ["holidays"] });
      qc.invalidateQueries({ queryKey: ["setup-status"] });
    },
    onError: () => toast.error("Could not remove holiday"),
  });

  function handleMultiplierChange(holiday: Holiday, value: string) {
    const multiplier = Number(value);
    if (Number.isNaN(multiplier) || multiplier <= 0) {
      toast.error("Please enter a holiday pay rate greater than 0");
      return;
    }
    updateRow.mutate({
      id: holiday.id,
      payload: { pay_multiplier: multiplier },
    });
  }

  function handleOtPremiumChange(holiday: Holiday, value: string) {
    const parsed = parseOptionalPercent(value);
    if (parsed === false) {
      toast.error("OT premium must be 0 or greater, or left blank");
      return;
    }
    updateRow.mutate({
      id: holiday.id,
      payload: { ot_premium_percent: parsed },
    });
  }

  const defaultHolidays = useMemo(
    () => sortByDate(holidays.filter((holiday) => !isCustomHoliday(holiday))),
    [holidays]
  );
  const customHolidays = useMemo(
    () => sortByDate(holidays.filter((holiday) => isCustomHoliday(holiday))),
    [holidays]
  );

  const defaultGroups = useMemo(() => {
    const groups: { key: string; title: string; items: Holiday[] }[] = [
      { key: "regular", title: "Regular holidays", items: [] },
      { key: "special_non_working", title: "Special non-working days", items: [] },
      { key: "other", title: "Other holidays", items: [] },
    ];
    for (const holiday of defaultHolidays) {
      if (holiday.holiday_type === "regular") groups[0].items.push(holiday);
      else if (holiday.holiday_type === "special_non_working") groups[1].items.push(holiday);
      else groups[2].items.push(holiday);
    }
    return groups.filter((group) => group.items.length > 0);
  }, [defaultHolidays]);

  return (
    <div className="min-w-0 space-y-5">
      {isLoading && (
        <p className="text-sm text-[#6B7280]">Loading holidays…</p>
      )}
      {isError && (
        <WizardNotice tone="error">
          Unable to load holidays. Please try again.
        </WizardNotice>
      )}

      <WizardNotice>
        Overtime pay uses the owner OT ₱/minute rate. Ordinary days and rest
        days have no extra OT premium. Only a holiday's own OT premium below
        can increase OT pay; leave that field blank for 0%.
      </WizardNotice>

      {!isLoading && defaultHolidays.length > 0 && (
        <section className="min-w-0 space-y-3">
          <div className="flex flex-wrap items-end justify-between gap-2">
            <div className="min-w-0">
              <h3 className="owner-section-title">
                Philippine holidays
              </h3>
              <p className="owner-section-subtitle mt-0.5">
                Built-in dates used for schedules and holiday pay.
              </p>
            </div>
            <span className="rounded-full bg-[#EEF3F8] px-2.5 py-1 text-[11px] font-semibold text-[#1E3A5F]">
              {defaultHolidays.length}
            </span>
          </div>
          <div className="space-y-4">
            {defaultGroups.map((group) => (
              <HolidayGroup
                key={group.key}
                title={group.title}
                holidays={group.items}
                editingId={editingId}
                pending={updateRow.isPending || removeCustom.isPending}
                onEdit={setEditingId}
                onMultiplierChange={handleMultiplierChange}
                onOtPremiumChange={handleOtPremiumChange}
                onPaidChange={(holiday, isPaid) =>
                  updateRow.mutate({
                    id: holiday.id,
                    payload: { is_paid: isPaid },
                  })
                }
                onNameChange={(holiday, name) =>
                  updateRow.mutate({ id: holiday.id, payload: { name } })
                }
                onDateChange={(holiday, holiday_date) =>
                  updateRow.mutate({ id: holiday.id, payload: { holiday_date } })
                }
                onRemove={(id) => removeCustom.mutate(id)}
              />
            ))}
          </div>
        </section>
      )}

      {!isLoading && (
        <section className="min-w-0 space-y-3">
          <div className="flex flex-wrap items-end justify-between gap-2">
            <div className="min-w-0">
              <h3 className="owner-section-title">
                Company holidays
              </h3>
              <p className="owner-section-subtitle mt-0.5">
                Custom dates for your business, such as foundation or closure days.
              </p>
            </div>
            <span className="rounded-full bg-[#EEF3F8] px-2.5 py-1 text-[11px] font-semibold text-[#1E3A5F]">
              {customHolidays.length}
            </span>
          </div>
          {customHolidays.length > 0 ? (
            <HolidayGroup
              holidays={customHolidays}
              editingId={editingId}
              pending={updateRow.isPending || removeCustom.isPending}
              onEdit={setEditingId}
              onMultiplierChange={handleMultiplierChange}
              onOtPremiumChange={handleOtPremiumChange}
              onPaidChange={(holiday, isPaid) =>
                updateRow.mutate({
                  id: holiday.id,
                  payload: { is_paid: isPaid },
                })
              }
              onNameChange={(holiday, name) =>
                updateRow.mutate({ id: holiday.id, payload: { name } })
              }
              onDateChange={(holiday, holiday_date) =>
                updateRow.mutate({ id: holiday.id, payload: { holiday_date } })
              }
              onRemove={(id) => removeCustom.mutate(id)}
            />
          ) : (
            <div className="rounded-2xl border border-dashed border-slate-200 bg-[#FAFBFC] px-4 py-5 text-sm text-[#6B7280]">
              No custom holidays yet. Add one below.
            </div>
          )}
        </section>
      )}

      <WizardSection
        title="Add your own holiday"
        description="Use this for company holidays or special closure days."
      >
        <div className="grid gap-4 sm:grid-cols-2">
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
          <WizardField label="Date">
            <Input
              className={wizardInputClass}
              type="date"
              value={customForm.holiday_date}
              onChange={(e) =>
                setCustomForm({ ...customForm, holiday_date: e.target.value })
              }
            />
          </WizardField>
          <WizardField label="Holiday pay rate (e.g. 2 = double)">
            <Input
              className={cn(wizardInputClass, !customForm.is_paid && "opacity-50")}
              type="number"
              step="0.1"
              min="0.01"
              value={customForm.pay_multiplier}
              onChange={(e) =>
                setCustomForm({ ...customForm, pay_multiplier: e.target.value })
              }
              disabled={!customForm.is_paid}
            />
          </WizardField>
          <WizardField
            label="OT premium (%)"
            hint="Leave blank for 0% extra OT premium."
          >
            <Input
              className={wizardInputClass}
              type="number"
              min="0"
              step="0.01"
              value={customForm.ot_premium_percent}
              onChange={(e) =>
                setCustomForm({
                  ...customForm,
                  ot_premium_percent: e.target.value,
                })
              }
              placeholder="Optional"
            />
          </WizardField>
          <div className="flex items-end">
            <div className="flex w-full items-center justify-between gap-3 rounded-xl border border-slate-200/80 bg-white px-4 py-2.5">
              <span className="text-sm font-medium text-[#1F2937]">
                Employees get holiday pay
              </span>
              <div className="flex items-center gap-2">
                <span
                  className={cn(
                    "text-[11px] font-semibold uppercase tracking-wide",
                    customForm.is_paid ? "text-[#1E3A5F]" : "text-[#9CA3AF]"
                  )}
                >
                  {customForm.is_paid ? "On" : "Off"}
                </span>
                <WizardToggle
                  checked={customForm.is_paid}
                  onChange={(next) =>
                    setCustomForm({ ...customForm, is_paid: next })
                  }
                  label="Employees get holiday pay"
                />
              </div>
            </div>
          </div>
        </div>
        <Button
          className={wizardPrimaryBtnClass}
          onClick={() => addCustom.mutate()}
          disabled={addCustom.isPending}
        >
          Add holiday
        </Button>
      </WizardSection>

      <Button
        variant="outline"
        className={wizardOutlineBtnClass}
        onClick={() => seedDefaults.mutate()}
        disabled={seedDefaults.isPending}
      >
        Load Philippine holidays
      </Button>
    </div>
  );
}

function HolidayGroup({
  title,
  holidays,
  editingId,
  pending,
  onEdit,
  onPaidChange,
  onMultiplierChange,
  onOtPremiumChange,
  onNameChange,
  onDateChange,
  onRemove,
}: {
  title?: string;
  holidays: Holiday[];
  editingId: string | null;
  pending: boolean;
  onEdit: (id: string | null) => void;
  onPaidChange: (holiday: Holiday, isPaid: boolean) => void;
  onMultiplierChange: (holiday: Holiday, value: string) => void;
  onOtPremiumChange: (holiday: Holiday, value: string) => void;
  onNameChange: (holiday: Holiday, name: string) => void;
  onDateChange: (holiday: Holiday, date: string) => void;
  onRemove: (id: string) => void;
}) {
  return (
    <div className="min-w-0 overflow-hidden rounded-2xl border border-slate-200/90 bg-white">
      {title ? (
        <div className="border-b border-slate-100 bg-[#F8FAFC] px-4 py-2.5">
          <p className="text-xs font-semibold uppercase tracking-[0.12em] text-[#6B7280]">
            {title}
          </p>
        </div>
      ) : null}
      <div className="hidden grid-cols-[minmax(0,1.4fr)_7.5rem_6.5rem_5.5rem_5.5rem_minmax(0,7rem)] gap-3 px-4 py-2 text-[11px] font-semibold uppercase tracking-wide text-[#6B7280] md:grid">
        <span>Holiday</span>
        <span>Date</span>
        <span>Holiday pay</span>
        <span>Pay rate</span>
        <span>OT premium</span>
        <span className="text-right">Actions</span>
      </div>
      <ul className="divide-y divide-slate-100">
        {holidays.map((holiday) => {
          const custom = isCustomHoliday(holiday);
          const editing = editingId === holiday.id && custom;
          const typeMeta = holidayTypeMeta(holiday.holiday_type);
          return (
            <li key={holiday.id} className="px-4 py-3">
              <div className="grid min-w-0 items-center gap-3 md:grid-cols-[minmax(0,1.4fr)_7.5rem_6.5rem_5.5rem_5.5rem_minmax(0,7rem)]">
                <div className="min-w-0">
                  {editing ? (
                    <Input
                      className={wizardInputClass}
                      defaultValue={holiday.name}
                      onBlur={(e) => {
                        if (e.target.value.trim() && e.target.value !== holiday.name) {
                          onNameChange(holiday, e.target.value.trim());
                        }
                      }}
                    />
                  ) : (
                    <div className="min-w-0">
                      <p className="truncate text-sm font-medium text-[#1F2937]">
                        {holiday.name}
                      </p>
                      <div className="mt-1">
                        <Badge
                          variant="secondary"
                          className="rounded-md border-0 bg-[#EEF3F8] px-2 py-0.5 text-[10px] font-semibold text-[#1E3A5F]"
                        >
                          {custom ? "Custom" : typeMeta.label}
                        </Badge>
                      </div>
                    </div>
                  )}
                </div>
                <div className="min-w-0 text-sm text-[#374151]">
                  <p className="mb-1 text-[11px] font-semibold uppercase tracking-wide text-[#9CA3AF] md:hidden">
                    Date
                  </p>
                  {editing ? (
                    <Input
                      className={wizardInputClass}
                      type="date"
                      defaultValue={holiday.holiday_date}
                      onBlur={(e) => {
                        if (e.target.value && e.target.value !== holiday.holiday_date) {
                          onDateChange(holiday, e.target.value);
                        }
                      }}
                    />
                  ) : (
                    <span className="tabular-nums">{formatHolidayDate(holiday.holiday_date)}</span>
                  )}
                </div>
                <div className="min-w-0">
                  <p className="mb-1 text-[11px] font-semibold uppercase tracking-wide text-[#9CA3AF] md:hidden">
                    Holiday pay
                  </p>
                  <div className="flex items-center gap-2">
                    <WizardToggle
                      checked={holiday.is_paid}
                      onChange={(next) => onPaidChange(holiday, next)}
                      label={`${holiday.name} holiday pay`}
                      disabled={pending}
                    />
                    <span
                      className={cn(
                        "text-xs font-semibold",
                        holiday.is_paid ? "text-[#1E3A5F]" : "text-[#9CA3AF]"
                      )}
                    >
                      {holiday.is_paid ? "On" : "Off"}
                    </span>
                  </div>
                </div>
                <div className="min-w-0">
                  <p className="mb-1 text-[11px] font-semibold uppercase tracking-wide text-[#9CA3AF] md:hidden">
                    Pay rate
                  </p>
                  <Input
                    type="number"
                    step="0.1"
                    min="0.01"
                    className={cn(
                      wizardInputClass,
                      !holiday.is_paid && "opacity-50"
                    )}
                    defaultValue={holiday.pay_multiplier}
                    disabled={!holiday.is_paid || pending}
                    onBlur={(e) => onMultiplierChange(holiday, e.target.value)}
                  />
                </div>
                <div className="min-w-0">
                  <p className="mb-1 text-[11px] font-semibold uppercase tracking-wide text-[#9CA3AF] md:hidden">
                    OT premium
                  </p>
                  <Input
                    type="number"
                    min="0"
                    step="0.01"
                    className={wizardInputClass}
                    defaultValue={
                      holiday.ot_premium_percent == null
                        ? ""
                        : holiday.ot_premium_percent
                    }
                    placeholder="—"
                    disabled={pending}
                    onBlur={(e) => onOtPremiumChange(holiday, e.target.value)}
                  />
                </div>
                <div className="min-w-0 md:text-right">
                  {custom ? (
                    <div className="flex flex-wrap gap-2 md:justify-end">
                      <Button
                        size="sm"
                        variant="outline"
                        className="h-8 rounded-lg px-2.5 text-xs"
                        onClick={() => onEdit(editing ? null : holiday.id)}
                      >
                        {editing ? "Done" : "Edit"}
                      </Button>
                      <Button
                        size="sm"
                        variant="outline"
                        className="h-8 rounded-lg px-2.5 text-xs text-red-600 hover:bg-red-50 hover:text-red-700"
                        onClick={() => onRemove(holiday.id)}
                        disabled={pending}
                      >
                        Delete
                      </Button>
                    </div>
                  ) : (
                    <span className="text-xs text-[#9CA3AF] md:block">—</span>
                  )}
                </div>
              </div>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
