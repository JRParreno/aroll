import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useMemo, useState } from "react";
import {
  ArrowLeft,
  ArrowRight,
  BadgeDollarSign,
  BriefcaseBusiness,
  CalendarDays,
  CheckCircle2,
  Circle,
  ClipboardCheck,
  Clock3,
  MapPin,
  ShieldCheck,
} from "lucide-react";
import { useNavigate, useSearchParams } from "react-router-dom";
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
import { OwnerNotificationBell } from "@/components/owner/OwnerNotificationBell";
import { BusinessLocationSetup } from "@/components/owner/location/BusinessLocationSetup";
import { HolidaySetupSection } from "@/components/owner/setup/HolidaySetupSection";
import {
  WizardField,
  WizardNotice,
  WizardRecordList,
  WizardSection,
  WizardSelect,
  WizardSettingRow,
  WizardStepTrack,
  wizardInputClass,
  wizardOutlineBtnClass,
  wizardPrimaryBtnClass,
} from "@/components/owner/setup/wizardUi";
import {
  OwnerCard,
  OwnerPage,
  OwnerPageBackLink,
} from "@/components/owner/layout/OwnerPageLayout";
import { formatShiftTime } from "@/components/owner/schedule/scheduleUtils";
import { cn } from "@/lib/utils";
import {
  completeSetup,
  createPosition,
  createShift,
  deletePosition,
  deleteShift,
  getAttendancePolicy,
  getPayrollConfig,
  getRestDayPolicy,
  getSetupStatus,
  listPositions,
  listShifts,
  updateAttendancePolicy,
  updatePayrollConfig,
  updateRestDayPolicy,
  updateShift,
  type Shift,
} from "@/lib/api";
import { ME_QUERY_KEY } from "@/lib/authSession";

const STEPS = [
  "Work Shifts",
  "Employee Job Roles",
  "Set Up Employee Pay",
  "How Employees Time In & Out",
  "Holidays Employees Will Be Paid For",
  "Work Location",
  "Review Your Setup",
];

const STEP_STATUS_KEYS = [
  "shifts",
  "positions",
  "payroll",
  "attendance_policy",
  "holidays",
  "location",
  "review",
] as const;

function toTimeInputValue(value: string) {
  const [hour = "00", minute = "00"] = value.split(":");
  return `${String(Number(hour) || 0).padStart(2, "0")}:${String(Number(minute) || 0).padStart(2, "0")}`;
}

const STEP_HELP: Record<string, string> = {
  "Work Shifts": "Add the times your team usually works.",
  "Employee Job Roles":
    "Add the different job roles in your business, their daily pay, and optional hourly pay.",
  "Set Up Employee Pay":
    "Choose how often employees get paid and how pay is calculated.",
  "How Employees Time In & Out":
    "Set the time rules for being on time, late, absent, and overtime.",
  "Holidays Employees Will Be Paid For":
    "Add holidays your business follows so schedules and pay stay accurate.",
  "Work Location":
    "Set your workplace so employees can only time in when they are nearby.",
  "Review Your Setup":
    "Check your progress and finish when the required parts are ready.",
};

const REQUIRED_SETUP_KEYS = new Set(["shifts", "positions", "payroll", "location"]);

const STEP_ICONS = [
  Clock3,
  BriefcaseBusiness,
  BadgeDollarSign,
  ShieldCheck,
  CalendarDays,
  MapPin,
  ClipboardCheck,
] as const;

const WEEKDAYS = [
  "monday",
  "tuesday",
  "wednesday",
  "thursday",
  "friday",
  "saturday",
  "sunday",
] as const;

const SEMI_MONTHLY_PRESETS: Record<string, [number, number]> = {
  "15_30": [15, 30],
  "10_25": [10, 25],
  "5_20": [5, 20],
};

function presetForDays(day1: string, day2: string): string {
  for (const [preset, [d1, d2]] of Object.entries(SEMI_MONTHLY_PRESETS)) {
    if (Number(day1) === d1 && Number(day2) === d2) return preset;
  }
  return "custom";
}

/** Days 29-31 mean "last day" in shorter months (e.g. the 30th in February). */
function clampedDate(year: number, monthIndex: number, day: number): Date {
  const lastDay = new Date(year, monthIndex + 1, 0).getDate();
  return new Date(year, monthIndex, Math.min(day, lastDay));
}

function toIsoDate(d: Date): string {
  const month = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${d.getFullYear()}-${month}-${day}`;
}

function computeNextPayday(form: {
  pay_period_type: string;
  weekly_payday_weekday: string;
  semi_monthly_payday_1: string;
  semi_monthly_payday_2: string;
  monthly_payday_day: string;
}): string {
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  if (form.pay_period_type === "weekly") {
    const target = WEEKDAYS.indexOf(
      form.weekly_payday_weekday as (typeof WEEKDAYS)[number]
    );
    if (target < 0) return "";
    // Date#getDay is 0=Sunday; our list starts at Monday.
    const targetDow = (target + 1) % 7;
    const next = new Date(today);
    next.setDate(next.getDate() + ((targetDow - next.getDay() + 7) % 7));
    return toIsoDate(next);
  }

  if (form.pay_period_type === "semi_monthly") {
    const day1 = Number(form.semi_monthly_payday_1);
    const day2 = Number(form.semi_monthly_payday_2);
    if (!day1 || !day2) return "";
    const candidates = [
      clampedDate(today.getFullYear(), today.getMonth(), day1),
      clampedDate(today.getFullYear(), today.getMonth(), day2),
      clampedDate(today.getFullYear(), today.getMonth() + 1, day1),
    ];
    const next = candidates.find((d) => d >= today);
    return next ? toIsoDate(next) : "";
  }

  if (form.pay_period_type === "monthly") {
    const day = Number(form.monthly_payday_day);
    if (!day) return "";
    const thisMonth = clampedDate(today.getFullYear(), today.getMonth(), day);
    const next =
      thisMonth >= today
        ? thisMonth
        : clampedDate(today.getFullYear(), today.getMonth() + 1, day);
    return toIsoDate(next);
  }

  return "";
}

export function OwnerSetupWizardPage() {
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const qc = useQueryClient();
  const rawStep = searchParams.get("step");
  const isMenu = rawStep === null || rawStep === "menu";
  const initialStep = isMenu
    ? -1
    : Math.min(Math.max(Number(rawStep ?? "0"), 0), STEPS.length - 1);
  const [step, setStep] = useState(initialStep);

  function goToStep(next: number) {
    if (next < 0) {
      setSearchParams({ step: "menu" });
      setStep(-1);
      return;
    }
    setSearchParams({ step: String(next) });
    setStep(next);
  }

  const { data: shifts = [], refetch: refetchShifts } = useQuery({
    queryKey: ["shifts"],
    queryFn: listShifts,
  });
  const { data: positions = [], refetch: refetchPositions } = useQuery({
    queryKey: ["positions"],
    queryFn: listPositions,
  });
  const { data: payroll } = useQuery({
    queryKey: ["payroll-config"],
    queryFn: getPayrollConfig,
  });
  const { data: attendancePolicy } = useQuery({
    queryKey: ["attendance-policy"],
    queryFn: getAttendancePolicy,
  });
  const { data: restDayPolicy } = useQuery({
    queryKey: ["rest-day-policy"],
    queryFn: getRestDayPolicy,
  });
  const { data: setupStatus } = useQuery({
    queryKey: ["setup-status"],
    queryFn: getSetupStatus,
  });

  const [shiftForm, setShiftForm] = useState({
    name: "",
    shift_type: "morning",
    start_time: "06:00",
    end_time: "14:00",
    break_minutes: "0",
    employee_capacity: "1",
  });
  const [editingShift, setEditingShift] = useState<Shift | null>(null);
  const [editTimes, setEditTimes] = useState({ start_time: "", end_time: "" });
  const [posForm, setPosForm] = useState({
    title: "",
    daily_rate: "",
    hourly_rate: "",
    description: "",
  });
  const [payrollForm, setPayrollForm] = useState({
    pay_period_type: "monthly",
    auto_reset_payroll_cycle: true,
    late_deduction_enabled: true,
    late_deduction_per_minute: "1",
    overtime_enabled: true,
    overtime_per_minute: "1",
    enable_late_overtime_balancing: false,
    weekly_payday_weekday: "friday",
    semi_monthly_preset: "15_30",
    semi_monthly_payday_1: "15",
    semi_monthly_payday_2: "30",
    monthly_payday_day: "30",
    holiday_rules_mode: "philippine_labor" as "philippine_labor" | "custom_company",
  });
  const [attForm, setAttForm] = useState({
    early_clock_in_minutes: "15",
    on_time_grace_minutes: "10",
    half_day_threshold_minutes: "120",
    absent_threshold_minutes: "240",
    absent_threshold_percent: "25",
    half_day_threshold_percent: "50",
    early_out_deduction_enabled: false,
    early_out_deduction_per_minute: "2",
    overtime_enabled: true,
    overtime_minimum_minutes: "30",
    maximum_overtime_minutes: "180",
    missing_clock_out_policy: "auto_clock_out",
    attendance_based_salary_enabled: true,
  });
  const [restForm, setRestForm] = useState({
    rest_day_premium_percent: "30",
  });

  useEffect(() => {
    if (!payroll) return;
    const day1 = String(payroll.semi_monthly_payday_1 ?? 15);
    const day2 = String(payroll.semi_monthly_payday_2 ?? 30);
    setPayrollForm({
      pay_period_type: payroll.pay_period_type,
      auto_reset_payroll_cycle: payroll.auto_reset_payroll_cycle,
      late_deduction_enabled: payroll.late_deduction_enabled,
      late_deduction_per_minute: String(payroll.late_deduction_per_minute),
      overtime_enabled: payroll.overtime_enabled,
      overtime_per_minute: String(payroll.overtime_per_minute),
      enable_late_overtime_balancing:
        payroll.enable_late_overtime_balancing === true,
      holiday_rules_mode:
        payroll.holiday_rules_mode === "custom_company"
          ? "custom_company"
          : "philippine_labor",
      weekly_payday_weekday: payroll.weekly_payday_weekday ?? "friday",
      semi_monthly_preset: presetForDays(day1, day2),
      semi_monthly_payday_1: day1,
      semi_monthly_payday_2: day2,
      monthly_payday_day: String(payroll.monthly_payday_day ?? 30),
    });
  }, [payroll]);

  useEffect(() => {
    if (!attendancePolicy) return;
    setAttForm({
      early_clock_in_minutes: String(attendancePolicy.early_clock_in_minutes),
      on_time_grace_minutes: String(attendancePolicy.on_time_grace_minutes),
      half_day_threshold_minutes: String(
        attendancePolicy.half_day_threshold_minutes
      ),
      absent_threshold_minutes: String(attendancePolicy.absent_threshold_minutes),
      absent_threshold_percent: String(
        attendancePolicy.absent_threshold_percent ?? 25
      ),
      half_day_threshold_percent: String(
        attendancePolicy.half_day_threshold_percent ?? 50
      ),
      early_out_deduction_enabled: attendancePolicy.early_out_deduction_enabled,
      early_out_deduction_per_minute: String(
        attendancePolicy.early_out_deduction_per_minute
      ),
      overtime_enabled: attendancePolicy.overtime_enabled,
      overtime_minimum_minutes: String(attendancePolicy.overtime_minimum_minutes),
      maximum_overtime_minutes: String(
        attendancePolicy.maximum_overtime_minutes ?? 180
      ),
      missing_clock_out_policy: attendancePolicy.missing_clock_out_policy,
      attendance_based_salary_enabled:
        attendancePolicy.attendance_based_salary_enabled,
    });
  }, [attendancePolicy]);

  useEffect(() => {
    if (!restDayPolicy) return;
    setRestForm({
      rest_day_premium_percent: String(restDayPolicy.rest_day_premium_percent),
    });
  }, [restDayPolicy]);

  const canCompleteSetup = useMemo(() => {
    if (!setupStatus) return false;
    return setupStatus.steps
      .filter((step) => REQUIRED_SETUP_KEYS.has(step.key))
      .every((step) => step.complete);
  }, [setupStatus]);

  const setupStepComplete = useMemo(() => {
    const map = new Map<string, boolean>();
    for (const item of setupStatus?.steps ?? []) {
      map.set(item.key, item.complete);
    }
    return map;
  }, [setupStatus]);

  const isStepComplete = (key: string) => setupStepComplete.get(key) === true;

  const shiftDraftValid =
    shiftForm.name.trim().length > 0 &&
    Boolean(shiftForm.start_time) &&
    Boolean(shiftForm.end_time) &&
    Number(shiftForm.break_minutes) >= 0 &&
    Number(shiftForm.employee_capacity) >= 1;

  const positionDraftValid =
    posForm.title.trim().length > 0 &&
    Number(posForm.daily_rate) > 0 &&
    (!posForm.hourly_rate.trim() || Number(posForm.hourly_rate) > 0);

  const nextPaydayDate = useMemo(
    () => computeNextPayday(payrollForm),
    [payrollForm]
  );

  const paydayScheduleValid = useMemo(() => {
    switch (payrollForm.pay_period_type) {
      case "weekly":
        return WEEKDAYS.includes(
          payrollForm.weekly_payday_weekday as (typeof WEEKDAYS)[number]
        );
      case "semi_monthly": {
        const day1 = Number(payrollForm.semi_monthly_payday_1);
        const day2 = Number(payrollForm.semi_monthly_payday_2);
        return day1 >= 1 && day2 <= 31 && day2 > day1;
      }
      case "monthly": {
        const day = Number(payrollForm.monthly_payday_day);
        return day >= 1 && day <= 31;
      }
      default:
        return false;
    }
  }, [payrollForm]);

  const payrollFormValid =
    paydayScheduleValid &&
    Boolean(nextPaydayDate) &&
    Number(payrollForm.late_deduction_per_minute) >= 0 &&
    Number(payrollForm.overtime_per_minute) >= 0 &&
    Number(restForm.rest_day_premium_percent) >= 0;

  const currentStepCanContinue = useMemo(() => {
    switch (step) {
      case 0:
        return isStepComplete("shifts") || shiftDraftValid;
      case 1:
        return isStepComplete("positions") || positionDraftValid;
      case 2:
        return isStepComplete("payroll") || payrollFormValid;
      case 3:
        return isStepComplete("attendance_policy");
      case 4:
        return isStepComplete("holidays");
      case 5:
        return isStepComplete("location");
      default:
        return false;
    }
  }, [
    step,
    setupStepComplete,
    shiftDraftValid,
    positionDraftValid,
    payrollFormValid,
  ]);

  const addShift = useMutation({
    mutationFn: () =>
      createShift({
        name: shiftForm.name,
        shift_type: shiftForm.shift_type,
        start_time: shiftForm.start_time,
        end_time: shiftForm.end_time,
        break_minutes: Number(shiftForm.break_minutes),
        employee_capacity: Number(shiftForm.employee_capacity),
      }),
    onSuccess: () => {
      toast.success("Work shift added");
      setShiftForm({ ...shiftForm, name: "" });
      refetchShifts();
      qc.invalidateQueries({ queryKey: ["setup-status"] });
    },
  });

  const saveShiftTimes = useMutation({
    mutationFn: () => {
      if (!editingShift) throw new Error("No shift selected");
      return updateShift(editingShift.id, {
        start_time: editTimes.start_time,
        end_time: editTimes.end_time,
      });
    },
    onSuccess: () => {
      toast.success("Shift times updated");
      setEditingShift(null);
      refetchShifts();
      qc.invalidateQueries({ queryKey: ["shifts"] });
      qc.invalidateQueries({ queryKey: ["weekly-schedule"] });
    },
    onError: () => toast.error("Could not update shift times"),
  });

  function openEditShiftTimes(shift: Shift) {
    setEditingShift(shift);
    setEditTimes({
      start_time: toTimeInputValue(shift.start_time),
      end_time: toTimeInputValue(shift.end_time),
    });
  }

  const addPosition = useMutation({
    mutationFn: () =>
      createPosition({
        title: posForm.title,
        daily_rate: Number(posForm.daily_rate),
        hourly_rate: posForm.hourly_rate.trim()
          ? Number(posForm.hourly_rate)
          : undefined,
        description: posForm.description || undefined,
      }),
    onSuccess: () => {
      toast.success("Job role added");
      setPosForm({ title: "", daily_rate: "", hourly_rate: "", description: "" });
      refetchPositions();
      qc.invalidateQueries({ queryKey: ["setup-status"] });
    },
  });

  const savePayroll = useMutation({
    mutationFn: () =>
      Promise.all([
        updatePayrollConfig({
          pay_period_type: payrollForm.pay_period_type,
          next_payday_date: nextPaydayDate || null,
          auto_reset_payroll_cycle: payrollForm.auto_reset_payroll_cycle,
          late_deduction_enabled: payrollForm.late_deduction_enabled,
          late_deduction_per_minute: Number(
            payrollForm.late_deduction_per_minute
          ),
          overtime_enabled: payrollForm.overtime_enabled,
          overtime_per_minute: Number(payrollForm.overtime_per_minute),
          enable_late_overtime_balancing:
            payrollForm.enable_late_overtime_balancing,
          holiday_rules_mode: payrollForm.holiday_rules_mode,
          weekly_payday_weekday:
            payrollForm.pay_period_type === "weekly"
              ? payrollForm.weekly_payday_weekday
              : null,
          semi_monthly_payday_1:
            payrollForm.pay_period_type === "semi_monthly"
              ? Number(payrollForm.semi_monthly_payday_1)
              : null,
          semi_monthly_payday_2:
            payrollForm.pay_period_type === "semi_monthly"
              ? Number(payrollForm.semi_monthly_payday_2)
              : null,
          monthly_payday_day:
            payrollForm.pay_period_type === "monthly"
              ? Number(payrollForm.monthly_payday_day)
              : null,
        }),
        updateRestDayPolicy({
          rest_day_premium_percent: Number(
            restForm.rest_day_premium_percent
          ),
        }),
      ]),
    onSuccess: () => {
      toast.success("Pay settings saved");
      qc.invalidateQueries({ queryKey: ["setup-status"] });
      qc.invalidateQueries({ queryKey: ["payroll-config"] });
      qc.invalidateQueries({ queryKey: ["owner-payroll-report"] });
      qc.invalidateQueries({ queryKey: ["rest-day-policy"] });
    },
  });

  const saveAttendance = useMutation({
    mutationFn: () =>
      updateAttendancePolicy({
        early_clock_in_minutes: Number(attForm.early_clock_in_minutes),
        on_time_grace_minutes: Number(attForm.on_time_grace_minutes),
        half_day_threshold_minutes: Number(attForm.half_day_threshold_minutes),
        absent_threshold_minutes: Number(attForm.absent_threshold_minutes),
        absent_threshold_percent: Number(attForm.absent_threshold_percent),
        half_day_threshold_percent: Number(attForm.half_day_threshold_percent),
        early_out_deduction_enabled: attForm.early_out_deduction_enabled,
        early_out_deduction_per_minute: Number(
          attForm.early_out_deduction_per_minute
        ),
        overtime_minimum_minutes: Number(attForm.overtime_minimum_minutes),
        maximum_overtime_minutes: Number(attForm.maximum_overtime_minutes),
        missing_clock_out_policy: attForm.missing_clock_out_policy,
        attendance_based_salary_enabled: attForm.attendance_based_salary_enabled,
      }),
    onSuccess: () => {
      toast.success("Time-in settings saved");
      qc.invalidateQueries({ queryKey: ["setup-status"] });
      qc.invalidateQueries({ queryKey: ["attendance-policy"] });
    },
  });

  const finishSetup = useMutation({
    mutationFn: completeSetup,
    onSuccess: () => {
      toast.success("Setup finished");
      localStorage.removeItem("aroll_setup_card_dismissed");
      qc.invalidateQueries({ queryKey: ["setup-status"] });
      qc.invalidateQueries({ queryKey: ME_QUERY_KEY });
      navigate("/owner/dashboard");
    },
    onError: (error: unknown) => {
      const detail =
        error &&
        typeof error === "object" &&
        "response" in error &&
        error.response &&
        typeof error.response === "object" &&
        "data" in error.response &&
        error.response.data &&
        typeof error.response.data === "object" &&
        "detail" in error.response.data
          ? error.response.data.detail
          : null;
      const missing =
        detail &&
        typeof detail === "object" &&
        "missing_items" in detail &&
        Array.isArray(detail.missing_items)
          ? detail.missing_items.join(", ")
          : null;
      toast.error(missing ?? "Please finish the required setup steps first");
      qc.invalidateQueries({ queryKey: ["setup-status"] });
    },
  });

  const continuePending =
    addShift.isPending || addPosition.isPending || savePayroll.isPending;

  async function handleContinue() {
    if (!currentStepCanContinue) {
      if (step === 5 && !isStepComplete("location")) {
        toast.error("Save your workplace location before continuing.");
      }
      return;
    }

    try {
      if (step === 0 && !isStepComplete("shifts") && shiftDraftValid) {
        await addShift.mutateAsync();
      }
      if (step === 1 && !isStepComplete("positions") && positionDraftValid) {
        await addPosition.mutateAsync();
      }
      if (step === 2 && !isStepComplete("payroll") && payrollFormValid) {
        await savePayroll.mutateAsync();
      }
      goToStep(Math.min(step + 1, STEPS.length - 1));
    } catch {
      toast.error("Please save this step before continuing.");
    }
  }

  const countableSteps = STEP_STATUS_KEYS.filter((key) => key !== "review");
  const completedCount = countableSteps.filter((key) => isStepComplete(key)).length;
  const wizardProgress =
    step < 0
      ? (setupStatus?.completion_percent ?? 0)
      : Math.round(((step + 1) / STEPS.length) * 100);
  const stepCompleteFlags = STEP_STATUS_KEYS.map((key) => isStepComplete(key));

  return (
    <OwnerPage className="flex min-h-full flex-col">
      <header className="sticky top-0 z-10 border-b border-slate-200/80 bg-white/95 backdrop-blur-sm">
        <div className="mx-auto w-full min-w-0 max-w-6xl px-5 py-3 sm:px-8">
          {step < 0 ? (
            <OwnerPageBackLink
              to="/owner/settings/setup"
              label="Back to Business Setup"
            />
          ) : (
            <button
              className="inline-flex items-center gap-2 rounded-lg px-1 py-0.5 text-sm font-medium text-[#6B7280] transition-colors hover:bg-[#F8FAFC] hover:text-[#1E3A5F]"
              onClick={() => goToStep(-1)}
              type="button"
            >
              <ArrowLeft className="h-4 w-4" />
              Back to setup menu
            </button>
          )}

          <div className="mt-2 flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div className="min-w-0">
              <h1 className="owner-page-title">
                Set Up Your Business
              </h1>
              <p className="owner-section-subtitle mt-1.5 max-w-2xl">
                {step < 0
                  ? "Choose a section below to set up. You can return anytime from Business Setup."
                  : STEP_HELP[STEPS[step]]}
              </p>
            </div>
            <div className="flex shrink-0 items-start gap-3">
              <div className="w-full sm:w-[14.5rem]">
                <div className="flex items-center justify-between gap-3 text-xs">
                  <p className="font-medium text-[#1F2937]">
                    {step < 0
                      ? `${completedCount} of ${countableSteps.length} complete`
                      : `Step ${step + 1} of ${STEPS.length}`}
                  </p>
                  <p className="tabular-nums text-[#6B7280]">{wizardProgress}%</p>
                </div>
                <div className="mt-1.5 h-1.5 overflow-hidden rounded-full bg-[#E5E7EB]">
                  <div
                    className="h-full rounded-full bg-[#1E3A5F] transition-[width] duration-300"
                    style={{ width: `${Math.min(Math.max(wizardProgress, 0), 100)}%` }}
                  />
                </div>
                {step >= 0 ? (
                  <p className="mt-1 truncate text-[11px] font-medium text-[#1E3A5F]">
                    {STEPS[step]}
                  </p>
                ) : (
                  <p className="mt-1 text-[11px] text-[#6B7280]">
                    {setupStatus?.completion_percent ?? 0}% of required setup
                  </p>
                )}
              </div>
              <OwnerNotificationBell />
            </div>
          </div>

          {step >= 0 ? (
            <WizardStepTrack
              current={step}
              labels={STEPS}
              complete={stepCompleteFlags}
              onSelect={goToStep}
            />
          ) : null}
        </div>
      </header>

      <div className="mx-auto w-full min-w-0 max-w-6xl flex-1 overflow-x-hidden px-5 py-6 sm:px-8">
        {step < 0 ? (
          <div className="grid gap-4 sm:grid-cols-2">
            {STEPS.map((label, index) => {
              const key = STEP_STATUS_KEYS[index];
              const complete = key ? isStepComplete(key) : false;
              const Icon = STEP_ICONS[index] ?? ClipboardCheck;
              return (
                <button
                  key={label}
                  type="button"
                  onClick={() => goToStep(index)}
                  className="owner-card p-5 text-left transition hover:border-[#B9C7D8] hover:bg-[#FAFBFC]"
                >
                  <div className="flex items-start gap-3">
                    <span className="owner-icon-well h-10 w-10 shrink-0">
                      <Icon className="h-4 w-4" />
                    </span>
                    <div className="min-w-0 flex-1">
                      <p className="owner-label uppercase tracking-[0.12em] text-[#6B7280]">
                        Step {index + 1}
                      </p>
                      <p className="owner-section-title mt-1">{label}</p>
                      <p className="owner-section-subtitle mt-1">
                        {STEP_HELP[label]}
                      </p>
                    </div>
                    {complete ? (
                      <CheckCircle2 className="h-5 w-5 shrink-0 text-emerald-600" />
                    ) : (
                      <Circle className="h-5 w-5 shrink-0 text-[#9CA3AF]" />
                    )}
                  </div>
                </button>
              );
            })}
          </div>
        ) : (
          <OwnerCard className="min-w-0 p-5 sm:p-6">
            <div className="min-w-0 space-y-5">
              <div className="min-w-0">
                <h2 className="owner-section-title text-base sm:text-lg">
                  {STEPS[step]}
                </h2>
              </div>
            {step === 0 && (
              <>
                <div className="grid gap-4 sm:grid-cols-2">
                  <WizardField label="Shift name">
                    <Input
                      className={wizardInputClass}
                      value={shiftForm.name}
                      onChange={(e) =>
                        setShiftForm({ ...shiftForm, name: e.target.value })
                      }
                      placeholder="Morning Shift"
                    />
                  </WizardField>
                  <WizardField label="Shift type">
                    <WizardSelect
                      value={shiftForm.shift_type}
                      onChange={(e) =>
                        setShiftForm({ ...shiftForm, shift_type: e.target.value })
                      }
                    >
                      <option value="morning">Morning</option>
                      <option value="afternoon">Afternoon</option>
                      <option value="evening">Evening</option>
                      <option value="night">Night</option>
                    </WizardSelect>
                  </WizardField>
                  <WizardField label="Start time">
                    <Input
                      className={wizardInputClass}
                      type="time"
                      value={shiftForm.start_time}
                      onChange={(e) =>
                        setShiftForm({ ...shiftForm, start_time: e.target.value })
                      }
                    />
                  </WizardField>
                  <WizardField label="End time">
                    <Input
                      className={wizardInputClass}
                      type="time"
                      value={shiftForm.end_time}
                      onChange={(e) =>
                        setShiftForm({ ...shiftForm, end_time: e.target.value })
                      }
                    />
                  </WizardField>
                  <WizardField label="Break minutes">
                    <Input
                      className={wizardInputClass}
                      type="number"
                      value={shiftForm.break_minutes}
                      onChange={(e) =>
                        setShiftForm({
                          ...shiftForm,
                          break_minutes: e.target.value,
                        })
                      }
                    />
                  </WizardField>
                  <WizardField label="Employees needed">
                    <Input
                      className={wizardInputClass}
                      type="number"
                      value={shiftForm.employee_capacity}
                      onChange={(e) =>
                        setShiftForm({
                          ...shiftForm,
                          employee_capacity: e.target.value,
                        })
                      }
                    />
                  </WizardField>
                </div>
                <Button
                  className={wizardPrimaryBtnClass}
                  onClick={() => addShift.mutate()}
                  disabled={!shiftForm.name || addShift.isPending}
                >
                  Add work shift
                </Button>
                <WizardRecordList empty="No work shifts yet. Add one above.">
                  {shifts.map((s) => (
                    <li
                      key={s.id}
                      className="flex items-center justify-between gap-3 px-4 py-3"
                    >
                      <div className="min-w-0">
                        <p className="truncate font-medium text-[#1F2937]">{s.name}</p>
                        <p className="mt-0.5 text-xs text-[#6B7280]">
                          {formatShiftTime(s.start_time)}–{formatShiftTime(s.end_time)}
                        </p>
                      </div>
                      <div className="flex shrink-0 items-center gap-2">
                        <Button
                          size="sm"
                          variant="outline"
                          className="h-8 rounded-lg px-2.5 text-xs"
                          onClick={() => openEditShiftTimes(s)}
                        >
                          Edit times
                        </Button>
                        <Button
                          size="sm"
                          variant="outline"
                          className="h-8 rounded-lg px-2.5 text-xs"
                          onClick={() =>
                            deleteShift(s.id).then(() => refetchShifts())
                          }
                        >
                          Remove
                        </Button>
                      </div>
                    </li>
                  ))}
                </WizardRecordList>
              </>
            )}

            {step === 1 && (
              <>
                <div className="grid gap-4 sm:grid-cols-2">
                  <WizardField label="Job role name" className="sm:col-span-2">
                    <Input
                      className={wizardInputClass}
                      value={posForm.title}
                      onChange={(e) =>
                        setPosForm({ ...posForm, title: e.target.value })
                      }
                    />
                  </WizardField>
                  <WizardField label="Daily pay (₱)">
                    <Input
                      className={wizardInputClass}
                      type="number"
                      value={posForm.daily_rate}
                      onChange={(e) =>
                        setPosForm({ ...posForm, daily_rate: e.target.value })
                      }
                    />
                  </WizardField>
                  <WizardField label="Hourly pay (₱, optional)">
                    <Input
                      className={wizardInputClass}
                      type="number"
                      value={posForm.hourly_rate}
                      onChange={(e) =>
                        setPosForm({ ...posForm, hourly_rate: e.target.value })
                      }
                    />
                  </WizardField>
                  <WizardField label="Description" className="sm:col-span-2">
                    <Input
                      className={wizardInputClass}
                      value={posForm.description}
                      onChange={(e) =>
                        setPosForm({ ...posForm, description: e.target.value })
                      }
                    />
                  </WizardField>
                </div>
                <Button
                  className={wizardPrimaryBtnClass}
                  onClick={() => addPosition.mutate()}
                  disabled={!positionDraftValid}
                >
                  Add job role
                </Button>
                <WizardRecordList empty="No job roles yet. Add one above.">
                  {positions.map((p) => (
                    <li
                      key={p.id}
                      className="flex items-center justify-between gap-3 px-4 py-3"
                    >
                      <div className="min-w-0">
                        <p className="truncate font-medium text-[#1F2937]">{p.title}</p>
                        <p className="mt-0.5 text-xs text-[#6B7280]">
                          ₱{p.daily_rate}/day
                          {p.hourly_rate != null ? ` · ₱${p.hourly_rate}/hr` : ""}
                        </p>
                      </div>
                      <Button
                        size="sm"
                        variant="outline"
                        className="h-8 rounded-lg px-2.5 text-xs"
                        onClick={() =>
                          deletePosition(p.id).then(() => refetchPositions())
                        }
                      >
                        Remove
                      </Button>
                    </li>
                  ))}
                </WizardRecordList>
              </>
            )}

            {step === 2 && (
              <>
                <WizardSection title="Payday schedule">
                  <div className="grid gap-4 sm:grid-cols-2">
                    <WizardField label="How often employees get paid">
                      <WizardSelect
                        value={payrollForm.pay_period_type}
                        onChange={(e) =>
                          setPayrollForm({
                            ...payrollForm,
                            pay_period_type: e.target.value,
                          })
                        }
                      >
                        <option value="weekly">Weekly</option>
                        <option value="semi_monthly">Twice a month</option>
                        <option value="monthly">Monthly</option>
                      </WizardSelect>
                    </WizardField>
                    {payrollForm.pay_period_type === "weekly" && (
                      <WizardField label="Payday">
                        <WizardSelect
                          value={payrollForm.weekly_payday_weekday}
                          onChange={(e) =>
                            setPayrollForm({
                              ...payrollForm,
                              weekly_payday_weekday: e.target.value,
                            })
                          }
                        >
                          {WEEKDAYS.map((d) => (
                            <option key={d} value={d}>
                              Every {d.charAt(0).toUpperCase() + d.slice(1)}
                            </option>
                          ))}
                        </WizardSelect>
                      </WizardField>
                    )}

                    {payrollForm.pay_period_type === "semi_monthly" && (
                      <WizardField label="Payday Schedule">
                        <WizardSelect
                          value={payrollForm.semi_monthly_preset}
                          onChange={(e) => {
                            const preset = e.target.value;
                            const days = SEMI_MONTHLY_PRESETS[preset];
                            setPayrollForm({
                              ...payrollForm,
                              semi_monthly_preset: preset,
                              semi_monthly_payday_1: days
                                ? String(days[0])
                                : payrollForm.semi_monthly_payday_1,
                              semi_monthly_payday_2: days
                                ? String(days[1])
                                : payrollForm.semi_monthly_payday_2,
                            });
                          }}
                        >
                          <option value="15_30">
                            Every 15th &amp; 30th (end of month)
                          </option>
                          <option value="10_25">Every 10th &amp; 25th</option>
                          <option value="5_20">Every 5th &amp; 20th</option>
                          <option value="custom">Custom days…</option>
                        </WizardSelect>
                      </WizardField>
                    )}

                    {payrollForm.pay_period_type === "monthly" && (
                      <WizardField
                        label="Payday (day of month)"
                        hint='Use 31 for "last day of the month".'
                      >
                        <Input
                          className={wizardInputClass}
                          type="number"
                          min="1"
                          max="31"
                          value={payrollForm.monthly_payday_day}
                          onChange={(e) =>
                            setPayrollForm({
                              ...payrollForm,
                              monthly_payday_day: e.target.value,
                            })
                          }
                        />
                      </WizardField>
                    )}

                    {payrollForm.pay_period_type === "semi_monthly" &&
                      payrollForm.semi_monthly_preset === "custom" && (
                        <>
                          <WizardField label="First Payday (day of month)">
                            <Input
                              className={wizardInputClass}
                              type="number"
                              min="1"
                              max="15"
                              value={payrollForm.semi_monthly_payday_1}
                              onChange={(e) =>
                                setPayrollForm({
                                  ...payrollForm,
                                  semi_monthly_payday_1: e.target.value,
                                })
                              }
                            />
                          </WizardField>
                          <WizardField label="Second Payday (day of month)">
                            <Input
                              className={wizardInputClass}
                              type="number"
                              min="16"
                              max="31"
                              value={payrollForm.semi_monthly_payday_2}
                              onChange={(e) =>
                                setPayrollForm({
                                  ...payrollForm,
                                  semi_monthly_payday_2: e.target.value,
                                })
                              }
                            />
                          </WizardField>
                        </>
                      )}
                  </div>
                  <WizardNotice>
                    {nextPaydayDate ? (
                      <>
                        Next payday:{" "}
                        <span className="font-medium text-[#1F2937]">
                          {new Date(`${nextPaydayDate}T00:00:00`).toLocaleDateString(
                            undefined,
                            {
                              weekday: "long",
                              year: "numeric",
                              month: "long",
                              day: "numeric",
                            }
                          )}
                        </span>{" "}
                        — calculated from the schedule above.
                      </>
                    ) : (
                      "Choose a valid payday schedule to see the next payday."
                    )}
                  </WizardNotice>
                  <WizardSettingRow
                    title="Start a new pay period after payday"
                    checked={payrollForm.auto_reset_payroll_cycle}
                    onChange={(next) =>
                      setPayrollForm({
                        ...payrollForm,
                        auto_reset_payroll_cycle: next,
                      })
                    }
                  />
                </WizardSection>

                <WizardSection
                  title="Holiday pay rules"
                  description="Choose how unworked and worked holidays are paid."
                >
                  <div className="space-y-2">
                    <label
                      className={cn(
                        "flex cursor-pointer items-start gap-3 rounded-xl border bg-white px-4 py-3 text-sm",
                        payrollForm.holiday_rules_mode === "philippine_labor"
                          ? "border-[#1E3A5F]/30 bg-[#F4F8FC]"
                          : "border-slate-200"
                      )}
                    >
                      <input
                        type="radio"
                        className="mt-1"
                        name="holiday_rules_mode"
                        checked={
                          payrollForm.holiday_rules_mode === "philippine_labor"
                        }
                        onChange={() =>
                          setPayrollForm({
                            ...payrollForm,
                            holiday_rules_mode: "philippine_labor",
                          })
                        }
                      />
                      <span>
                        <span className="font-medium text-[#1F2937]">
                          Philippine labor rules
                        </span>
                        <span className="mt-0.5 block text-xs text-[#6B7280]">
                          Regular holidays pay even if unworked. Special
                          holidays follow no-work-no-pay unless worked.
                        </span>
                      </span>
                    </label>
                    <label
                      className={cn(
                        "flex cursor-pointer items-start gap-3 rounded-xl border bg-white px-4 py-3 text-sm",
                        payrollForm.holiday_rules_mode === "custom_company"
                          ? "border-[#1E3A5F]/30 bg-[#F4F8FC]"
                          : "border-slate-200"
                      )}
                    >
                      <input
                        type="radio"
                        className="mt-1"
                        name="holiday_rules_mode"
                        checked={
                          payrollForm.holiday_rules_mode === "custom_company"
                        }
                        onChange={() =>
                          setPayrollForm({
                            ...payrollForm,
                            holiday_rules_mode: "custom_company",
                          })
                        }
                      />
                      <span>
                        <span className="font-medium text-[#1F2937]">
                          Custom company rules
                        </span>
                        <span className="mt-0.5 block text-xs text-[#6B7280]">
                          Use each holiday&apos;s Paid flag and pay multiplier
                          only.
                        </span>
                      </span>
                    </label>
                  </div>
                </WizardSection>

                <WizardSection title="Pay rules">
                  <WizardSettingRow
                    title="Pay less when late"
                    checked={payrollForm.late_deduction_enabled}
                    onChange={(next) =>
                      setPayrollForm({
                        ...payrollForm,
                        late_deduction_enabled: next,
                      })
                    }
                  />
                  <WizardField label="Amount per late minute (₱)">
                    <Input
                      className={wizardInputClass}
                      type="number"
                      step="0.01"
                      min="0"
                      value={payrollForm.late_deduction_per_minute}
                      onChange={(e) =>
                        setPayrollForm({
                          ...payrollForm,
                          late_deduction_per_minute: e.target.value,
                        })
                      }
                      disabled={!payrollForm.late_deduction_enabled}
                    />
                  </WizardField>
                  <WizardSettingRow
                    title="Pay for overtime"
                    checked={payrollForm.overtime_enabled}
                    onChange={(next) =>
                      setPayrollForm({
                        ...payrollForm,
                        overtime_enabled: next,
                      })
                    }
                  />
                  <WizardField label="Extra pay per overtime minute (₱)">
                    <Input
                      className={wizardInputClass}
                      type="number"
                      step="0.01"
                      min="0"
                      value={payrollForm.overtime_per_minute}
                      onChange={(e) =>
                        setPayrollForm({
                          ...payrollForm,
                          overtime_per_minute: e.target.value,
                        })
                      }
                      disabled={!payrollForm.overtime_enabled}
                    />
                  </WizardField>
                  <WizardSettingRow
                    title="Late–OT Balancing"
                    description="When enabled, overtime minutes are first used to recover late arrival. Only the remaining overtime minutes are paid."
                    checked={payrollForm.enable_late_overtime_balancing}
                    onChange={(next) =>
                      setPayrollForm({
                        ...payrollForm,
                        enable_late_overtime_balancing: next,
                      })
                    }
                    disabled={!payrollForm.overtime_enabled}
                  />
                </WizardSection>

                <WizardSection
                  title="Extra pay on rest days"
                  description="Set the extra pay when an employee works on an approved rest day."
                >
                  <WizardField
                    label="Extra pay (%)"
                    className="sm:max-w-xs"
                    hint="Example: 30% adds 0.30 × the employee's daily pay."
                  >
                    <Input
                      className={wizardInputClass}
                      type="number"
                      min="0"
                      value={restForm.rest_day_premium_percent}
                      onChange={(e) =>
                        setRestForm({
                          ...restForm,
                          rest_day_premium_percent: e.target.value,
                        })
                      }
                    />
                  </WizardField>
                </WizardSection>

                <Button
                  className={wizardPrimaryBtnClass}
                  onClick={() => savePayroll.mutate()}
                  disabled={!payrollFormValid || savePayroll.isPending}
                >
                  Save Pay Settings
                </Button>
              </>
            )}

            {step === 3 && (
              <>
                <WizardSection title="Time-in windows">
                  <div className="grid gap-4 sm:grid-cols-2">
                    {(
                      [
                        [
                          "early_clock_in_minutes",
                          "Early time-in window (min)",
                          "How early employees may time in before shift start.",
                        ],
                        [
                          "on_time_grace_minutes",
                          "Extra minutes before late",
                          "Grace after shift start before status becomes Late.",
                        ],
                      ] as const
                    ).map(([key, label, hint]) => (
                      <WizardField key={key} label={label} hint={hint}>
                        <Input
                          className={wizardInputClass}
                          type="number"
                          min="0"
                          value={attForm[key]}
                          onChange={(e) =>
                            setAttForm({ ...attForm, [key]: e.target.value })
                          }
                        />
                      </WizardField>
                    ))}
                  </div>
                </WizardSection>

                <WizardSection title="Attendance status cutoffs">
                  <div className="grid gap-4 sm:grid-cols-2">
                    {(
                      [
                        [
                          "absent_threshold_percent",
                          "Absent if under (% of shift)",
                          "Status cutoff as percent of scheduled shift length.",
                        ],
                        [
                          "half_day_threshold_percent",
                          "Half-day if under (% of shift)",
                          "Status cutoff as percent of scheduled shift length.",
                        ],
                        [
                          "half_day_threshold_minutes",
                          "Payroll half-day cutoff (min)",
                          "Used for payslip half-day math (minutes).",
                        ],
                        [
                          "absent_threshold_minutes",
                          "Payroll absent cutoff (min)",
                          "Fallback minute cutoff when shift length is unavailable.",
                        ],
                      ] as const
                    ).map(([key, label, hint]) => (
                      <WizardField key={key} label={label} hint={hint}>
                        <Input
                          className={wizardInputClass}
                          type="number"
                          min="0"
                          value={attForm[key]}
                          onChange={(e) =>
                            setAttForm({ ...attForm, [key]: e.target.value })
                          }
                        />
                      </WizardField>
                    ))}
                  </div>
                </WizardSection>

                <WizardSection title="Overtime">
                  <div className="grid gap-4 sm:grid-cols-2">
                    {(
                      [
                        [
                          "overtime_minimum_minutes",
                          "Minimum overtime minutes",
                          "OT pay starts only after this many minutes past shift end.",
                        ],
                        [
                          "maximum_overtime_minutes",
                          "Maximum overtime duration (min)",
                          "How long an employee may stay timed in after shift end before attendance becomes Incomplete.",
                        ],
                      ] as const
                    ).map(([key, label, hint]) => (
                      <WizardField key={key} label={label} hint={hint}>
                        <Input
                          className={wizardInputClass}
                          type="number"
                          min="0"
                          value={attForm[key]}
                          onChange={(e) =>
                            setAttForm({ ...attForm, [key]: e.target.value })
                          }
                        />
                      </WizardField>
                    ))}
                  </div>
                </WizardSection>

                <WizardNotice>
                  Absent and half-day status use percent of each employee&apos;s
                  scheduled shift. Maximum overtime duration is an attendance
                  cutoff only — overtime pay still uses ₱
                  {payrollForm.overtime_per_minute} per minute (
                  {payrollForm.overtime_enabled ? "turned on" : "turned off"} in
                  pay settings).
                </WizardNotice>
                <Button
                  className={wizardPrimaryBtnClass}
                  onClick={() => saveAttendance.mutate()}
                  disabled={saveAttendance.isPending}
                >
                  Save Time-In Settings
                </Button>
              </>
            )}
            {step === 4 && <HolidaySetupSection />}

            {step === 5 && (
              <BusinessLocationSetup
                description=""
                mapHeightClassName="h-[240px] sm:h-[300px]"
                saveLabel="Save Workplace Location"
              />
            )}

            {step === 6 && (
              <>
                <WizardNotice>
                  Review your setup and finish when the required steps are done.
                  Required: work shifts, job roles, pay settings, and work
                  location.
                </WizardNotice>
                <ul className="grid gap-3 sm:grid-cols-2">
                  {setupStatus?.steps
                    .filter((s) => s.key !== "review")
                    .map((s) => (
                      <li
                        key={s.key}
                        className="flex items-center gap-3 rounded-xl border border-slate-200/90 bg-[#FAFBFC] px-3.5 py-3"
                      >
                        {s.complete ? (
                          <CheckCircle2 className="h-5 w-5 shrink-0 text-emerald-600" />
                        ) : (
                          <Circle className="h-5 w-5 shrink-0 text-[#9CA3AF]" />
                        )}
                        <span className="min-w-0 flex-1 text-sm font-medium text-[#1F2937]">
                          {s.label}
                        </span>
                        <span
                          className={cn(
                            "text-[11px] font-semibold uppercase tracking-wide",
                            s.complete ? "text-emerald-700" : "text-[#9CA3AF]"
                          )}
                        >
                          {s.complete ? "Done" : "Needed"}
                        </span>
                      </li>
                    ))}
                </ul>
                {!canCompleteSetup && setupStatus?.missing_items.length ? (
                  <WizardNotice tone="warning">
                    Still needed: {setupStatus.missing_items.join(", ")}
                  </WizardNotice>
                ) : null}
              </>
            )}
            </div>
          </OwnerCard>
        )}
        </div>

      {step >= 0 ? (
        <footer className="sticky bottom-0 z-10 border-t border-slate-200/80 bg-white/95 backdrop-blur-sm">
          <div className="mx-auto flex w-full min-w-0 max-w-6xl flex-col-reverse gap-2 px-5 py-3 sm:flex-row sm:items-center sm:justify-end sm:px-8">
            {step < STEPS.length - 1 ? (
              <>
                <Button
                  variant="ghost"
                  className="h-10 rounded-xl"
                  onClick={() => goToStep(step + 1)}
                >
                  Skip for Now
                </Button>
                {currentStepCanContinue && (
                  <Button
                    className={wizardPrimaryBtnClass}
                    onClick={() => {
                      void handleContinue();
                    }}
                    disabled={continuePending}
                  >
                    Continue
                    <ArrowRight className="ml-2 h-4 w-4" />
                  </Button>
                )}
              </>
            ) : (
              <>
                <Button
                  variant="outline"
                  className={wizardOutlineBtnClass}
                  onClick={() => navigate("/owner/dashboard")}
                  type="button"
                >
                  Go to Dashboard
                </Button>
                <Button
                  className={wizardPrimaryBtnClass}
                  onClick={() => finishSetup.mutate()}
                  disabled={finishSetup.isPending || !canCompleteSetup}
                >
                  Finish Setup
                </Button>
              </>
            )}
          </div>
        </footer>
      ) : null}

      <Dialog
        open={Boolean(editingShift)}
        onOpenChange={(open) => {
          if (!open) setEditingShift(null);
        }}
      >
        <DialogContent className="sm:max-w-md sm:rounded-2xl">
          <DialogHeader>
            <DialogTitle className="text-[#1F2937]">
              Edit {editingShift?.name} times
            </DialogTitle>
          </DialogHeader>
          <div className="grid gap-4 sm:grid-cols-2">
            <WizardField label="Start time">
              <Input
                className={wizardInputClass}
                type="time"
                value={editTimes.start_time}
                onChange={(e) =>
                  setEditTimes({ ...editTimes, start_time: e.target.value })
                }
              />
            </WizardField>
            <WizardField label="End time">
              <Input
                className={wizardInputClass}
                type="time"
                value={editTimes.end_time}
                onChange={(e) =>
                  setEditTimes({ ...editTimes, end_time: e.target.value })
                }
              />
            </WizardField>
          </div>
          <DialogFooter className="gap-2 sm:justify-end">
            <Button
              className={wizardOutlineBtnClass}
              variant="outline"
              onClick={() => setEditingShift(null)}
            >
              Cancel
            </Button>
            <Button
              className={wizardPrimaryBtnClass}
              disabled={
                !editTimes.start_time ||
                !editTimes.end_time ||
                saveShiftTimes.isPending
              }
              onClick={() => saveShiftTimes.mutate()}
            >
              {saveShiftTimes.isPending ? "Saving..." : "Save times"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </OwnerPage>
  );
}
