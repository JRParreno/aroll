import { useMemo } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { countShiftAssignmentsOnDate } from "@/components/owner/schedule/scheduleUtils";
import type { Employee, ScheduleAssignment, Shift } from "@/lib/api";

type Props = {
  shifts: Shift[];
  employees: Employee[];
  assignments: ScheduleAssignment[];
  shiftId: string;
  workDate: string;
  selectedEmployeeIds: string[];
  loading: boolean;
  onShiftChange: (shiftId: string) => void;
  onDateChange: (workDate: string) => void;
  onToggleEmployee: (employeeId: string) => void;
  onAssign: () => void;
};

export function AssignScheduleForm({
  shifts,
  employees,
  assignments,
  shiftId,
  workDate,
  selectedEmployeeIds,
  loading,
  onShiftChange,
  onDateChange,
  onToggleEmployee,
  onAssign,
}: Props) {
  const selectedShift = shifts.find((shift) => shift.id === shiftId);

  const capacityInfo = useMemo(() => {
    if (!selectedShift || !workDate) {
      return null;
    }

    const assignedCount = countShiftAssignmentsOnDate(
      assignments,
      selectedShift.id,
      workDate
    );
    const remaining = Math.max(
      selectedShift.employee_capacity - assignedCount,
      0
    );

    return {
      assignedCount,
      remaining,
      capacity: selectedShift.employee_capacity,
    };
  }, [assignments, selectedShift, workDate]);

  const exceedsCapacity =
    capacityInfo !== null &&
    selectedEmployeeIds.length > capacityInfo.remaining;

  return (
    <Card>
      <CardHeader>
        <CardTitle>Assign Schedule</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="grid gap-4 md:grid-cols-2">
          <div className="space-y-2">
            <Label htmlFor="schedule-shift">Shift</Label>
            <select
              id="schedule-shift"
              className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
              value={shiftId}
              onChange={(event) => onShiftChange(event.target.value)}
            >
              <option value="">Select shift</option>
              {shifts.map((shift) => (
                <option key={shift.id} value={shift.id}>
                  {shift.name} ({shift.start_time.slice(0, 5)} –{" "}
                  {shift.end_time.slice(0, 5)}, cap {shift.employee_capacity})
                </option>
              ))}
            </select>
          </div>

          <div className="space-y-2">
            <Label htmlFor="schedule-date">Date</Label>
            <Input
              id="schedule-date"
              type="date"
              value={workDate}
              onChange={(event) => onDateChange(event.target.value)}
            />
          </div>
        </div>

        {selectedShift && capacityInfo && (
          <p className="text-sm text-muted-foreground">
            {capacityInfo.assignedCount} of {capacityInfo.capacity} slots filled
            on this date. {capacityInfo.remaining} remaining.
          </p>
        )}

        <div className="space-y-2">
          <Label>Employees</Label>
          {employees.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              No employees available. Add employees first.
            </p>
          ) : (
            <div className="max-h-48 space-y-2 overflow-y-auto rounded-md border p-3">
              {employees.map((employee) => (
                <label
                  key={employee.id}
                  className="flex items-center gap-2 text-sm"
                >
                  <input
                    type="checkbox"
                    checked={selectedEmployeeIds.includes(employee.id)}
                    onChange={() => onToggleEmployee(employee.id)}
                  />
                  <span>{employee.full_name}</span>
                  <span className="text-muted-foreground">
                    {employee.position_title ?? "—"}
                  </span>
                </label>
              ))}
            </div>
          )}
        </div>

        {exceedsCapacity && (
          <p className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
            Selected employees exceed shift capacity. Choose at most{" "}
            {capacityInfo?.remaining ?? 0} employee(s).
          </p>
        )}

        <Button
          onClick={onAssign}
          disabled={
            loading ||
            !shiftId ||
            !workDate ||
            selectedEmployeeIds.length === 0 ||
            exceedsCapacity
          }
        >
          Assign Schedule
        </Button>
      </CardContent>
    </Card>
  );
}
