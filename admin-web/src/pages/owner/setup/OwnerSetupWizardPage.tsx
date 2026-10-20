import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useMemo, useState } from "react";
import {
  ArrowLeft,
  ArrowRight,
  BadgeDollarSign,
  BriefcaseBusiness,
  CalendarDays,
  CalendarOff,
  CheckCircle2,
  Circle,
  ClipboardCheck,
  Clock3,
  Home,
  MapPin,
  ShieldCheck,
} from "lucide-react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
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
import { LeavePolicySetupSection } from "@/components/owner/setup/LeavePolicySetupSection";
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
  updatePosition,
  updateRestDayPolicy,
  updateShift,
  type Position,
  type Shift,
} from "@/lib/api";
import { ME_QUERY_KEY } from "@/lib/authSession";
import {
  SETUP_WIZARD_LOCATION_STEP,
  SETUP_WIZARD_STATUS_KEYS,
  SETUP_WIZARD_STEPS,
} from "@/lib/ownerFirstLoginPath";

const STEPS = [...SETUP_WIZARD_STEPS];

const STEP_STATUS_KEYS = SETUP_WIZARD_STATUS_KEYS;

function toTimeInputValue(value: string) {
  const [hour = "00", minute = "00"] = value.split(":");
  return `${String(Number(hour) || 0).padStart(2, "0")}:${String(Number(minute) || 0).padStart(2, "0")}`;
}

function positionRateLabel(p: Position) {
  const configs = p.pay_configs ?? [];
  if (configs.length > 0) {
    return configs
      .map((c) =>
        c.pay_basis === "hourly"
          ? `Hourly · ₱${c.rate}/hr`
          : `Daily · ₱${c.rate}/day`
      )
      .join(" · ");
  }
  const basis = p.pay_basis ?? "daily";
  if (basis === "hourly" && p.hourly_rate != null) {
    return `Hourly · ₱${p.hourly_rate}/hr`;
  }
  if (p.daily_rate != null) {
    return `Daily · ₱${p.daily_rate}/day`;
  }
  if (p.hourly_rate != null) {
    return `Hourly · ₱${p.hourly_rate}/hr`;
  }
  return "Rate not set";
}

function employmentTypeLabel(value: string | null | undefined) {
  if (value === "part_time") return "Part-time";
  if (value === "full_time") return "Full-time";
  return "Unclassified";
}

const STEP_HELP: Record<string, string> = {
  "Work Shifts": "Add the times your team usually works.",
  "Employee Job Roles":
    "Choose an employment type, then add a role with one or both pay configurations (Daily and/or Hourly). Configure once here, then reuse when adding employees.",
  "Set Up Employee Pay":
    "Choose how often employees get paid and how pay is calculated.",
  "How Employees Time In & Out":
    "Set the time rules for being on time, late, absent, and overtime.",
  "Holiday Management":
    "Add holidays your business follows so schedules and pay stay accurate.",
  "Holidays Employees Will Be Paid For":
    "Add holidays your business follows so schedules and pay stay accurate.",
  "Leave Policy":
    "Set paid or unpaid leave types and how far ahead leave must be requested.",
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
  CalendarOff,
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
  const [editTimes, setEditTimes] = useState({
    start_time: "",
    end_time: "",
    employee_capacity: "1",
  });
  const [posForm, setPosForm] = useState({
    employment_type: "full_time" as "full_time" | "part_time",
    title: "",
    enable_daily: true,
    daily_rate: "",
    enable_hourly: false,
    hourly_rate: "",
    description: "",
  });
  const [editingPayPosition, setEditingPayPosition] = useState<Position | null>(
    null
  );
  const [editPayForm, setEditPayForm] = useState({
    enable_daily: true,
    daily_rate: "",
    enable_hourly: false,
    hourly_rate: "",
  });
  const [payrollForm, setPayrollForm] = useState({
    pay_period_type: "monthly",
    auto_reset_payroll_cycle: true,
    late_deduction_enabled: true,
    late_deduction_per_minute: "1",
    overtime_enabled: true,
    overtime_per_minute: "1",
    overtime_calculation_method: "flat_per_minute" as
      | "flat_per_minute"
      | "hourly_statutory",
    enable_late_overtime_balancing: false,
    overtime_approval_required: false,
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
    breaktime_is_paid: false,
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
      overtime_calculation_method:
        payroll.overtime_calculation_method === "hourly_statutory"
          ? "hourly_statutory"
          : "flat_per_minute",
      enable_late_overtime_balancing:
        payroll.enable_late_overtime_balancing === true,
      overtime_approval_required:
        payroll.overtime_approval_required === true,
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
      breaktime_is_paid: attendancePolicy.breaktime_is_paid === true,
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
    ((posForm.enable_daily && Number(posForm.daily_rate) > 0) ||
      (posForm.enable_hourly && Number(posForm.hourly_rate) > 0)) &&
    (!posForm.enable_daily || Number(posForm.daily_rate) > 0) &&
    (!posForm.enable_hourly || Number(posForm.hourly_rate) > 0);

  const editPayDraftValid =
    ((editPayForm.enable_daily && Number(editPayForm.daily_rate) > 0) ||
      (editPayForm.enable_hourly && Number(editPayForm.hourly_rate) > 0)) &&
    (!editPayForm.enable_daily || Number(editPayForm.daily_rate) > 0) &&
    (!editPayForm.enable_hourly || Number(editPayForm.hourly_rate) > 0);

  function buildPayConfigs(form: {
    enable_daily: boolean;
    daily_rate: string;
    enable_hourly: boolean;
    hourly_rate: string;
  }) {
    const configs: { pay_basis: "daily" | "hourly"; rate: number }[] = [];
    if (form.enable_daily) {
      configs.push({ pay_basis: "daily", rate: Number(form.daily_rate) });
    }
    if (form.enable_hourly) {
      configs.push({ pay_basis: "hourly", rate: Number(form.hourly_rate) });
    }
    return configs;
  }

  function openEditPayConfigs(position: Position) {
    const configs = position.pay_configs ?? [];
    const daily = configs.find((c) => c.pay_basis === "daily");
    const hourly = configs.find((c) => c.pay_basis === "hourly");
    setEditingPayPosition(position);
    setEditPayForm({
      enable_daily: Boolean(daily) || (daily == null && hourly == null && position.daily_rate != null),
      daily_rate: String(
        daily?.rate ?? position.daily_rate ?? ""
      ),
      enable_hourly: Boolean(hourly) || (hourly == null && daily == null && position.pay_basis === "hourly"),
      hourly_rate: String(
        hourly?.rate ?? position.hourly_rate ?? ""
      ),
    });
  }

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
        return true;
      case 6:
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
      const capacity = Number(editTimes.employee_capacity);
      if (!Number.isInteger(capacity) || capacity < 1) {
        throw new Error("Invalid employee capacity");
      }
      if (editingShift.has_in_progress_today) {
        return updateShift(editingShift.id, {
          employee_capacity: capacity,
        });
      }
      return updateShift(editingShift.id, {
        start_time: editTimes.start_time,
        end_time: editTimes.end_time,
        employee_capacity: capacity,
      });
    },
    onSuccess: () => {
      toast.success("Shift updated");
      setEditingShift(null);
      refetchShifts();
      qc.invalidateQueries({ queryKey: ["shifts"] });
      qc.invalidateQueries({ queryKey: ["weekly-schedule"] });
    },
    onError: (error) => {
      const detail =
        typeof error === "object" &&
        error !== null &&
        "response" in error &&
        typeof error.response === "object" &&
        error.response !== null &&
        "data" in error.response &&
        typeof error.response.data === "object" &&
        error.response.data !== null &&
        "detail" in error.response.data
          ? error.response.data.detail
          : null;
      if (
        typeof detail === "object" &&
        detail !== null &&
        "code" in detail &&
        detail.code === "shift_in_progress"
      ) {
        const title =
          "title" in detail && typeof detail.title === "string"
            ? detail.title
            : "Shift In Progress";
        const message =
          "message" in detail && typeof detail.message === "string"
            ? detail.message
            : "This shift has already started and cannot be changed.";
        toast.error(`${title}: ${message}`);
        return;
      }
      toast.error(
        error instanceof Error && error.message === "Invalid employee capacity"
          ? "Employee capacity must be a whole number of at least 1"
          : "Could not update shift"
      );
    },
  });

  function openEditShiftTimes(shift: Shift) {
    setEditingShift(shift);
    setEditTimes({
      start_time: toTimeInputValue(shift.start_time),
      end_time: toTimeInputValue(shift.end_time),
      employee_capacity: String(shift.employee_capacity ?? 1),
    });
  }

  const addPosition = useMutation({
    mutationFn: () =>
      createPosition({
        title: posForm.title,
        employment_type: posForm.employment_type,
        pay_configs: buildPayConfigs(posForm),
        description: posForm.description || undefined,
      }),
    onSuccess: () => {
      toast.success("Job role added");
      setPosForm((current) => ({
        ...current,
        title: "",
        enable_daily: true,
        daily_rate: "",
        enable_hourly: false,
        hourly_rate: "",
        description: "",
      }));
      refetchPositions();
      qc.invalidateQueries({ queryKey: ["setup-status"] });
    },
  });

  const savePayConfigs = useMutation({
    mutationFn: () => {
      if (!editingPayPosition) throw new Error("No role selected");
      return updatePosition(editingPayPosition.id, {
        pay_configs: buildPayConfigs(editPayForm),
      });
    },
    onSuccess: () => {
      toast.success("Pay configurations updated");
      setEditingPayPosition(null);
      refetchPositions();
      qc.invalidateQueries({ queryKey: ["setup-status"] });
      qc.invalidateQueries({ queryKey: ["positions"] });
    },
    onError: () => toast.error("Could not update pay configurations"),
  });

  const classifyPosition = useMutation({
    mutationFn: ({
      id,
      employment_type,
    }: {
      id: string;
      employment_type: "full_time" | "part_time";
    }) => updatePosition(id, { employment_type }),
    onSuccess: () => {
      toast.success("Job role classified");
      refetchPositions();
      qc.invalidateQueries({ queryKey: ["positions"] });
    },
    onError: () => toast.error("Could not update job role"),
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
          overtime_calculation_method:
            payrollForm.overtime_calculation_method,
          enable_late_overtime_balancing:
            payrollForm.enable_late_overtime_balancing,
          overtime_approval_required:
            payrollForm.overtime_approval_required,
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

  const saveBreaktime = useMutation({
    mutationFn: (breaktime_is_paid: boolean) =>
      updateAttendancePolicy({
        ...(attendancePolicy ?? {}),
        breaktime_is_paid,
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["attendance-policy"] });
    },
    onError: () => toast.error("Could not save breaktime setting"),
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
        // early_out_deduction_* is stored for compatibility only; undertime
        // pay uses the employee's wage minute rate. Do not present or rewrite
        // those fields from Owner Setup.
        overtime_minimum_minutes: Number(attForm.overtime_minimum_minutes),
        maximum_overtime_minutes: Number(attForm.maximum_overtime_minutes),
        missing_clock_out_policy: attForm.missing_clock_out_policy,
        attendance_based_salary_enabled: attForm.attendance_based_salary_enabled,
        breaktime_is_paid: attForm.breaktime_is_paid,
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
      if (step === SETUP_WIZARD_LOCATION_STEP && !isStepComplete("location")) {
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
    <OwnerPage className="flex h-full max-h-full min-h-0 flex-col overflow-hidden">
      {/* Setup Guide–only navbar: scoped styles, not shared OwnerPageHeader */}
      <header className="setup-wizard-navbar shrink-0 z-10 border-b border-slate-200/80 bg-white/95 backdrop-blur-sm">
        <div className="mx-auto w-full min-w-0 max-w-6xl px-5 sm:px-8">
          {/* Row 1 — fixed chrome: title + Home + Notifications */}
          <div className="flex h-14 items-center justify-between gap-4">
            <h1 className="min-w-0 flex-1 truncate text-lg font-bold tracking-tight text-[#111827] sm:text-xl">
              Set Up Your Business
            </h1>
            <div className="flex shrink-0 items-center gap-2.5">
              <Link
                to="/owner/dashboard"
                className="inline-flex h-10 items-center gap-2 rounded-xl border border-slate-200/90 bg-white px-3 text-sm font-medium text-[#374151] shadow-sm transition hover:border-[color-mix(in_srgb,var(--owner-navy)_20%,transparent)] hover:bg-[#F8FAFC] hover:text-[var(--owner-navy)]"
                aria-label="Home"
              >
                <Home className="h-[18px] w-[18px]" strokeWidth={2} />
                <span className="hidden sm:inline">Home</span>
              </Link>
              <OwnerNotificationBell />
            </div>
          </div>

          {/* Row 2 — fixed back slot + progress (stable widths) */}
          <div className="flex h-12 items-center justify-between gap-4 border-t border-slate-100">
            <div className="flex h-9 w-[13.75rem] shrink-0 items-center">
              {step < 0 ? (
                <OwnerPageBackLink
                  to="/owner/settings/setup"
                  label="Back to Business Setup"
                  className="max-w-full truncate hover:bg-[#F8FAFC]"
                />
              ) : (
                <button
                  className="inline-flex items-center gap-2 rounded-lg px-1 py-0.5 text-sm font-medium text-[#6B7280] transition-colors hover:bg-[#F8FAFC] hover:text-[var(--owner-navy)]"
                  onClick={() => goToStep(step === 0 ? -1 : step - 1)}
                  type="button"
                >
                  <ArrowLeft className="h-4 w-4 shrink-0" />
                  Back
                </button>
              )}
            </div>
            <div className="w-full max-w-[14.5rem] shrink-0 sm:w-[14.5rem]">
              <div className="flex items-center justify-between gap-3 text-xs">
                <p className="min-w-0 truncate font-medium text-[#1F2937]">
                  {step < 0
                    ? `${completedCount} of ${countableSteps.length} complete`
                    : `Step ${step + 1} of ${STEPS.length}`}
                </p>
                <p className="shrink-0 tabular-nums text-[#6B7280]">
                  {wizardProgress}%
                </p>
              </div>
              <div className="mt-1.5 h-1.5 overflow-hidden rounded-full bg-[#E5E7EB]">
                <div
                  className="h-full rounded-full bg-[var(--owner-button)] transition-[width] duration-300"
                  style={{
                    width: `${Math.min(Math.max(wizardProgress, 0), 100)}%`,
                  }}
                />
              </div>
              <p className="mt-1 h-4 truncate text-[11px] font-medium text-[var(--owner-navy)]">
                {step >= 0
                  ? STEPS[step]
                  : `${setupStatus?.completion_percent ?? 0}% of required setup`}
              </p>
            </div>
          </div>

          {/* Row 3 — context copy with reserved height so step text length does not resize the bar */}
          <div className="pb-3 pt-1">
            <p className="owner-section-subtitle min-h-[2.5rem] max-w-3xl line-clamp-2">
              {step < 0
                ? "Choose a section below to set up. You can return anytime from Business Setup."
                : STEP_HELP[STEPS[step]]}
            </p>
          </div>

          {/* Row 4 — step track; reserve height on sm+ so hub↔step does not jump as much */}
          <div className="min-h-0 pb-3 sm:min-h-[2.75rem]">
            {step >= 0 ? (
              <WizardStepTrack
                current={step}
                labels={STEPS}
                complete={stepCompleteFlags}
                onSelect={goToStep}
                className="mt-0"
              />
            ) : null}
          </div>
        </div>
      </header>

      <div className="mx-auto w-full min-w-0 max-w-6xl flex-1 min-h-0 overflow-x-hidden overflow-y-auto px-5 py-6 sm:px-8">
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
                  className="owner-card p-5 text-left transition hover:border-[color-mix(in_srgb,var(--owner-accent)_32%,white)] hover:bg-[#FAFBFC]"
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
                <WizardSettingRow
                  title="Breaktime is paid"
                  description="ON: Include breaktime in paid working hours. OFF: Breaktime is unpaid."
                  checked={attForm.breaktime_is_paid}
                  onChange={(next) => {
                    setAttForm({ ...attForm, breaktime_is_paid: next });
                    saveBreaktime.mutate(next);
                  }}
                  disabled={!attendancePolicy || saveBreaktime.isPending}
                />
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
                          {formatShiftTime(s.start_time)}–{formatShiftTime(s.end_time)}{" "}
                          · Capacity {s.employee_capacity}
                        </p>
                      </div>
                      <div className="flex shrink-0 items-center gap-2">
                        <Button
                          size="sm"
                          variant="outline"
                          className="h-8 rounded-lg px-2.5 text-xs"
                          onClick={() => openEditShiftTimes(s)}
                        >
                          Edit shift
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
                  <WizardField label="1. Employment type">
                    <WizardSelect
                      value={posForm.employment_type}
                      onChange={(e) =>
                        setPosForm({
                          ...posForm,
                          employment_type: e.target.value as
                            | "full_time"
                            | "part_time",
                        })
                      }
                    >
                      <option value="full_time">Full-time</option>
                      <option value="part_time">Part-time</option>
                    </WizardSelect>
                  </WizardField>
                  <WizardField label="2. Role / position name">
                    <Input
                      className={wizardInputClass}
                      value={posForm.title}
                      onChange={(e) =>
                        setPosForm({ ...posForm, title: e.target.value })
                      }
                      placeholder="e.g. Cashier"
                    />
                  </WizardField>
                  <div className="space-y-3 sm:col-span-2">
                    <p className="text-xs font-semibold uppercase tracking-wide text-[#9CA3AF]">
                      3. Pay configurations
                    </p>
                    <p className="text-sm text-[#6B7280]">
                      Add Daily, Hourly, or both. Each role keeps rates separate
                      by employment type.
                    </p>
                    <div className="grid gap-3 sm:grid-cols-2">
                      <div className="rounded-xl border border-slate-200 bg-white px-3 py-3">
                        <label className="flex items-center gap-2 text-sm font-medium text-[#1F2937]">
                          <input
                            type="checkbox"
                            className="accent-[var(--owner-accent)]"
                            checked={posForm.enable_daily}
                            onChange={(e) =>
                              setPosForm({
                                ...posForm,
                                enable_daily: e.target.checked,
                              })
                            }
                          />
                          Daily
                        </label>
                        {posForm.enable_daily ? (
                          <Input
                            className={`${wizardInputClass} mt-2`}
                            type="number"
                            min="0"
                            step="0.01"
                            placeholder="Daily amount (₱)"
                            value={posForm.daily_rate}
                            onChange={(e) =>
                              setPosForm({
                                ...posForm,
                                daily_rate: e.target.value,
                              })
                            }
                          />
                        ) : null}
                      </div>
                      <div className="rounded-xl border border-slate-200 bg-white px-3 py-3">
                        <label className="flex items-center gap-2 text-sm font-medium text-[#1F2937]">
                          <input
                            type="checkbox"
                            className="accent-[var(--owner-accent)]"
                            checked={posForm.enable_hourly}
                            onChange={(e) =>
                              setPosForm({
                                ...posForm,
                                enable_hourly: e.target.checked,
                              })
                            }
                          />
                          Hourly
                        </label>
                        {posForm.enable_hourly ? (
                          <Input
                            className={`${wizardInputClass} mt-2`}
                            type="number"
                            min="0"
                            step="0.01"
                            placeholder="Hourly amount (₱)"
                            value={posForm.hourly_rate}
                            onChange={(e) =>
                              setPosForm({
                                ...posForm,
                                hourly_rate: e.target.value,
                              })
                            }
                          />
                        ) : null}
                      </div>
                    </div>
                  </div>
                  <WizardField label="Description (optional)" className="sm:col-span-2">
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

                {positions.some((p) => !p.employment_type) ? (
                  <div className="rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-950">
                    <p className="font-semibold">Unclassified existing roles</p>
                    <p className="mt-1 text-amber-900/80">
                      These roles still work for current employees, but they
                      will not appear in Add Employee until you assign Full-time
                      or Part-time.
                    </p>
                    <ul className="mt-3 space-y-2">
                      {positions
                        .filter((p) => !p.employment_type)
                        .map((p) => (
                          <li
                            key={p.id}
                            className="flex flex-wrap items-center justify-between gap-2 rounded-lg bg-white/80 px-3 py-2"
                          >
                            <div className="min-w-0">
                              <p className="truncate font-medium">{p.title}</p>
                              <p className="text-xs text-amber-900/70">
                                {positionRateLabel(p)}
                              </p>
                            </div>
                            <div className="flex gap-2">
                              <Button
                                size="sm"
                                variant="outline"
                                className="h-8 rounded-lg px-2.5 text-xs"
                                disabled={classifyPosition.isPending}
                                onClick={() =>
                                  classifyPosition.mutate({
                                    id: p.id,
                                    employment_type: "full_time",
                                  })
                                }
                              >
                                Full-time
                              </Button>
                              <Button
                                size="sm"
                                variant="outline"
                                className="h-8 rounded-lg px-2.5 text-xs"
                                disabled={classifyPosition.isPending}
                                onClick={() =>
                                  classifyPosition.mutate({
                                    id: p.id,
                                    employment_type: "part_time",
                                  })
                                }
                              >
                                Part-time
                              </Button>
                            </div>
                          </li>
                        ))}
                    </ul>
                  </div>
                ) : null}

                <WizardRecordList empty="No job roles yet. Add one above.">
                  {(["full_time", "part_time"] as const).map((etype) => {
                    const group = positions.filter(
                      (p) => p.employment_type === etype
                    );
                    if (group.length === 0) return null;
                    return (
                      <li key={etype} className="list-none space-y-0 border-b border-slate-100 last:border-0">
                        <p className="bg-slate-50 px-4 py-2 text-xs font-semibold uppercase tracking-wide text-[#6B7280]">
                          {employmentTypeLabel(etype)}
                        </p>
                        <ul>
                          {group.map((p) => (
                            <li
                              key={p.id}
                              className="flex items-center justify-between gap-3 px-4 py-3"
                            >
                              <div className="min-w-0">
                                <p className="truncate font-medium text-[#1F2937]">
                                  {p.title}
                                </p>
                                <p className="mt-0.5 text-xs text-[#6B7280]">
                                  {positionRateLabel(p)}
                                </p>
                              </div>
                              <div className="flex shrink-0 items-center gap-2">
                                <Button
                                  size="sm"
                                  variant="outline"
                                  className="h-8 rounded-lg px-2.5 text-xs"
                                  onClick={() => openEditPayConfigs(p)}
                                >
                                  Edit rates
                                </Button>
                                <Button
                                  size="sm"
                                  variant="outline"
                                  className="h-8 rounded-lg px-2.5 text-xs"
                                  onClick={() =>
                                    deletePosition(p.id).then(() =>
                                      refetchPositions()
                                    )
                                  }
                                >
                                  Remove
                                </Button>
                              </div>
                            </li>
                          ))}
                        </ul>
                      </li>
                    );
                  })}
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
                  title="Holiday Rules"
                  description="Choose how Aroll+ interprets holiday types for worked and unworked days."
                >
                  <div className="space-y-2">
                    <label
                      className={cn(
                        "flex cursor-pointer items-start gap-3 rounded-xl border bg-white px-4 py-3 text-sm",
                        payrollForm.holiday_rules_mode === "philippine_labor"
                          ? "border-[color-mix(in_srgb,var(--owner-accent)_45%,white)] bg-[var(--owner-well)]"
                          : "border-slate-200"
                      )}
                    >
                      <input
                        type="radio"
                        className="mt-1 accent-[var(--owner-accent)]"
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
                          Regular holidays pay the scheduled day even if
                          unworked. Special non-working days follow
                          no-work-no-pay unless worked. Company holidays follow
                          Pay Scheduled Day When Not Working.
                        </span>
                      </span>
                    </label>
                    <label
                      className={cn(
                        "flex cursor-pointer items-start gap-3 rounded-xl border bg-white px-4 py-3 text-sm",
                        payrollForm.holiday_rules_mode === "custom_company"
                          ? "border-[color-mix(in_srgb,var(--owner-accent)_45%,white)] bg-[var(--owner-well)]"
                          : "border-slate-200"
                      )}
                    >
                      <input
                        type="radio"
                        className="mt-1 accent-[var(--owner-accent)]"
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
                          Use each holiday&apos;s Pay Scheduled Day When Not
                          Working setting and Worked Holiday Premium only.
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
                  <WizardField
                    label="How overtime is calculated"
                    hint={
                      payrollForm.overtime_calculation_method ===
                      "hourly_statutory"
                        ? "Uses each employee's basic hourly rate, or the daily rate divided by that shift's scheduled hours, then the day-specific overtime factor. This is not proof that every employee is covered by the Labor Code."
                        : "Uses the peso amount per overtime minute saved below. A flat amount can be below the overtime pay a covered employee is entitled to. Saving it does not make the rate legally compliant."
                    }
                  >
                    <WizardSelect
                      value={payrollForm.overtime_calculation_method}
                      disabled={!payrollForm.overtime_enabled}
                      onChange={(e) =>
                        setPayrollForm({
                          ...payrollForm,
                          overtime_calculation_method:
                            e.target.value === "hourly_statutory"
                              ? "hourly_statutory"
                              : "flat_per_minute",
                        })
                      }
                    >
                      <option value="flat_per_minute">
                        Flat rate per overtime minute
                      </option>
                      <option value="hourly_statutory">
                        Hourly-based overtime calculation
                      </option>
                    </WizardSelect>
                  </WizardField>
                  {payrollForm.overtime_calculation_method ===
                    "flat_per_minute" && (
                    <WizardField label="Extra Pay per Overtime Minute (₱)">
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
                  )}
                  <WizardSettingRow
                    title="Late–OT Balancing"
                    description="Employees who arrive late may offset the late time by working beyond their scheduled end time."
                    checked={payrollForm.enable_late_overtime_balancing}
                    onChange={(next) =>
                      setPayrollForm({
                        ...payrollForm,
                        enable_late_overtime_balancing: next,
                      })
                    }
                    disabled={!payrollForm.overtime_enabled}
                  />
                  <WizardSettingRow
                    title="OT Approval Required"
                    description="When enabled, overtime must be approved before it is included as payable additional pay."
                    checked={payrollForm.overtime_approval_required}
                    onChange={(next) =>
                      setPayrollForm({
                        ...payrollForm,
                        overtime_approval_required: next,
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
                          "Minimum Worked Shift (%)",
                          "Employees must work at least the configured percentage of their scheduled shift to avoid being marked Absent.",
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
                  Minimum Worked Shift (%) and half-day cutoffs use percent of
                  each employee&apos;s scheduled shift. Maximum overtime
                  duration is an attendance cutoff only — overtime pay still
                  follows the method in pay settings (
                  {payrollForm.overtime_enabled ? "turned on" : "turned off"}
                  {payrollForm.overtime_calculation_method === "hourly_statutory"
                    ? ", hourly-based"
                    : `, ₱${payrollForm.overtime_per_minute} per minute`}
                  ).
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

            {step === 5 && <LeavePolicySetupSection />}

            {step === 6 && (
              <BusinessLocationSetup
                description=""
                mapHeightClassName="h-[240px] sm:h-[300px]"
                saveLabel="Save Workplace Location"
              />
            )}

            {step === 7 && (
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
        <footer className="shrink-0 z-10 border-t border-slate-200/80 bg-white/95 backdrop-blur-sm">
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
              {editingShift?.has_in_progress_today
                ? "Shift In Progress"
                : `Edit ${editingShift?.name}`}
            </DialogTitle>
          </DialogHeader>
          {editingShift?.has_in_progress_today ? (
            <p className="text-sm leading-relaxed text-[#6B7280]">
              This shift has already started and cannot be changed. Changes to
              an active shift could affect attendance and payroll records.
            </p>
          ) : null}
          <div className="grid gap-4 sm:grid-cols-2">
            <WizardField label="Start time">
              <Input
                className={wizardInputClass}
                type="time"
                value={editTimes.start_time}
                disabled={Boolean(editingShift?.has_in_progress_today)}
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
                disabled={Boolean(editingShift?.has_in_progress_today)}
                onChange={(e) =>
                  setEditTimes({ ...editTimes, end_time: e.target.value })
                }
              />
            </WizardField>
            <WizardField label="Employee Capacity">
              <Input
                className={wizardInputClass}
                type="number"
                min={1}
                step={1}
                value={editTimes.employee_capacity}
                onChange={(e) =>
                  setEditTimes({
                    ...editTimes,
                    employee_capacity: e.target.value,
                  })
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
                !editTimes.employee_capacity ||
                Number(editTimes.employee_capacity) < 1 ||
                !Number.isInteger(Number(editTimes.employee_capacity)) ||
                saveShiftTimes.isPending
              }
              onClick={() => saveShiftTimes.mutate()}
            >
              {saveShiftTimes.isPending ? "Saving..." : "Save"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog
        open={Boolean(editingPayPosition)}
        onOpenChange={(open) => {
          if (!open) setEditingPayPosition(null);
        }}
      >
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle className="text-[#1F2937]">
              Edit rates · {editingPayPosition?.title}
            </DialogTitle>
          </DialogHeader>
          <p className="text-sm text-[#6B7280]">
            Enable Daily and/or Hourly. Removing a configuration only removes
            that rate option — the role stays.
          </p>
          <div className="grid gap-3 sm:grid-cols-2">
            <div className="rounded-xl border border-slate-200 bg-white px-3 py-3">
              <label className="flex items-center gap-2 text-sm font-medium text-[#1F2937]">
                <input
                  type="checkbox"
                  className="accent-[var(--owner-accent)]"
                  checked={editPayForm.enable_daily}
                  onChange={(e) =>
                    setEditPayForm({
                      ...editPayForm,
                      enable_daily: e.target.checked,
                    })
                  }
                />
                Daily
              </label>
              {editPayForm.enable_daily ? (
                <Input
                  className={`${wizardInputClass} mt-2`}
                  type="number"
                  min="0"
                  step="0.01"
                  value={editPayForm.daily_rate}
                  onChange={(e) =>
                    setEditPayForm({
                      ...editPayForm,
                      daily_rate: e.target.value,
                    })
                  }
                />
              ) : null}
            </div>
            <div className="rounded-xl border border-slate-200 bg-white px-3 py-3">
              <label className="flex items-center gap-2 text-sm font-medium text-[#1F2937]">
                <input
                  type="checkbox"
                  className="accent-[var(--owner-accent)]"
                  checked={editPayForm.enable_hourly}
                  onChange={(e) =>
                    setEditPayForm({
                      ...editPayForm,
                      enable_hourly: e.target.checked,
                    })
                  }
                />
                Hourly
              </label>
              {editPayForm.enable_hourly ? (
                <Input
                  className={`${wizardInputClass} mt-2`}
                  type="number"
                  min="0"
                  step="0.01"
                  value={editPayForm.hourly_rate}
                  onChange={(e) =>
                    setEditPayForm({
                      ...editPayForm,
                      hourly_rate: e.target.value,
                    })
                  }
                />
              ) : null}
            </div>
          </div>
          <DialogFooter className="gap-2 sm:justify-end">
            <Button
              className={wizardOutlineBtnClass}
              variant="outline"
              onClick={() => setEditingPayPosition(null)}
            >
              Cancel
            </Button>
            <Button
              className={wizardPrimaryBtnClass}
              disabled={!editPayDraftValid || savePayConfigs.isPending}
              onClick={() => savePayConfigs.mutate()}
            >
              {savePayConfigs.isPending ? "Saving..." : "Save"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </OwnerPage>
  );
}
