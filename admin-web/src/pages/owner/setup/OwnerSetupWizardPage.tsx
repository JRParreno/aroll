import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useMemo, useState } from "react";
import {
  ArrowRight,
  CheckCircle2,
  Circle,
  ClipboardCheck,
} from "lucide-react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { HolidaySetupSection } from "@/components/owner/setup/HolidaySetupSection";
import { OwnerPageBackLink } from "@/components/owner/layout/OwnerPageLayout";
import {
  completeSetup,
  createPosition,
  createShift,
  deletePosition,
  deleteShift,
  getAttendancePolicy,
  getBusinessLocation,
  getPayrollConfig,
  getRestDayPolicy,
  getSetupStatus,
  listPositions,
  listShifts,
  updateAttendancePolicy,
  updateBusinessLocation,
  updatePayrollConfig,
  updateRestDayPolicy,
} from "@/lib/api";
import { ME_QUERY_KEY } from "@/lib/authSession";

const STEPS = [
  "Shifts",
  "Positions",
  "Payroll",
  "Attendance",
  "Holidays",
  "Location",
  "Review",
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

const STEP_HELP: Record<string, string> = {
  Shifts: "Add the work shifts your employees can be assigned to.",
  Positions: "Create job roles and daily rates for payroll calculations.",
  Payroll:
    "Set pay schedules, deductions, overtime, and rest day premium rules.",
  Attendance: "Choose the time rules used for lateness, absences, and overtime.",
  Holidays:
    "Add the holidays your business follows. This helps schedules and pay stay accurate.",
  Location:
    "Set your business work site so attendance can be checked by location.",
  Review: "Check your setup progress and finish when the required parts are ready.",
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
  const { data: businessLocation } = useQuery({
    queryKey: ["business-location"],
    queryFn: getBusinessLocation,
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
  const [posForm, setPosForm] = useState({
    title: "",
    daily_rate: "",
    description: "",
  });
  const [payrollForm, setPayrollForm] = useState({
    pay_period_type: "monthly",
    auto_reset_payroll_cycle: true,
    late_deduction_enabled: true,
    late_deduction_per_minute: "1",
    overtime_enabled: true,
    overtime_per_minute: "1",
    weekly_payday_weekday: "friday",
    semi_monthly_preset: "15_30",
    semi_monthly_payday_1: "15",
    semi_monthly_payday_2: "30",
    monthly_payday_day: "30",
  });
  const [attForm, setAttForm] = useState({
    early_clock_in_minutes: "15",
    on_time_grace_minutes: "10",
    half_day_threshold_minutes: "120",
    absent_threshold_minutes: "240",
    early_out_deduction_enabled: false,
    early_out_deduction_per_minute: "2",
    overtime_enabled: true,
    overtime_minimum_minutes: "30",
    missing_clock_out_policy: "auto_clock_out",
    attendance_based_salary_enabled: true,
  });
  const [locationForm, setLocationForm] = useState({
    label: "Main",
    address: "",
    latitude: "",
    longitude: "",
    geofence_radius_m: "75",
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
      early_out_deduction_enabled: attendancePolicy.early_out_deduction_enabled,
      early_out_deduction_per_minute: String(
        attendancePolicy.early_out_deduction_per_minute
      ),
      overtime_enabled: attendancePolicy.overtime_enabled,
      overtime_minimum_minutes: String(attendancePolicy.overtime_minimum_minutes),
      missing_clock_out_policy: attendancePolicy.missing_clock_out_policy,
      attendance_based_salary_enabled:
        attendancePolicy.attendance_based_salary_enabled,
    });
  }, [attendancePolicy]);

  useEffect(() => {
    if (!businessLocation) return;
    setLocationForm({
      label: businessLocation.label,
      address: businessLocation.address,
      latitude: businessLocation.latitude?.toString() ?? "",
      longitude: businessLocation.longitude?.toString() ?? "",
      geofence_radius_m: String(businessLocation.geofence_radius_m),
    });
  }, [businessLocation]);

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
    posForm.title.trim().length > 0 && Number(posForm.daily_rate) > 0;

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

  const locationCanSave =
    locationForm.address.trim().length >= 5 &&
    locationForm.latitude !== "" &&
    locationForm.longitude !== "" &&
    Number(locationForm.geofence_radius_m) >= 20 &&
    Number(locationForm.geofence_radius_m) <= 200;

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
        return isStepComplete("location") || locationCanSave;
      default:
        return false;
    }
  }, [
    step,
    setupStepComplete,
    shiftDraftValid,
    positionDraftValid,
    payrollFormValid,
    locationCanSave,
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
      toast.success("Shift added");
      setShiftForm({ ...shiftForm, name: "" });
      refetchShifts();
      qc.invalidateQueries({ queryKey: ["setup-status"] });
    },
  });

  const addPosition = useMutation({
    mutationFn: () =>
      createPosition({
        title: posForm.title,
        daily_rate: Number(posForm.daily_rate),
        description: posForm.description || undefined,
      }),
    onSuccess: () => {
      toast.success("Position added");
      setPosForm({ title: "", daily_rate: "", description: "" });
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
      toast.success("Payroll configuration saved");
      qc.invalidateQueries({ queryKey: ["setup-status"] });
      qc.invalidateQueries({ queryKey: ["payroll-config"] });
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
        early_out_deduction_enabled: attForm.early_out_deduction_enabled,
        early_out_deduction_per_minute: Number(
          attForm.early_out_deduction_per_minute
        ),
        overtime_minimum_minutes: Number(attForm.overtime_minimum_minutes),
        missing_clock_out_policy: attForm.missing_clock_out_policy,
        attendance_based_salary_enabled: attForm.attendance_based_salary_enabled,
      }),
    onSuccess: () => {
      toast.success("Attendance policy saved");
      qc.invalidateQueries({ queryKey: ["setup-status"] });
    },
  });

  const saveLocation = useMutation({
    mutationFn: () =>
      updateBusinessLocation({
        label: locationForm.label,
        address: locationForm.address,
        latitude: locationForm.latitude ? Number(locationForm.latitude) : null,
        longitude: locationForm.longitude ? Number(locationForm.longitude) : null,
        geofence_radius_m: Number(locationForm.geofence_radius_m),
      }),
    onSuccess: () => {
      toast.success("Business location saved");
      qc.invalidateQueries({ queryKey: ["business-location"] });
      qc.invalidateQueries({ queryKey: ["setup-status"] });
    },
    onError: () => toast.error("Failed to save location"),
  });

  const finishSetup = useMutation({
    mutationFn: completeSetup,
    onSuccess: () => {
      toast.success("Business setup marked complete");
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
      toast.error(missing ?? "Complete all required setup steps first");
      qc.invalidateQueries({ queryKey: ["setup-status"] });
    },
  });

  const continuePending =
    addShift.isPending ||
    addPosition.isPending ||
    savePayroll.isPending ||
    saveLocation.isPending;

  async function handleContinue() {
    if (!currentStepCanContinue) return;

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
      if (step === 5 && !isStepComplete("location") && locationCanSave) {
        await saveLocation.mutateAsync();
      }
      goToStep(Math.min(step + 1, STEPS.length - 1));
    } catch {
      toast.error("Save this step before continuing.");
    }
  }

  return (
    <div className="min-h-screen bg-[#F7F8FA] px-4 py-6 text-[#1F2937] sm:px-6 lg:px-8">
      <div className="mx-auto max-w-5xl space-y-6">
        <OwnerPageBackLink
          to={step < 0 ? "/owner/settings/setup" : "/owner/setup-wizard?step=menu"}
          label={step < 0 ? "Back to Business Setup" : "Back to Setup Menu"}
        />

        <header className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm sm:p-6">
          <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
            <div className="min-w-0">
              <div className="mb-3 inline-flex items-center gap-2 rounded-full bg-[#EAF2FB] px-3 py-1.5 text-xs font-medium text-[#1E3A5F]">
                <ClipboardCheck className="h-4 w-4" />
                Business setup
              </div>
              <h1 className="text-2xl font-semibold tracking-tight text-[#1F2937]">
                Business Setup Wizard
              </h1>
              <p className="mt-2 max-w-2xl text-sm leading-6 text-[#6B7280]">
                {step < 0
                  ? "Choose a setup section to configure. You can return anytime from Business Setup."
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
                    <Label>Shift Name</Label>
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
                    <Label>Shift Type</Label>
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
                    <Label>Start Time</Label>
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
                    <Label>End Time</Label>
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
                    <Label>Break Minutes</Label>
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
                    <Label>Employee Capacity</Label>
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
                  Add Shift
                </Button>
                <ul className="overflow-hidden rounded-2xl border border-slate-200 text-sm">
                  {shifts.map((s) => (
                    <li
                      key={s.id}
                      className="flex items-center justify-between gap-3 border-b border-slate-100 px-4 py-3 last:border-b-0"
                    >
                      <span>
                        {s.name} ({s.start_time}–{s.end_time})
                      </span>
                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() =>
                          deleteShift(s.id).then(() => refetchShifts())
                        }
                      >
                        Remove
                      </Button>
                    </li>
                  ))}
                </ul>
              </>
            )}

            {step === 1 && (
              <>
                <div className="grid gap-5 sm:grid-cols-2">
                  <div className="space-y-2">
                    <Label>Position Name</Label>
                    <Input
                      className="h-11 rounded-xl border-slate-200 bg-white"
                      value={posForm.title}
                      onChange={(e) =>
                        setPosForm({ ...posForm, title: e.target.value })
                      }
                    />
                  </div>
                  <div className="space-y-2">
                    <Label>Daily Rate (₱)</Label>
                    <Input
                      className="h-11 rounded-xl border-slate-200 bg-white"
                      type="number"
                      value={posForm.daily_rate}
                      onChange={(e) =>
                        setPosForm({ ...posForm, daily_rate: e.target.value })
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
                  disabled={!posForm.title || !posForm.daily_rate}
                >
                  Add Position
                </Button>
                <ul className="overflow-hidden rounded-2xl border border-slate-200 text-sm">
                  {positions.map((p) => (
                    <li
                      key={p.id}
                      className="flex items-center justify-between gap-3 border-b border-slate-100 px-4 py-3 last:border-b-0"
                    >
                      <span>
                        {p.title} — ₱{p.daily_rate}/day
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
                    <Label>Pay Period Type</Label>
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
                      <option value="semi_monthly">Semi-Monthly</option>
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
                  Automatically reset payroll cycle after payday
                </label>

                <div className="space-y-4 rounded-2xl border border-slate-200 bg-[#FAFBFC] p-4">
                  <p className="text-sm font-medium text-[#1F2937]">
                    Pay Rules
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
                    Enable late deduction
                  </label>
                  <div className="space-y-2">
                    <Label>Late Deduction (₱/min)</Label>
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
                    Enable overtime pay
                  </label>
                  <div className="space-y-2">
                    <Label>Overtime Rate (₱/min)</Label>
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
                </div>

                <div className="space-y-4 rounded-2xl border border-slate-200 bg-[#FAFBFC] p-4">
                  <div>
                    <p className="text-sm font-medium text-[#1F2937]">
                      Rest Day Pay
                    </p>
                    <p className="mt-1 text-xs text-muted-foreground">
                      Set the premium rate for shifts the owner or manager
                      marks as approved rest day work on the schedule.
                    </p>
                  </div>
                  <div className="space-y-2 sm:max-w-xs">
                    <Label>Rest Day Premium (%)</Label>
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
                      30% adds 0.30 × the employee's daily rate.
                    </p>
                  </div>
                </div>

                <Button
                  className="rounded-xl bg-[#1E3A5F] hover:bg-[#284B73]"
                  onClick={() => savePayroll.mutate()}
                  disabled={!payrollFormValid || savePayroll.isPending}
                >
                  Save Payroll Configuration
                </Button>
              </>
            )}

            {step === 3 && (
              <>
                <div className="grid gap-5 sm:grid-cols-2">
                  {[
                    ["early_clock_in_minutes", "Early Clock-In Window (min)"],
                    ["on_time_grace_minutes", "On-Time Grace (min)"],
                    ["half_day_threshold_minutes", "Half-Day Threshold (min)"],
                    ["absent_threshold_minutes", "Absent Threshold (min)"],
                    ["overtime_minimum_minutes", "Min Overtime (min)"],
                  ].map(([key, label]) => (
                    <div key={key} className="space-y-2">
                      <Label>{label}</Label>
                      <Input
                        className="h-11 rounded-xl border-slate-200 bg-white"
                        type="number"
                        value={attForm[key as keyof typeof attForm] as string}
                        onChange={(e) =>
                          setAttForm({ ...attForm, [key]: e.target.value })
                        }
                      />
                    </div>
                  ))}
                </div>
                <p className="rounded-xl bg-[#F3F6FA] px-4 py-3 text-sm text-[#6B7280]">
                  Overtime rate uses payroll configuration: ₱
                  {payrollForm.overtime_per_minute}/min (
                  {payrollForm.overtime_enabled ? "enabled" : "disabled"}). Update
                  in the Payroll step.
                </p>
                <Button
                  className="rounded-xl bg-[#1E3A5F] hover:bg-[#284B73]"
                  onClick={() => saveAttendance.mutate()}
                >
                  Save Attendance Policy
                </Button>
              </>
            )}

            {step === 4 && <HolidaySetupSection />}

            {step === 5 && (
              <>
                <p className="rounded-xl bg-[#F3F6FA] px-4 py-3 text-sm text-[#6B7280]">
                  Set your primary work site and geofence. Required before
                  employees can clock in for attendance.
                </p>
                <div className="space-y-2">
                  <Label>Address</Label>
                  <Input
                    className="h-11 rounded-xl border-slate-200 bg-white"
                    value={locationForm.address}
                    onChange={(e) =>
                      setLocationForm({ ...locationForm, address: e.target.value })
                    }
                    placeholder="123 Main St, Manila"
                  />
                </div>
                <div className="grid gap-5 sm:grid-cols-2">
                  <div className="space-y-2">
                    <Label>Latitude</Label>
                    <Input
                      className="h-11 rounded-xl border-slate-200 bg-white"
                      type="number"
                      step="any"
                      value={locationForm.latitude}
                      onChange={(e) =>
                        setLocationForm({
                          ...locationForm,
                          latitude: e.target.value,
                        })
                      }
                      placeholder="14.5995"
                    />
                  </div>
                  <div className="space-y-2">
                    <Label>Longitude</Label>
                    <Input
                      className="h-11 rounded-xl border-slate-200 bg-white"
                      type="number"
                      step="any"
                      value={locationForm.longitude}
                      onChange={(e) =>
                        setLocationForm({
                          ...locationForm,
                          longitude: e.target.value,
                        })
                      }
                      placeholder="120.9842"
                    />
                  </div>
                </div>
                <div className="space-y-2">
                  <Label>
                    Geofence Radius: {locationForm.geofence_radius_m}m
                  </Label>
                  <input
                    type="range"
                    min={20}
                    max={200}
                    step={5}
                    value={locationForm.geofence_radius_m}
                    onChange={(e) =>
                      setLocationForm({
                        ...locationForm,
                        geofence_radius_m: e.target.value,
                      })
                    }
                    className="w-full accent-[#1E3A5F]"
                  />
                  <p className="text-xs text-muted-foreground">
                    Allowed range: 20m – 200m (default 75m)
                  </p>
                </div>
                <Button
                  className="rounded-xl bg-[#1E3A5F] hover:bg-[#284B73]"
                  onClick={() => saveLocation.mutate()}
                  disabled={!locationCanSave || saveLocation.isPending}
                >
                  Save Location
                </Button>
              </>
            )}

            {step === 6 && (
              <>
                <p className="rounded-xl bg-[#F3F6FA] px-4 py-3 text-sm text-[#6B7280]">
                  Review your configuration and mark setup as complete. Required
                  steps: schedules, positions, payroll, and location.
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
                    Complete required items:{" "}
                    {setupStatus.missing_items.join(", ")}
                  </p>
                ) : null}
                <Button
                  className="rounded-xl bg-[#1E3A5F] hover:bg-[#284B73]"
                  onClick={() => finishSetup.mutate()}
                  disabled={finishSetup.isPending || !canCompleteSetup}
                >
                  Mark Setup Complete
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
    </div>
  );
}
