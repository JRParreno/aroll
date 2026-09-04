import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useMemo, useState } from "react";
import {
  ArrowLeft,
  ArrowRight,
  CheckCircle2,
  Circle,
  ClipboardCheck,
} from "lucide-react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { BusinessLocationSetup } from "@/components/owner/location/BusinessLocationSetup";
import { HolidaySetupSection } from "@/components/owner/setup/HolidaySetupSection";
import { OwnerPageBackLink } from "@/components/owner/layout/OwnerPageLayout";
import { formatShiftTime } from "@/components/owner/schedule/scheduleUtils";
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

  return (
    <div className="min-h-screen bg-[#F7F8FA] px-4 py-6 text-[#1F2937] sm:px-6 lg:px-8">
      <div className="mx-auto max-w-5xl space-y-6">
        {step < 0 ? (
          <OwnerPageBackLink
            to="/owner/settings/setup"
            label="Back to Business Setup"
          />
        ) : (
          <button
            className="inline-flex items-center gap-2 rounded-lg px-1 py-0.5 text-sm font-medium text-[#6B7280] transition-colors hover:bg-white hover:text-[#1E3A5F]"
            onClick={() => goToStep(-1)}
            type="button"
          >
            <ArrowLeft className="h-4 w-4" />
            Back to setup menu
          </button>
        )}

        <header className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm sm:p-6">
          <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
            <div className="min-w-0">
              <div className="mb-3 inline-flex items-center gap-2 rounded-full bg-[#EAF2FB] px-3 py-1.5 text-xs font-medium text-[#1E3A5F]">
                <ClipboardCheck className="h-4 w-4" />
                Business setup
              </div>
              <h1 className="text-2xl font-semibold tracking-tight text-[#1F2937]">
                Set Up Your Business
              </h1>
              <p className="mt-2 max-w-2xl text-sm leading-6 text-[#6B7280]">
                {step < 0
                  ? "Choose a section below to set up. You can return anytime from Business Setup."
                  : STEP_HELP[STEPS[step]]}
              </p>
            </div>
            {step >= 0 ? (
              <div className="rounded-2xl bg-[#F3F6FA] px-4 py-3 text-sm">
                <p className="font-medium text-[#1F2937]">
                  Step {step + 1} of {STEPS.length}
                </p>
                <p className="text-xs text-[#6B7280]">{STEPS[step]}</p>
              </div>
            ) : null}
          </div>
        </header>

        {step < 0 ? (
          <div className="grid gap-4 sm:grid-cols-2">
            {STEPS.map((label, index) => {
              const key = STEP_STATUS_KEYS[index];
              const complete = key ? isStepComplete(key) : false;
              return (
                <button
                  key={label}
                  type="button"
                  onClick={() => goToStep(index)}
                  className="rounded-2xl border border-slate-200 bg-white p-5 text-left shadow-sm transition hover:border-[#B9C7D8] hover:bg-[#FAFBFC]"
                >
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <p className="font-semibold text-[#1F2937]">{label}</p>
                      <p className="mt-2 text-sm text-[#6B7280]">
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
          <>
        <Card className="rounded-2xl border-slate-200 bg-white shadow-sm">
          <CardHeader className="border-b border-slate-100 px-5 py-5 sm:px-6">
            <CardTitle className="text-xl font-semibold text-[#1F2937]">
              {STEPS[step]}
            </CardTitle>
            <p className="mt-2 text-sm leading-6 text-[#6B7280]">
              {STEP_HELP[STEPS[step]]}
            </p>
          </CardHeader>
          <CardContent className="space-y-6 px-5 py-6 sm:px-6">
            {step === 0 && (
              <>
                <div className="grid gap-5 sm:grid-cols-2">
                  <div className="space-y-2">
                    <Label>Shift name</Label>
                    <Input
                      className="h-11 rounded-xl border-slate-200 bg-white"
                      value={shiftForm.name}
                      onChange={(e) =>
                        setShiftForm({ ...shiftForm, name: e.target.value })
                      }
                      placeholder="Morning Shift"
                    />
                  </div>
                  <div className="space-y-2">
                    <Label>Shift type</Label>
                    <select
                      className="flex h-11 w-full rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm"
                      value={shiftForm.shift_type}
                      onChange={(e) =>
                        setShiftForm({ ...shiftForm, shift_type: e.target.value })
                      }
                    >
                      <option value="morning">Morning</option>
                      <option value="afternoon">Afternoon</option>
                      <option value="evening">Evening</option>
                      <option value="night">Night</option>
                    </select>
                  </div>
                  <div className="space-y-2">
                    <Label>Start time</Label>
                    <Input
                      className="h-11 rounded-xl border-slate-200 bg-white"
                      type="time"
                      value={shiftForm.start_time}
                      onChange={(e) =>
                        setShiftForm({ ...shiftForm, start_time: e.target.value })
                      }
                    />
                  </div>
                  <div className="space-y-2">
                    <Label>End time</Label>
                    <Input
                      className="h-11 rounded-xl border-slate-200 bg-white"
                      type="time"
                      value={shiftForm.end_time}
                      onChange={(e) =>
                        setShiftForm({ ...shiftForm, end_time: e.target.value })
                      }
                    />
                  </div>
                  <div className="space-y-2">
                    <Label>Break minutes</Label>
                    <Input
                      className="h-11 rounded-xl border-slate-200 bg-white"
                      type="number"
                      value={shiftForm.break_minutes}
                      onChange={(e) =>
                        setShiftForm({
                          ...shiftForm,
                          break_minutes: e.target.value,
                        })
                      }
                    />
                  </div>
                  <div className="space-y-2">
                    <Label>Employees needed</Label>
                    <Input
                      className="h-11 rounded-xl border-slate-200 bg-white"
                      type="number"
                      value={shiftForm.employee_capacity}
                      onChange={(e) =>
                        setShiftForm({
                          ...shiftForm,
                          employee_capacity: e.target.value,
                        })
                      }
                    />
                  </div>
                </div>
                <Button
                  className="rounded-xl bg-[#1E3A5F] hover:bg-[#284B73]"
                  onClick={() => addShift.mutate()}
                  disabled={!shiftForm.name || addShift.isPending}
                >
                  Add work shift
                </Button>
                <ul className="overflow-hidden rounded-2xl border border-slate-200 text-sm">
                  {shifts.map((s) => (
                    <li
                      key={s.id}
                      className="flex items-center justify-between gap-3 border-b border-slate-100 px-4 py-3 last:border-b-0"
                    >
                      <span>
                        {s.name} ({formatShiftTime(s.start_time)}–
                        {formatShiftTime(s.end_time)})
                      </span>
                      <div className="flex shrink-0 items-center gap-2">
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() => openEditShiftTimes(s)}
                        >
                          Edit times
                        </Button>
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() =>
                            deleteShift(s.id).then(() => refetchShifts())
                          }
                        >
                          Remove
                        </Button>
                      </div>
                    </li>
                  ))}
                </ul>
              </>
            )}

            {step === 1 && (
              <>
                <div className="grid gap-5 sm:grid-cols-2">
                  <div className="space-y-2 sm:col-span-2">
                    <Label>Job role name</Label>
                    <Input
                      className="h-11 rounded-xl border-slate-200 bg-white"
                      value={posForm.title}
                      onChange={(e) =>
                        setPosForm({ ...posForm, title: e.target.value })
                      }
                    />
                  </div>
                  <div className="space-y-2">
                    <Label>Daily pay (₱)</Label>
                    <Input
                      className="h-11 rounded-xl border-slate-200 bg-white"
                      type="number"
                      value={posForm.daily_rate}
                      onChange={(e) =>
                        setPosForm({ ...posForm, daily_rate: e.target.value })
                      }
                    />
                  </div>
                  <div className="space-y-2">
                    <Label>Hourly pay (₱, optional)</Label>
                    <Input
                      className="h-11 rounded-xl border-slate-200 bg-white"
                      type="number"
                      value={posForm.hourly_rate}
                      onChange={(e) =>
                        setPosForm({ ...posForm, hourly_rate: e.target.value })
                      }
                    />
                  </div>
                  <div className="space-y-2 sm:col-span-2">
                    <Label>Description</Label>
                    <Input
                      className="h-11 rounded-xl border-slate-200 bg-white"
                      value={posForm.description}
                      onChange={(e) =>
                        setPosForm({ ...posForm, description: e.target.value })
                      }
                    />
                  </div>
                </div>
                <Button
                  className="rounded-xl bg-[#1E3A5F] hover:bg-[#284B73]"
                  onClick={() => addPosition.mutate()}
                  disabled={!positionDraftValid}
                >
                  Add job role
                </Button>
                <ul className="overflow-hidden rounded-2xl border border-slate-200 text-sm">
                  {positions.map((p) => (
                    <li
                      key={p.id}
                      className="flex items-center justify-between gap-3 border-b border-slate-100 px-4 py-3 last:border-b-0"
                    >
                      <span>
                        {p.title} — ₱{p.daily_rate}/day
                        {p.hourly_rate != null ? ` · ₱${p.hourly_rate}/hr` : ""}
                      </span>
                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() =>
                          deletePosition(p.id).then(() => refetchPositions())
                        }
                      >
                        Remove
                      </Button>
                    </li>
                  ))}
                </ul>
              </>
            )}

            {step === 2 && (
              <>
                <div className="grid gap-5 sm:grid-cols-2">
                  <div className="space-y-2">
                    <Label>How often employees get paid</Label>
                    <select
                      className="flex h-11 w-full rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm"
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
                    </select>
                  </div>
                  {payrollForm.pay_period_type === "weekly" && (
                    <div className="space-y-2">
                      <Label>Payday</Label>
                      <select
                        className="flex h-11 w-full rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm"
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
                      </select>
                    </div>
                  )}

                  {payrollForm.pay_period_type === "semi_monthly" && (
                    <div className="space-y-2">
                      <Label>Payday Schedule</Label>
                      <select
                        className="flex h-11 w-full rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm"
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
                      </select>
                    </div>
                  )}

                  {payrollForm.pay_period_type === "monthly" && (
                    <div className="space-y-2">
                      <Label>Payday (day of month)</Label>
                      <Input
                        className="h-11 rounded-xl border-slate-200 bg-white"
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
                      <p className="text-xs text-muted-foreground">
                        Use 31 for "last day of the month".
                      </p>
                    </div>
                  )}

                  {payrollForm.pay_period_type === "semi_monthly" &&
                    payrollForm.semi_monthly_preset === "custom" && (
                      <>
                        <div className="space-y-2">
                          <Label>First Payday (day of month)</Label>
                          <Input
                            className="h-11 rounded-xl border-slate-200 bg-white"
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
                        </div>
                        <div className="space-y-2">
                          <Label>Second Payday (day of month)</Label>
                          <Input
                            className="h-11 rounded-xl border-slate-200 bg-white"
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
                        </div>
                      </>
                    )}
                </div>

                <p className="rounded-xl bg-[#F3F6FA] px-4 py-3 text-sm text-[#6B7280]">
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
                </p>
                <label className="flex items-center gap-2 rounded-xl border border-slate-200 bg-[#FAFBFC] px-4 py-3 text-sm">
                  <input
                    type="checkbox"
                    checked={payrollForm.auto_reset_payroll_cycle}
                    onChange={(e) =>
                      setPayrollForm({
                        ...payrollForm,
                        auto_reset_payroll_cycle: e.target.checked,
                      })
                    }
                  />
                  Start a new pay period after payday
                </label>

                <div className="space-y-4 rounded-2xl border border-slate-200 bg-[#FAFBFC] p-4">
                  <div>
                    <p className="text-sm font-medium text-[#1F2937]">
                      Holiday pay rules
                    </p>
                    <p className="mt-1 text-xs text-[#6B7280]">
                      Choose how unworked and worked holidays are paid.
                    </p>
                  </div>
                  <div className="space-y-2">
                    <label className="flex cursor-pointer items-start gap-3 rounded-xl border border-slate-200 bg-white px-4 py-3 text-sm">
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
                    <label className="flex cursor-pointer items-start gap-3 rounded-xl border border-slate-200 bg-white px-4 py-3 text-sm">
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
                </div>

                <div className="space-y-4 rounded-2xl border border-slate-200 bg-[#FAFBFC] p-4">
                  <p className="text-sm font-medium text-[#1F2937]">
                    Pay rules
                  </p>
                  <label className="flex items-center gap-2 text-sm">
                    <input
                      type="checkbox"
                      checked={payrollForm.late_deduction_enabled}
                      onChange={(e) =>
                        setPayrollForm({
                          ...payrollForm,
                          late_deduction_enabled: e.target.checked,
                        })
                      }
                    />
                    Pay less when late
                  </label>
                  <div className="space-y-2">
                    <Label>Amount per late minute (₱)</Label>
                    <Input
                      className="h-11 rounded-xl border-slate-200 bg-white"
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
                  </div>
                  <label className="flex items-center gap-2 text-sm">
                    <input
                      type="checkbox"
                      checked={payrollForm.overtime_enabled}
                      onChange={(e) =>
                        setPayrollForm({
                          ...payrollForm,
                          overtime_enabled: e.target.checked,
                        })
                      }
                    />
                    Pay for overtime
                  </label>
                  <div className="space-y-2">
                    <Label>Extra pay per overtime minute (₱)</Label>
                    <Input
                      className="h-11 rounded-xl border-slate-200 bg-white"
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
                  </div>
                  <div className="space-y-2 sm:col-span-2">
                    <label className="flex items-start gap-2 text-sm">
                      <input
                        type="checkbox"
                        className="mt-1"
                        checked={payrollForm.enable_late_overtime_balancing}
                        onChange={(e) =>
                          setPayrollForm({
                            ...payrollForm,
                            enable_late_overtime_balancing: e.target.checked,
                          })
                        }
                        disabled={!payrollForm.overtime_enabled}
                      />
                      <span>
                        <span className="font-medium text-[#1F2937]">
                          Late–OT Balancing
                        </span>
                        <span className="mt-1 block text-xs text-[#6B7280]">
                          When enabled, overtime minutes are first used to
                          recover late arrival. Only the remaining overtime
                          minutes are paid.
                        </span>
                      </span>
                    </label>
                  </div>
                </div>

                <div className="space-y-4 rounded-2xl border border-slate-200 bg-[#FAFBFC] p-4">
                  <div>
                    <p className="text-sm font-medium text-[#1F2937]">
                      Extra pay on rest days
                    </p>
                    <p className="mt-1 text-xs text-muted-foreground">
                      Set the extra pay when an employee works on an approved
                      rest day.
                    </p>
                  </div>
                  <div className="space-y-2 sm:max-w-xs">
                    <Label>Extra pay (%)</Label>
                    <Input
                      className="h-11 rounded-xl border-slate-200 bg-white"
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
                    <p className="text-xs text-muted-foreground">
                      Example: 30% adds 0.30 × the employee&apos;s daily pay.
                    </p>
                  </div>
                </div>

                <Button
                  className="rounded-xl bg-[#1E3A5F] hover:bg-[#284B73]"
                  onClick={() => savePayroll.mutate()}
                  disabled={!payrollFormValid || savePayroll.isPending}
                >
                  Save Pay Settings
                </Button>
              </>
            )}

            {step === 3 && (
              <>
                <div className="grid gap-5 sm:grid-cols-2">
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
                    <div key={key} className="space-y-2">
                      <Label>{label}</Label>
                      <Input
                        className="h-11 rounded-xl border-slate-200 bg-white"
                        type="number"
                        min="0"
                        value={attForm[key]}
                        onChange={(e) =>
                          setAttForm({ ...attForm, [key]: e.target.value })
                        }
                      />
                      <p className="text-xs text-[#6B7280]">{hint}</p>
                    </div>
                  ))}
                </div>

                <p className="rounded-xl bg-[#F3F6FA] px-4 py-3 text-sm text-[#6B7280]">
                  Absent and half-day status use percent of each employee&apos;s
                  scheduled shift. Maximum overtime duration is an attendance
                  cutoff only — overtime pay still uses ₱
                  {payrollForm.overtime_per_minute} per minute (
                  {payrollForm.overtime_enabled ? "turned on" : "turned off"} in
                  pay settings).
                </p>
                <Button
                  className="rounded-xl bg-[#1E3A5F] hover:bg-[#284B73]"
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
                description="Set your workplace on the map and choose how close employees must be before they can time in or time out."
                mapHeightClassName="h-[280px] sm:h-[340px]"
                saveLabel="Save Workplace Location"
              />
            )}

            {step === 6 && (
              <>
                <p className="rounded-xl bg-[#F3F6FA] px-4 py-3 text-sm text-[#6B7280]">
                  Review your setup and finish when the required steps are done.
                  Required: work shifts, job roles, pay settings, and work
                  location.
                </p>
                <ul className="grid gap-2 text-sm sm:grid-cols-2">
                  {setupStatus?.steps
                    .filter((s) => s.key !== "review")
                    .map((s) => (
                      <li key={s.key}>
                        {s.complete ? "✓" : "✗"} {s.label}
                      </li>
                    ))}
                </ul>
                {!canCompleteSetup && setupStatus?.missing_items.length ? (
                  <p className="rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800">
                    Still needed: {setupStatus.missing_items.join(", ")}
                  </p>
                ) : null}
                <Button
                  className="rounded-xl bg-[#1E3A5F] hover:bg-[#284B73]"
                  onClick={() => finishSetup.mutate()}
                  disabled={finishSetup.isPending || !canCompleteSetup}
                >
                  Finish Setup
                </Button>
                <Button
                  variant="outline"
                  className="rounded-xl border-slate-200"
                  onClick={() => navigate("/owner/dashboard")}
                  type="button"
                >
                  Go to Dashboard
                </Button>
              </>
            )}
          </CardContent>
        </Card>

        {step < STEPS.length - 1 ? (
        <div className="flex flex-col-reverse gap-3 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:flex-row sm:items-center sm:justify-end">
          <div className="flex flex-col gap-2 sm:flex-row">
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
                  className="h-10 rounded-xl bg-[#1E3A5F] hover:bg-[#284B73]"
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
          </div>
        </div>
        ) : null}
          </>
        )}
      </div>

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
            <div className="space-y-2">
              <Label>Start time</Label>
              <Input
                className="h-11 rounded-xl border-slate-200 bg-white"
                type="time"
                value={editTimes.start_time}
                onChange={(e) =>
                  setEditTimes({ ...editTimes, start_time: e.target.value })
                }
              />
            </div>
            <div className="space-y-2">
              <Label>End time</Label>
              <Input
                className="h-11 rounded-xl border-slate-200 bg-white"
                type="time"
                value={editTimes.end_time}
                onChange={(e) =>
                  setEditTimes({ ...editTimes, end_time: e.target.value })
                }
              />
            </div>
          </div>
          <DialogFooter className="gap-2 sm:justify-end">
            <Button
              className="rounded-xl"
              variant="outline"
              onClick={() => setEditingShift(null)}
            >
              Cancel
            </Button>
            <Button
              className="rounded-xl bg-[#1E3A5F] hover:bg-[#284B73]"
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
    </div>
  );
}
