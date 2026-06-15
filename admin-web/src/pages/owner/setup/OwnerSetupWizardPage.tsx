import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
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
  getPayrollConfig,
  listHolidays,
  listPositions,
  listShifts,
  seedDefaultHolidays,
  updateAttendancePolicy,
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
  "Review",
];

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
    overtime_rate_per_minute: "5",
    missing_clock_out_policy: "auto_clock_out",
    attendance_based_salary_enabled: true,
  });
  const [restForm, setRestForm] = useState({
    weekly_rest_day: "sunday",
    work_on_rest_day_allowed: false,
    rest_day_premium_percent: "30",
    use_custom_premium: false,
    custom_premium_percent: "",
  });

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
      }),
    onSuccess: () => {
      toast.success("Payroll configuration saved");
      qc.invalidateQueries({ queryKey: ["setup-status"] });
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
        overtime_enabled: attForm.overtime_enabled,
        overtime_minimum_minutes: Number(attForm.overtime_minimum_minutes),
        overtime_rate_per_minute: Number(attForm.overtime_rate_per_minute),
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

  const finishSetup = useMutation({
    mutationFn: completeSetup,
    onSuccess: () => {
      toast.success("Business setup marked complete");
      localStorage.removeItem("aroll_setup_card_dismissed");
      qc.invalidateQueries({ queryKey: ["setup-status"] });
      qc.invalidateQueries({ queryKey: ["me"] });
      navigate("/owner/dashboard");
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
                    ["overtime_rate_per_minute", "OT Rate (₱/min)"],
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
                  Review your configuration and mark setup as complete. You can
                  always update settings later.
                </p>
                <ul className="text-sm space-y-1">
                  <li>Shifts: {shifts.length}</li>
                  <li>Positions: {positions.length}</li>
                  <li>Holidays: {holidays.filter((h) => h.business_id).length}</li>
                </ul>
                <Button
                  onClick={() => finishSetup.mutate()}
                  disabled={finishSetup.isPending}
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
