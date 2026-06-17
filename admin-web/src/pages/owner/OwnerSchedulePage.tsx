import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useMemo, useState } from "react";
import { toast } from "sonner";
import { AssignScheduleForm } from "@/components/owner/schedule/AssignScheduleForm";
import {
  downloadScheduleExcel,
  downloadSchedulePdf,
  printSchedule,
} from "@/components/owner/schedule/scheduleExport";
import {
  buildScheduleMatrix,
  formatWeekRange,
  getWeekStart,
  navigateWeek,
  toDateKey,
} from "@/components/owner/schedule/scheduleUtils";
import { WeeklyScheduleTable } from "@/components/owner/schedule/WeeklyScheduleTable";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  assignSchedule,
  getMe,
  getWeeklySchedule,
  listEmployees,
  listShifts,
} from "@/lib/api";
import { ME_QUERY_KEY } from "@/lib/authSession";

export function OwnerSchedulePage() {
  const qc = useQueryClient();
  const [weekStart, setWeekStart] = useState(() => getWeekStart(new Date()));
  const [shiftId, setShiftId] = useState("");
  const [workDate, setWorkDate] = useState(toDateKey(new Date()));
  const [selectedEmployeeIds, setSelectedEmployeeIds] = useState<string[]>([]);

  const weekStartKey = toDateKey(weekStart);

  const { data: me } = useQuery({
    queryKey: ME_QUERY_KEY,
    queryFn: getMe,
  });

  const { data: employees = [], isLoading: employeesLoading } = useQuery({
    queryKey: ["employees"],
    queryFn: listEmployees,
  });

  const { data: shifts = [], isLoading: shiftsLoading } = useQuery({
    queryKey: ["shifts"],
    queryFn: listShifts,
  });

  const {
    data: weeklySchedule,
    isLoading: scheduleLoading,
    isError: scheduleError,
  } = useQuery({
    queryKey: ["weekly-schedule", weekStartKey],
    queryFn: () => getWeeklySchedule(weekStartKey),
  });

  const assignments = weeklySchedule?.assignments ?? [];

  const scheduleRows = useMemo(
    () => buildScheduleMatrix(employees, assignments, weekStart),
    [employees, assignments, weekStart]
  );

  const businessName = me?.business_name ?? "Business";

  const assign = useMutation({
    mutationFn: () =>
      assignSchedule({
        shift_id: shiftId,
        work_date: workDate,
        employee_ids: selectedEmployeeIds,
      }),
    onSuccess: (result) => {
      toast.success(
        result.created > 0
          ? `Assigned ${result.created} employee(s) to the schedule`
          : "Selected employees were already assigned to this shift"
      );
      setSelectedEmployeeIds([]);
      qc.invalidateQueries({ queryKey: ["weekly-schedule", weekStartKey] });
    },
    onError: (error: unknown) => {
      const message =
        error &&
        typeof error === "object" &&
        "response" in error &&
        error.response &&
        typeof error.response === "object" &&
        "data" in error.response &&
        error.response.data &&
        typeof error.response.data === "object" &&
        "detail" in error.response.data
          ? String(error.response.data.detail)
          : "Failed to assign schedule";
      toast.error(message);
    },
  });

  function toggleEmployee(employeeId: string) {
    setSelectedEmployeeIds((current) =>
      current.includes(employeeId)
        ? current.filter((id) => id !== employeeId)
        : [...current, employeeId]
    );
  }

  const isLoading = employeesLoading || shiftsLoading || scheduleLoading;

  return (
    <div className="min-h-full bg-muted/30 p-6">
      <div className="mx-auto max-w-6xl space-y-6">
        <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
          <div>
            <h1 className="text-2xl font-semibold">Schedules</h1>
            <p className="mt-1 text-muted-foreground">
              Assign shifts to employees and review the weekly schedule.
            </p>
          </div>

          <div className="flex items-center gap-2">
            <Button
              variant="outline"
              onClick={() => setWeekStart((current) => navigateWeek(current, "prev"))}
            >
              Previous Week
            </Button>
            <div className="min-w-[220px] rounded-md border bg-background px-4 py-2 text-center text-sm font-medium">
              {formatWeekRange(weekStart)}
            </div>
            <Button
              variant="outline"
              onClick={() => setWeekStart((current) => navigateWeek(current, "next"))}
            >
              Next Week
            </Button>
          </div>
        </div>

        {scheduleError && (
          <p className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
            Unable to load schedule data. Restart the backend and try again.
          </p>
        )}

        <AssignScheduleForm
          shifts={shifts}
          employees={employees}
          assignments={assignments}
          shiftId={shiftId}
          workDate={workDate}
          selectedEmployeeIds={selectedEmployeeIds}
          loading={assign.isPending}
          onShiftChange={setShiftId}
          onDateChange={setWorkDate}
          onToggleEmployee={toggleEmployee}
          onAssign={() => assign.mutate()}
        />

        <Card>
          <CardHeader className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
            <div>
              <CardTitle>Weekly Schedule</CardTitle>
              <p className="mt-1 text-sm text-muted-foreground">
                Employee assignments for {formatWeekRange(weekStart)}.
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              <Button
                variant="outline"
                onClick={() =>
                  downloadSchedulePdf({
                    businessName,
                    weekStart,
                    rows: scheduleRows,
                  })
                }
                disabled={isLoading}
              >
                Download PDF
              </Button>
              <Button
                variant="outline"
                onClick={() =>
                  downloadScheduleExcel({
                    businessName,
                    weekStart,
                    rows: scheduleRows,
                  })
                }
                disabled={isLoading}
              >
                Export Excel
              </Button>
              <Button
                variant="outline"
                onClick={() =>
                  printSchedule({
                    businessName,
                    weekStart,
                    rows: scheduleRows,
                  })
                }
                disabled={isLoading}
              >
                Print Schedule
              </Button>
            </div>
          </CardHeader>
          <CardContent>
            {isLoading ? (
              <p className="text-sm text-muted-foreground">Loading schedule…</p>
            ) : shifts.length === 0 ? (
              <p className="text-sm text-muted-foreground">
                No shifts found. Create shifts in Business Setup before
                assigning schedules.
              </p>
            ) : (
              <WeeklyScheduleTable weekStart={weekStart} rows={scheduleRows} />
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
