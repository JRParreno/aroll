import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useMemo, useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
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
  listHolidays,
  listPositions,
  listShifts,
  seedDefaultHolidays,
  updateAttendancePolicy,
  updateBusinessLocation,
  updatePayrollConfig,
  updateRestDayPolicy,
} from "@/lib/api";

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
  const { data: holidays = [], refetch: refetchHolidays } = useQuery({
    queryKey: ["holidays"],
    queryFn: listHolidays,
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

  const seedHolidays = useMutation({
    mutationFn: seedDefaultHolidays,
    onSuccess: () => {
      toast.success("Philippine holidays added");
      refetchHolidays();
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

  const locationCanSave =
    locationForm.address.trim().length >= 5 &&
    locationForm.latitude !== "" &&
    locationForm.longitude !== "" &&
    Number(locationForm.geofence_radius_m) >= 20 &&
    Number(locationForm.geofence_radius_m) <= 200;

  const finishSetup = useMutation({
    mutationFn: completeSetup,
    onSuccess: () => {
      toast.success("Business setup marked complete");
      localStorage.removeItem("aroll_setup_card_dismissed");
      qc.invalidateQueries({ queryKey: ["setup-status"] });
      qc.invalidateQueries({ queryKey: ["me"] });
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

  return (
    <div className="min-h-screen bg-muted/30 p-6">
      <div className="mx-auto max-w-3xl space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-semibold">Business Setup Wizard</h1>
            <p className="text-sm text-muted-foreground">
              Step {step + 1} of {STEPS.length}: {STEPS[step]}
            </p>
          </div>
          <Button variant="outline" asChild>
            <Link to="/owner/dashboard">Exit to Dashboard</Link>
          </Button>
        </div>

        <div className="flex gap-2 overflow-x-auto pb-2">
          {STEPS.map((label, i) => (
            <button
              key={label}
              type="button"
              onClick={() => setStep(i)}
              className={`whitespace-nowrap rounded-full px-3 py-1 text-xs ${
                i === step
                  ? "bg-[#1e3a5f] text-white"
                  : "bg-muted text-muted-foreground"
              }`}
            >
              {label}
            </button>
          ))}
        </div>

        <Card>
          <CardHeader>
            <CardTitle>{STEPS[step]}</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            {step === 0 && (
              <>
                <div className="grid gap-4 sm:grid-cols-2">
                  <div className="space-y-2">
                    <Label>Shift Name</Label>
                    <Input
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
                      className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
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
                  onClick={() => addShift.mutate()}
                  disabled={!shiftForm.name || addShift.isPending}
                >
                  Add Shift
                </Button>
                <ul className="divide-y text-sm">
                  {shifts.map((s) => (
                    <li
                      key={s.id}
                      className="flex items-center justify-between py-2"
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
                <div className="grid gap-4 sm:grid-cols-2">
                  <div className="space-y-2">
                    <Label>Position Name</Label>
                    <Input
                      value={posForm.title}
                      onChange={(e) =>
                        setPosForm({ ...posForm, title: e.target.value })
                      }
                    />
                  </div>
                  <div className="space-y-2">
                    <Label>Daily Rate (₱)</Label>
                    <Input
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
                      value={posForm.description}
                      onChange={(e) =>
                        setPosForm({ ...posForm, description: e.target.value })
                      }
                    />
                  </div>
                </div>
                <Button
                  onClick={() => addPosition.mutate()}
                  disabled={!posForm.title || !posForm.daily_rate}
                >
                  Add Position
                </Button>
                <ul className="divide-y text-sm">
                  {positions.map((p) => (
                    <li
                      key={p.id}
                      className="flex items-center justify-between py-2"
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
                <div className="grid gap-4 sm:grid-cols-2">
                  <div className="space-y-2">
                    <Label>Pay Period Type</Label>
                    <select
                      className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
                      value={payrollForm.pay_period_type}
                      onChange={(e) =>
                        setPayrollForm({
                          ...payrollForm,
                          pay_period_type: e.target.value,
                        })
                      }
                    >
                      <option value="weekly">Weekly</option>
                      <option value="bi_weekly">Bi-Weekly</option>
                      <option value="semi_monthly">Semi-Monthly</option>
                      <option value="monthly">Monthly</option>
                    </select>
                  </div>
                  <div className="space-y-2">
                    <Label>Next Payday Date</Label>
                    <Input
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
                <label className="flex items-center gap-2 text-sm">
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

                <div className="rounded-lg border p-4 space-y-4">
                  <p className="text-sm font-medium">Payroll Rules (W1)</p>
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

                <Button onClick={() => savePayroll.mutate()}>Save Payroll</Button>
              </>
            )}

            {step === 3 && (
              <>
                <div className="grid gap-4 sm:grid-cols-2">
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
                        type="number"
                        value={attForm[key as keyof typeof attForm] as string}
                        onChange={(e) =>
                          setAttForm({ ...attForm, [key]: e.target.value })
                        }
                      />
                    </div>
                  ))}
                </div>
                <p className="text-sm text-muted-foreground">
                  Overtime rate uses payroll configuration: ₱
                  {payrollForm.overtime_per_minute}/min (
                  {payrollForm.overtime_enabled ? "enabled" : "disabled"}). Update
                  in the Payroll step.
                </p>
                <Button onClick={() => saveAttendance.mutate()}>
                  Save Attendance Policy
                </Button>
              </>
            )}

            {step === 4 && (
              <>
                <p className="text-sm text-muted-foreground">
                  Load default Philippine holidays or manage your own.
                </p>
                <Button
                  variant="outline"
                  onClick={() => seedHolidays.mutate()}
                  disabled={seedHolidays.isPending}
                >
                  Load Philippine Holidays
                </Button>
                <ul className="divide-y text-sm">
                  {holidays
                    .filter((h) => h.business_id)
                    .map((h) => (
                      <li key={h.id} className="py-2">
                        {h.name} — {h.holiday_date}
                      </li>
                    ))}
                </ul>
              </>
            )}

            {step === 5 && (
              <>
                <div className="grid gap-4 sm:grid-cols-2">
                  <div className="space-y-2">
                    <Label>Weekly Rest Day</Label>
                    <select
                      className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
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
                <Button onClick={() => saveRestDay.mutate()}>
                  Save Rest Day Policy
                </Button>
              </>
            )}

            {step === 6 && (
              <>
                <p className="text-sm text-muted-foreground">
                  Set your primary work site and geofence. Required before
                  employees can clock in for attendance.
                </p>
                <div className="space-y-2">
                  <Label>Address</Label>
                  <Input
                    value={locationForm.address}
                    onChange={(e) =>
                      setLocationForm({ ...locationForm, address: e.target.value })
                    }
                    placeholder="123 Main St, Manila"
                  />
                </div>
                <div className="grid gap-4 sm:grid-cols-2">
                  <div className="space-y-2">
                    <Label>Latitude</Label>
                    <Input
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
                    className="w-full"
                  />
                  <p className="text-xs text-muted-foreground">
                    Allowed range: 20m – 200m (default 75m)
                  </p>
                </div>
                <Button
                  onClick={() => saveLocation.mutate()}
                  disabled={!locationCanSave || saveLocation.isPending}
                >
                  Save Location
                </Button>
              </>
            )}

            {step === 7 && (
              <>
                <p className="text-sm text-muted-foreground">
                  Review your configuration and mark setup as complete. Required
                  steps: schedules, positions, payroll, and location.
                </p>
                <ul className="space-y-1 text-sm">
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
                  onClick={() => finishSetup.mutate()}
                  disabled={finishSetup.isPending || !canCompleteSetup}
                >
                  Mark Setup Complete
                </Button>
              </>
            )}
          </CardContent>
        </Card>

        <div className="flex justify-between">
          <Button
            variant="outline"
            disabled={step === 0}
            onClick={() => setStep((s) => s - 1)}
          >
            Back
          </Button>
          <div className="flex gap-2">
            {step < STEPS.length - 1 && (
              <>
                <Button variant="ghost" onClick={() => setStep((s) => s + 1)}>
                  Skip for now
                </Button>
                <Button onClick={() => setStep((s) => s + 1)}>Continue</Button>
              </>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
