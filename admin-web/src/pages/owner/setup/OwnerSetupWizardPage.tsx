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
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { HolidaySetupSection } from "@/components/owner/setup/HolidaySetupSection";
import {
  completeSetup,
  createPosition,
  createShift,
  deletePosition,
  deleteShift,
  getAttendancePolicy,
  getBusinessLocation,
  getPayrollConfig,
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
  "Rest Day",
  "Location",
  "Review",
];

const STEP_HELP: Record<string, string> = {
  Shifts: "Add the work shifts your employees can be assigned to.",
  Positions: "Create job roles and daily rates for payroll calculations.",
  Payroll: "Set when employees are paid and how pay rules are applied.",
  Attendance: "Choose the time rules used for lateness, absences, and overtime.",
  Holidays:
    "Add the holidays your business follows. This helps schedules and pay stay accurate.",
  "Rest Day": "Choose the regular weekly rest day and rest day pay settings.",
  Location:
    "Set your business work site so attendance can be checked by location.",
  Review: "Check your setup progress and finish when the required parts are ready.",
};

const REQUIRED_SETUP_KEYS = new Set(["shifts", "positions", "payroll", "location"]);

export function OwnerSetupWizardPage() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const qc = useQueryClient();
  const initialStep = Math.min(
    Math.max(Number(searchParams.get("step") ?? "0"), 0),
    STEPS.length - 1
  );
  const [step, setStep] = useState(initialStep);

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
    next_payday_date: "",
    auto_reset_payroll_cycle: true,
    late_deduction_enabled: true,
    late_deduction_per_minute: "1",
    overtime_enabled: true,
    overtime_per_minute: "1",
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
    weekly_rest_day: "sunday",
    work_on_rest_day_allowed: false,
    rest_day_premium_percent: "30",
    use_custom_premium: false,
    custom_premium_percent: "",
  });

  useEffect(() => {
    if (!payroll) return;
    setPayrollForm({
      pay_period_type: payroll.pay_period_type,
      next_payday_date: payroll.next_payday_date ?? "",
      auto_reset_payroll_cycle: payroll.auto_reset_payroll_cycle,
      late_deduction_enabled: payroll.late_deduction_enabled,
      late_deduction_per_minute: String(payroll.late_deduction_per_minute),
      overtime_enabled: payroll.overtime_enabled,
      overtime_per_minute: String(payroll.overtime_per_minute),
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

  const payrollFormValid =
    Boolean(payrollForm.next_payday_date) &&
    Number(payrollForm.late_deduction_per_minute) >= 0 &&
    Number(payrollForm.overtime_per_minute) >= 0;

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
        return isStepComplete("rest_day");
      case 6:
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
      updatePayrollConfig({
        pay_period_type: payrollForm.pay_period_type,
        next_payday_date: payrollForm.next_payday_date || null,
        auto_reset_payroll_cycle: payrollForm.auto_reset_payroll_cycle,
        late_deduction_enabled: payrollForm.late_deduction_enabled,
        late_deduction_per_minute: Number(payrollForm.late_deduction_per_minute),
        overtime_enabled: payrollForm.overtime_enabled,
        overtime_per_minute: Number(payrollForm.overtime_per_minute),
      }),
    onSuccess: () => {
      toast.success("Payroll configuration saved");
      qc.invalidateQueries({ queryKey: ["setup-status"] });
      qc.invalidateQueries({ queryKey: ["payroll-config"] });
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

  const saveRestDay = useMutation({
    mutationFn: () =>
      updateRestDayPolicy({
        weekly_rest_day: restForm.weekly_rest_day,
        work_on_rest_day_allowed: restForm.work_on_rest_day_allowed,
        rest_day_premium_percent: Number(restForm.rest_day_premium_percent),
        use_custom_premium: restForm.use_custom_premium,
        custom_premium_percent: restForm.custom_premium_percent
          ? Number(restForm.custom_premium_percent)
          : null,
      }),
    onSuccess: () => {
      toast.success("Rest day policy saved");
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
      if (step === 6 && !isStepComplete("location") && locationCanSave) {
        await saveLocation.mutateAsync();
      }
      setStep((s) => Math.min(s + 1, STEPS.length - 1));
    } catch {
      toast.error("Save this step before continuing.");
    }
  }

  return (
    <div className="min-h-screen bg-[#F7F8FA] px-4 py-6 text-[#1F2937] sm:px-6 lg:px-8">
      <div className="mx-auto max-w-5xl space-y-6">
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
                Complete the basics for scheduling, payroll, attendance, and
                location. You can skip a step and come back from the dashboard.
              </p>
            </div>
            <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
              <div className="rounded-2xl bg-[#F3F6FA] px-4 py-3 text-sm">
                <p className="font-medium text-[#1F2937]">
                  Step {step + 1} of {STEPS.length}
                </p>
                <p className="text-xs text-[#6B7280]">{STEPS[step]}</p>
              </div>
              <Button
                variant="outline"
                className="h-10 rounded-xl border-slate-200 bg-white"
                onClick={() => navigate("/owner/dashboard")}
                type="button"
              >
                Exit to Dashboard
              </Button>
            </div>
          </div>
        </header>

        <nav className="rounded-2xl border border-slate-200 bg-white p-3 shadow-sm">
          <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
            {STEPS.map((label, i) => {
              const key = setupStatus?.steps[i]?.key;
              const complete = key ? isStepComplete(key) : false;
              const active = i === step;
              const Icon = complete ? CheckCircle2 : Circle;

              return (
                <button
                  key={label}
                  type="button"
                  onClick={() => setStep(i)}
                  className={`flex items-center gap-3 rounded-xl border px-3 py-3 text-left text-sm transition ${
                    active
                      ? "border-[#1E3A5F] bg-[#1E3A5F] text-white shadow-sm"
                      : "border-slate-200 bg-[#FAFBFC] text-[#374151] hover:border-[#B9C7D8] hover:bg-white"
                  }`}
                >
                  <Icon
                    className={`h-4 w-4 shrink-0 ${
                      active ? "text-white" : complete ? "text-emerald-600" : "text-[#9CA3AF]"
                    }`}
                  />
                  <span className="min-w-0">
                    <span className="block truncate font-medium">{label}</span>
                    <span
                      className={`block text-xs ${
                        active ? "text-white/75" : "text-[#6B7280]"
                      }`}
                    >
                      {complete ? "Done" : `Step ${i + 1}`}
                    </span>
                  </span>
                </button>
              );
            })}
          </div>
        </nav>

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
                  <div className="space-y-2">
                    <Label>Next Payday Date</Label>
                    <Input
                      className="h-11 rounded-xl border-slate-200 bg-white"
                      type="date"
                      value={payrollForm.next_payday_date}
                      onChange={(e) =>
                        setPayrollForm({
                          ...payrollForm,
                          next_payday_date: e.target.value,
                        })
                      }
                    />
                  </div>
                </div>
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

                <Button
                  className="rounded-xl bg-[#1E3A5F] hover:bg-[#284B73]"
                  onClick={() => savePayroll.mutate()}
                >
                  Save Payroll
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
                <div className="grid gap-5 sm:grid-cols-2">
                  <div className="space-y-2">
                    <Label>Weekly Rest Day</Label>
                    <select
                      className="flex h-11 w-full rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm"
                      value={restForm.weekly_rest_day}
                      onChange={(e) =>
                        setRestForm({
                          ...restForm,
                          weekly_rest_day: e.target.value,
                        })
                      }
                    >
                      {[
                        "sunday",
                        "monday",
                        "tuesday",
                        "wednesday",
                        "thursday",
                        "friday",
                        "saturday",
                      ].map((d) => (
                        <option key={d} value={d}>
                          {d.charAt(0).toUpperCase() + d.slice(1)}
                        </option>
                      ))}
                    </select>
                  </div>
                  <div className="space-y-2">
                    <Label>Rest Day Premium (%)</Label>
                    <Input
                      className="h-11 rounded-xl border-slate-200 bg-white"
                      type="number"
                      value={restForm.rest_day_premium_percent}
                      onChange={(e) =>
                        setRestForm({
                          ...restForm,
                          rest_day_premium_percent: e.target.value,
                        })
                      }
                    />
                  </div>
                </div>
                <Button
                  className="rounded-xl bg-[#1E3A5F] hover:bg-[#284B73]"
                  onClick={() => saveRestDay.mutate()}
                >
                  Save Rest Day Policy
                </Button>
              </>
            )}

            {step === 6 && (
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

            {step === 7 && (
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

        <div className="flex flex-col-reverse gap-3 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:flex-row sm:items-center sm:justify-between">
          <Button
            variant="outline"
            className="h-10 rounded-xl border-slate-200"
            disabled={step === 0}
            onClick={() => setStep((s) => s - 1)}
          >
            <ArrowLeft className="mr-2 h-4 w-4" />
            Back
          </Button>
          <div className="flex flex-col gap-2 sm:flex-row">
            {step < STEPS.length - 1 && (
              <>
                <Button
                  variant="ghost"
                  className="h-10 rounded-xl"
                  onClick={() => setStep((s) => s + 1)}
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
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
