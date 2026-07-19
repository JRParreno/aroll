import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Download, FileSpreadsheet, Pencil, Plus, Printer, Search, Trash2, Users } from "lucide-react";
import { useMemo, useState } from "react";
import { toast } from "sonner";
import {
  downloadScheduleExcel,
  downloadSchedulePdf,
  printSchedule,
} from "@/components/owner/schedule/scheduleExport";
import {
  buildScheduleMatrix,
  formatShiftTime,
  formatWeekRange,
  getWeekDays,
  getWeekStart,
  navigateWeek,
  toDateKey,
  WEEKDAY_LABELS,
  type ScheduleCell,
} from "@/components/owner/schedule/scheduleUtils";
import { Button } from "@/components/ui/button";
import {
  OwnerPage,
  OwnerPageContent,
  OwnerPageHeader,
} from "@/components/owner/layout/OwnerPageLayout";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import {
  assignSchedule,
  createShift,
  deleteScheduleAssignment,
  getMe,
  getWeeklySchedule,
  listEmployees,
  listHolidays,
  listShifts,
  updateScheduleAssignment,
  type Employee,
  type ScheduleAssignment,
  type Shift,
} from "@/lib/api";
import { ME_QUERY_KEY } from "@/lib/authSession";

type EmployeeAvailability = "available" | "assigned" | "conflict";

const defaultTableColors = {
  header: "#1E3A5F",
  row1: "#FFE5A3",
  row2: "#FFB166",
  row3: "#B8F28C",
  row4: "#B9D8F7",
  row5: "#F2A7EA",
  off: "#F8B4B4",
  text: "#111827",
};

function initials(name: string) {
  return name
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join("");
}

function overlaps(first: Shift, second: Shift) {
  return first.start_time < second.end_time && second.start_time < first.end_time;
}

function statusTone(status: EmployeeAvailability) {
  if (status === "available") return "bg-emerald-50 text-emerald-700 border-emerald-100";
  if (status === "assigned") return "bg-blue-50 text-blue-700 border-blue-100";
  return "bg-amber-50 text-amber-700 border-amber-100";
}

export function OwnerSchedulePage() {
  const qc = useQueryClient();
  const [mode, setMode] = useState<"assign" | "viewer">("assign");
  const [weekStart, setWeekStart] = useState(() => getWeekStart(new Date()));
  const [workDate, setWorkDate] = useState(toDateKey(new Date()));
  const [selectedShiftId, setSelectedShiftId] = useState("");
  const [selectedEmployeeIds, setSelectedEmployeeIds] = useState<string[]>([]);
  const [employeeModalOpen, setEmployeeModalOpen] = useState(false);
  const [editingAssignmentId, setEditingAssignmentId] = useState<string | null>(null);
  const [isRestDayWork, setIsRestDayWork] = useState(false);
  const [search, setSearch] = useState("");
  const [positionFilter, setPositionFilter] = useState("all");
  const [typeFilter, setTypeFilter] = useState("all");
  const [availabilityFilter, setAvailabilityFilter] = useState("all");
  const [customizing, setCustomizing] = useState(false);
  const [tableColors, setTableColors] = useState(defaultTableColors);
  const [visibleDays, setVisibleDays] = useState(WEEKDAY_LABELS);
  const [defaultStart, setDefaultStart] = useState("09:00");
  const [defaultEnd, setDefaultEnd] = useState("17:00");
  const [showNewShift, setShowNewShift] = useState(false);
  const [newShift, setNewShift] = useState({
    name: "",
    start_time: "08:00",
    end_time: "15:00",
    employee_capacity: "6",
  });

  const weekStartKey = toDateKey(weekStart);

  const { data: me } = useQuery({
    queryKey: ME_QUERY_KEY,
    queryFn: getMe,
  });
  const { data: employees = [] } = useQuery({
    queryKey: ["employees"],
    queryFn: listEmployees,
  });
  const { data: shifts = [] } = useQuery({
    queryKey: ["shifts"],
    queryFn: listShifts,
  });
  const { data: holidays = [] } = useQuery({
    queryKey: ["holidays"],
    queryFn: listHolidays,
  });
  const { data: weeklySchedule, isLoading } = useQuery({
    queryKey: ["weekly-schedule", weekStartKey],
    queryFn: () => getWeeklySchedule(weekStartKey),
  });

  const assignments = weeklySchedule?.assignments ?? [];
  const businessName =
    me?.business_name ?? localStorage.getItem("aroll_business_name") ?? "Aroll+";
  const selectedShift = shifts.find((shift) => shift.id === selectedShiftId);
  const selectedHoliday = holidays.find(
    (holiday) => holiday.is_active && holiday.holiday_date === workDate
  );

  const positions = useMemo(
    () =>
      Array.from(
        new Set(employees.map((employee) => employee.position_title).filter(Boolean))
      ) as string[],
    [employees]
  );

  const assignmentsForDate = assignments.filter(
    (assignment) => assignment.work_date === workDate
  );
  const assignmentsByShift = useMemo(() => {
    const map = new Map<string, ScheduleAssignment[]>();
    for (const assignment of assignmentsForDate) {
      map.set(assignment.shift_id, [
        ...(map.get(assignment.shift_id) ?? []),
        assignment,
      ]);
    }
    return map;
  }, [assignmentsForDate]);

  function availabilityFor(employee: Employee): EmployeeAvailability {
    if (!selectedShift) return "available";
    const employeeAssignments = assignmentsForDate.filter(
      (assignment) =>
        assignment.employee_id === employee.id &&
        assignment.id !== editingAssignmentId
    );
    if (employeeAssignments.some((assignment) => assignment.shift_id === selectedShift.id)) {
      return "assigned";
    }
    const hasConflict = employeeAssignments.some((assignment) => {
      const assignedShift = shifts.find((shift) => shift.id === assignment.shift_id);
      return assignedShift ? overlaps(assignedShift, selectedShift) : true;
    });
    return hasConflict ? "conflict" : "available";
  }

  const filteredEmployees = employees.filter((employee) => {
    const availability = availabilityFor(employee);
    const matchesSearch = [
      employee.full_name,
      employee.position_title ?? "",
      employee.employment_type,
    ]
      .join(" ")
      .toLowerCase()
      .includes(search.toLowerCase());
    return (
      matchesSearch &&
      (positionFilter === "all" || employee.position_title === positionFilter) &&
      (typeFilter === "all" || employee.employment_type === typeFilter) &&
      (availabilityFilter === "all" || availability === availabilityFilter)
    );
  });

  const viewerEmployees = employees.filter((employee) => {
    const matchesSearch = [employee.full_name, employee.position_title ?? ""]
      .join(" ")
      .toLowerCase()
      .includes(search.toLowerCase());
    return (
      matchesSearch &&
      (positionFilter === "all" || employee.position_title === positionFilter)
    );
  });
  const scheduleRows = useMemo(
    () => buildScheduleMatrix(viewerEmployees, assignments, weekStart),
    [viewerEmployees, assignments, weekStart]
  );

  const assign = useMutation({
    mutationFn: () =>
      assignSchedule({
        shift_id: selectedShiftId,
        work_date: workDate,
        employee_ids: selectedEmployeeIds,
        is_rest_day_work: isRestDayWork,
      }),
    onSuccess: (result) => {
      toast.success(
        result.created > 0 ? `Assigned ${result.created} employee(s)` : "No new assignments"
      );
      setSelectedEmployeeIds([]);
      setIsRestDayWork(false);
      setEmployeeModalOpen(false);
      qc.invalidateQueries({ queryKey: ["weekly-schedule"] });
      qc.invalidateQueries({ queryKey: ["owner-performance"] });
    },
    onError: (error: unknown) => {
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
          ? String(error.response.data.detail)
          : "Failed to assign schedule";
      toast.error(detail);
    },
  });

  const editAssignment = useMutation({
    mutationFn: () =>
      updateScheduleAssignment(editingAssignmentId!, {
        shift_id: selectedShiftId,
        work_date: workDate,
        is_rest_day_work: isRestDayWork,
      }),
    onSuccess: () => {
      toast.success("Schedule updated");
      setEditingAssignmentId(null);
      setIsRestDayWork(false);
      qc.invalidateQueries({ queryKey: ["weekly-schedule"] });
      qc.invalidateQueries({ queryKey: ["owner-performance"] });
    },
    onError: (error: unknown) => {
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
          ? String(error.response.data.detail)
          : "Unable to update schedule";
      toast.error(detail);
    },
  });

  const addShift = useMutation({
    mutationFn: () =>
      createShift({
        name: newShift.name,
        shift_type: "morning",
        start_time: newShift.start_time,
        end_time: newShift.end_time,
        employee_capacity: Number(newShift.employee_capacity),
        break_minutes: 0,
      }),
    onSuccess: () => {
      toast.success("Shift created");
      setShowNewShift(false);
      setNewShift({ name: "", start_time: "08:00", end_time: "15:00", employee_capacity: "6" });
      qc.invalidateQueries({ queryKey: ["shifts"] });
    },
    onError: () => toast.error("Failed to create shift"),
  });

  const removeAssignment = useMutation({
    mutationFn: deleteScheduleAssignment,
    onSuccess: () => {
      toast.success("Schedule removed");
      qc.invalidateQueries({ queryKey: ["weekly-schedule"] });
      qc.invalidateQueries({ queryKey: ["owner-performance"] });
    },
    onError: () => toast.error("Failed to remove schedule"),
  });

  function toggleEmployee(employee: Employee) {
    const availability = availabilityFor(employee);
    if (availability !== "available") return;
    setSelectedEmployeeIds((current) =>
      current.includes(employee.id)
        ? current.filter((id) => id !== employee.id)
        : [...current, employee.id]
    );
  }

  function openEmployeeModal(shiftId: string) {
    setSelectedShiftId(shiftId);
    setSelectedEmployeeIds([]);
    setEditingAssignmentId(null);
    setIsRestDayWork(false);
    setEmployeeModalOpen(true);
  }

  return (
    <OwnerPage>
      <OwnerPageHeader
        //eyebrow="Scheduling"
        title={mode === "assign" ? "Assign Schedule" : "Schedule Viewer"}
        actions={
          <>
            <Button
              variant="outline"
              className="gap-2"
              onClick={() => {
                setMode("assign");
                setShowNewShift(true);
              }}
            >
              <Plus className="h-4 w-4" />
              New Shift
            </Button>
            <Button
              variant={mode === "assign" ? "default" : "outline"}
              className={mode === "assign" ? "bg-[#1E3A5F] hover:bg-[#284B73]" : ""}
              onClick={() => setMode("assign")}
            >
              Assign
            </Button>
            <Button
              variant={mode === "viewer" ? "default" : "outline"}
              className={mode === "viewer" ? "bg-[#1E3A5F] hover:bg-[#284B73]" : ""}
              onClick={() => setMode("viewer")}
            >
              View Schedule
            </Button>
          </>
        }
      />

      <OwnerPageContent>
        {mode === "assign" ? (
          <>
            <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
              <div className="grid gap-4 lg:grid-cols-[1fr_1fr_auto] lg:items-end">
                <div>
                  <label className="mb-2 block text-sm font-medium text-[#374151]">
                    Select Date
                  </label>
                  <Input
                    type="date"
                    value={workDate}
                    onChange={(event) => {
                      setWorkDate(event.target.value);
                      setWeekStart(getWeekStart(new Date(`${event.target.value}T00:00:00`)));
                    }}
                  />
                </div>
                <div>
                  <label className="mb-2 block text-sm font-medium text-[#374151]">
                    Select Shift
                  </label>
                  <select
                    className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
                    value={selectedShiftId}
                    onChange={(event) => setSelectedShiftId(event.target.value)}
                  >
                    <option value="">Choose a shift</option>
                    {shifts.map((shift) => (
                      <option key={shift.id} value={shift.id}>
                        {shift.name} ({formatShiftTime(shift.start_time)} -{" "}
                        {formatShiftTime(shift.end_time)})
                      </option>
                    ))}
                  </select>
                </div>
                <Button
                  variant="outline"
                  className="gap-2"
                  onClick={() => setShowNewShift(true)}
                >
                  <Plus className="h-4 w-4" />
                  New Shift
                </Button>
              </div>
              {selectedHoliday && (
                <div className="mt-4 rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
                  <span className="font-medium">Holiday Notice:</span>{" "}
                  {new Date(`${workDate}T00:00:00`).toLocaleDateString(
                    undefined,
                    { month: "long", day: "numeric" }
                  )}{" "}
                  is a holiday: {selectedHoliday.name}.
                </div>
              )}
            </section>

            {showNewShift && (
              <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
                <h2 className="mb-4 text-base font-semibold text-[#1F2937]">
                  Create Shift
                </h2>
                <div className="grid gap-4 md:grid-cols-4">
                  <Input
                    placeholder="Shift name"
                    value={newShift.name}
                    onChange={(event) =>
                      setNewShift({ ...newShift, name: event.target.value })
                    }
                  />
                  <Input
                    type="time"
                    value={newShift.start_time}
                    onChange={(event) =>
                      setNewShift({ ...newShift, start_time: event.target.value })
                    }
                  />
                  <Input
                    type="time"
                    value={newShift.end_time}
                    onChange={(event) =>
                      setNewShift({ ...newShift, end_time: event.target.value })
                    }
                  />
                  <Input
                    type="number"
                    min={1}
                    value={newShift.employee_capacity}
                    onChange={(event) =>
                      setNewShift({ ...newShift, employee_capacity: event.target.value })
                    }
                  />
                </div>
                <div className="mt-4 flex justify-end gap-2">
                  <Button variant="outline" onClick={() => setShowNewShift(false)}>
                    Cancel
                  </Button>
                  <Button
                    className="bg-[#1E3A5F] hover:bg-[#284B73]"
                    onClick={() => addShift.mutate()}
                    disabled={!newShift.name.trim() || addShift.isPending}
                  >
                    Save Shift
                  </Button>
                </div>
              </section>
            )}

            <section className="space-y-4">
              {shifts.map((shift) => {
                const shiftAssignments = assignmentsByShift.get(shift.id) ?? [];
                return (
                  <div
                    className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm"
                    key={shift.id}
                  >
                    <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
                      <div>
                        <h2 className="text-base font-semibold text-[#1F2937]">
                          {shift.name}
                        </h2>
                        <p className="text-sm text-[#6B7280]">
                          {formatShiftTime(shift.start_time)} -{" "}
                          {formatShiftTime(shift.end_time)} · Capacity{" "}
                          {shift.employee_capacity}
                        </p>
                      </div>
                      <Button
                        variant="outline"
                        className="gap-2"
                        onClick={() => openEmployeeModal(shift.id)}
                      >
                        <Users className="h-4 w-4" />
                        Add Employee
                      </Button>
                    </div>

                    <div className="mt-5 overflow-hidden rounded-xl border border-slate-100">
                      <table className="w-full text-sm">
                        <thead className="bg-[#F9FAFB] text-left text-[#6B7280]">
                          <tr>
                            <th className="px-4 py-3 font-medium">Employee</th>
                            <th className="px-4 py-3 font-medium">Position</th>
                            <th className="px-4 py-3 font-medium">Status</th>
                            <th className="px-4 py-3 text-right font-medium">Actions</th>
                          </tr>
                        </thead>
                        <tbody>
                          {shiftAssignments.length === 0 ? (
                            <tr>
                              <td className="px-4 py-6 text-[#6B7280]" colSpan={4}>
                                No employees assigned to this shift yet.
                              </td>
                            </tr>
                          ) : (
                            shiftAssignments.map((assignment) => {
                              const employee = employees.find(
                                (item) => item.id === assignment.employee_id
                              );
                              return (
                                <tr className="border-t border-slate-100" key={assignment.id}>
                                  <td className="px-4 py-3 font-medium text-[#1F2937]">
                                    {assignment.employee_name}
                                  </td>
                                  <td className="px-4 py-3 text-[#6B7280]">
                                    {employee?.position_title ?? "Unassigned"}
                                  </td>
                                  <td className="px-4 py-3">
                                    <div className="flex flex-wrap gap-2">
                                      <span className="rounded-full border border-blue-100 bg-blue-50 px-2.5 py-1 text-xs font-medium text-blue-700">
                                        Assigned
                                      </span>
                                      {assignment.is_rest_day_work && (
                                        <span className="rounded-full border border-sky-100 bg-sky-50 px-2.5 py-1 text-xs font-medium text-sky-800">
                                          Rest day
                                        </span>
                                      )}
                                    </div>
                                  </td>
                                  <td className="px-4 py-3">
                                    <div className="flex justify-end gap-2">
                                      <Button
                                        variant="outline"
                                        size="sm"
                                        onClick={() => {
                                          setEditingAssignmentId(assignment.id);
                                          setSelectedShiftId(shift.id);
                                          setIsRestDayWork(
                                            Boolean(assignment.is_rest_day_work)
                                          );
                                          setEmployeeModalOpen(false);
                                        }}
                                      >
                                        <Pencil className="h-4 w-4" />
                                      </Button>
                                      <Button
                                        variant="outline"
                                        size="sm"
                                        onClick={() => removeAssignment.mutate(assignment.id)}
                                      >
                                        <Trash2 className="h-4 w-4" />
                                      </Button>
                                    </div>
                                  </td>
                                </tr>
                              );
                            })
                          )}
                        </tbody>
                      </table>
                    </div>
                  </div>
                );
              })}
            </section>

            {editingAssignmentId && (
              <section className="rounded-2xl border border-amber-200 bg-amber-50 p-5 text-sm text-amber-800">
                Choose a new date or shift above, then save to reassign this schedule.
                <label className="mt-4 flex items-center gap-2 rounded-xl border border-amber-200 bg-white px-4 py-3 text-sm text-[#1F2937]">
                  <input
                    type="checkbox"
                    checked={isRestDayWork}
                    onChange={(event) => setIsRestDayWork(event.target.checked)}
                  />
                  Mark as approved rest day work (premium applies)
                </label>
                <div className="mt-4 flex gap-2">
                  <Button
                    className="bg-[#1E3A5F] hover:bg-[#284B73]"
                    disabled={!selectedShiftId || editAssignment.isPending}
                    onClick={() => editAssignment.mutate()}
                  >
                    Save Reassignment
                  </Button>
                  <Button
                    variant="outline"
                    onClick={() => {
                      setEditingAssignmentId(null);
                      setIsRestDayWork(false);
                    }}
                  >
                    Cancel
                  </Button>
                </div>
              </section>
            )}
          </>
        ) : (
          <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
            <div className="flex flex-col gap-4 xl:flex-row xl:items-center xl:justify-between">
              <div>
                <h2 className="text-lg font-semibold text-[#1F2937]">
                  Download Schedule
                </h2>
                <p className="text-sm text-[#6B7280]">{formatWeekRange(weekStart)}</p>
              </div>
              <div className="flex flex-wrap gap-2">
                <Button variant="outline" onClick={() => setWeekStart((current) => navigateWeek(current, "prev"))}>
                  Previous
                </Button>
                <Button variant="outline" onClick={() => setWeekStart((current) => navigateWeek(current, "next"))}>
                  Next
                </Button>
                <Button variant="outline" className="gap-2" onClick={() => downloadSchedulePdf({ businessName, weekStart, rows: scheduleRows })}>
                  <Download className="h-4 w-4" />
                  PDF
                </Button>
                <Button variant="outline" className="gap-2" onClick={() => downloadScheduleExcel({ businessName, weekStart, rows: scheduleRows })}>
                  <FileSpreadsheet className="h-4 w-4" />
                  Excel
                </Button>
                <Button variant="outline" className="gap-2" onClick={() => printSchedule({ businessName, weekStart, rows: scheduleRows })}>
                  <Printer className="h-4 w-4" />
                  Print
                </Button>
                <Button className="bg-[#1E3A5F] hover:bg-[#284B73]" onClick={() => setCustomizing(true)}>
                  Edit Table
                </Button>
              </div>
            </div>

            <div className="mt-5 grid gap-3 lg:grid-cols-[1fr_220px_180px]">
              <div className="relative">
                <Search className="absolute left-3 top-2.5 h-4 w-4 text-[#9CA3AF]" />
                <Input
                  className="pl-9"
                  placeholder="Search employee"
                  value={search}
                  onChange={(event) => setSearch(event.target.value)}
                />
              </div>
              <select
                className="flex h-10 rounded-md border border-input bg-background px-3 py-2 text-sm"
                value={positionFilter}
                onChange={(event) => setPositionFilter(event.target.value)}
              >
                <option value="all">All positions</option>
                {positions.map((position) => (
                  <option key={position} value={position}>
                    {position}
                  </option>
                ))}
              </select>
              <select className="flex h-10 rounded-md border border-input bg-background px-3 py-2 text-sm" disabled>
                <option>All departments</option>
              </select>
            </div>

            <div className="mt-5">
              {isLoading ? (
                <p className="py-8 text-center text-sm text-[#6B7280]">
                  Loading schedule...
                </p>
              ) : (
                <ColorScheduleTable
                  colors={tableColors}
                  defaultEnd={defaultEnd}
                  defaultStart={defaultStart}
                  rows={scheduleRows}
                  visibleDays={visibleDays}
                  weekStart={weekStart}
                />
              )}
            </div>
          </section>
        )}
      </OwnerPageContent>

      <Dialog open={customizing} onOpenChange={setCustomizing}>
        <DialogContent className="max-w-5xl">
          <DialogHeader>
            <DialogTitle>Customize Table</DialogTitle>
          </DialogHeader>
          <div className="grid gap-6 lg:grid-cols-[1fr_1fr_1fr]">
            <div className="space-y-5">
              <div>
                <h3 className="mb-2 text-sm font-semibold text-[#1F2937]">
                  Shift Times
                </h3>
                <div className="flex items-center gap-2">
                  <Input
                    type="time"
                    value={defaultStart}
                    onChange={(event) => setDefaultStart(event.target.value)}
                  />
                  <span className="text-[#6B7280]">-</span>
                  <Input
                    type="time"
                    value={defaultEnd}
                    onChange={(event) => setDefaultEnd(event.target.value)}
                  />
                </div>
              </div>

              <div>
                <h3 className="mb-3 text-sm font-semibold text-[#1F2937]">
                  Days of the Week
                </h3>
                <div className="grid grid-cols-2 gap-2 text-sm">
                  {WEEKDAY_LABELS.map((day) => (
                    <label className="flex items-center gap-2" key={day}>
                      <input
                        checked={visibleDays.includes(day)}
                        type="checkbox"
                        onChange={() =>
                          setVisibleDays((current) =>
                            current.includes(day)
                              ? current.filter((item) => item !== day)
                              : [...current, day]
                          )
                        }
                      />
                      {day}
                    </label>
                  ))}
                </div>
              </div>
            </div>

            <div>
              <h3 className="mb-1 text-sm font-semibold text-[#1F2937]">
                Color Settings
              </h3>
              <p className="mb-3 text-xs text-[#6B7280]">
                Set colors used by table rows.
              </p>
              <ColorInput label="Header Color" value={tableColors.header} onChange={(value) => setTableColors({ ...tableColors, header: value })} />
              <ColorInput label="Row Color 1" value={tableColors.row1} onChange={(value) => setTableColors({ ...tableColors, row1: value })} />
              <ColorInput label="Row Color 2" value={tableColors.row2} onChange={(value) => setTableColors({ ...tableColors, row2: value })} />
              <ColorInput label="Row Color 3" value={tableColors.row3} onChange={(value) => setTableColors({ ...tableColors, row3: value })} />
              <ColorInput label="Row Color 4" value={tableColors.row4} onChange={(value) => setTableColors({ ...tableColors, row4: value })} />
              <ColorInput label="Row Color 5" value={tableColors.row5} onChange={(value) => setTableColors({ ...tableColors, row5: value })} />
              <ColorInput label="Off" value={tableColors.off} onChange={(value) => setTableColors({ ...tableColors, off: value })} />
            </div>

            <div>
              <h3 className="mb-4 text-sm font-semibold text-[#1F2937]">
                Text Color
              </h3>
              <div className="flex flex-wrap gap-3">
                {["#111827", "#FFFFFF", "#1E3A5F", "#6B7280"].map((color) => (
                  <button
                    className="h-9 w-9 rounded-md border border-slate-300"
                    key={color}
                    onClick={() => setTableColors({ ...tableColors, text: color })}
                    style={{ backgroundColor: color }}
                    type="button"
                  />
                ))}
              </div>
            </div>
          </div>

          <div className="mt-4 rounded-2xl border border-slate-200 bg-[#FAFBFC] p-5">
            <ColorScheduleTable
              colors={tableColors}
              defaultEnd={defaultEnd}
              defaultStart={defaultStart}
              rows={scheduleRows.slice(0, 5)}
              visibleDays={visibleDays}
              weekStart={weekStart}
            />
          </div>

          <DialogFooter>
            <Button variant="outline" onClick={() => setTableColors(defaultTableColors)}>
              Reset
            </Button>
            <Button className="bg-[#1E3A5F] hover:bg-[#284B73]" onClick={() => setCustomizing(false)}>
              Apply Changes
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={employeeModalOpen} onOpenChange={setEmployeeModalOpen}>
        <DialogContent className="max-w-4xl">
          <DialogHeader>
            <DialogTitle>Select Employees</DialogTitle>
          </DialogHeader>
          <div className="grid gap-3 lg:grid-cols-[1fr_180px_160px_160px]">
            <div className="relative">
              <Search className="absolute left-3 top-2.5 h-4 w-4 text-[#9CA3AF]" />
              <Input
                className="pl-9"
                placeholder="Search by name or position"
                value={search}
                onChange={(event) => setSearch(event.target.value)}
              />
            </div>
            <select className="h-10 rounded-md border border-input bg-background px-3 text-sm" value={positionFilter} onChange={(event) => setPositionFilter(event.target.value)}>
              <option value="all">All positions</option>
              {positions.map((position) => (
                <option key={position} value={position}>
                  {position}
                </option>
              ))}
            </select>
            <select className="h-10 rounded-md border border-input bg-background px-3 text-sm" value={typeFilter} onChange={(event) => setTypeFilter(event.target.value)}>
              <option value="all">All types</option>
              <option value="full_time">Full-Time</option>
              <option value="part_time">Part-Time</option>
            </select>
            <select className="h-10 rounded-md border border-input bg-background px-3 text-sm" value={availabilityFilter} onChange={(event) => setAvailabilityFilter(event.target.value)}>
              <option value="all">All availability</option>
              <option value="available">Available</option>
              <option value="assigned">Already assigned</option>
              <option value="conflict">Conflicts</option>
            </select>
          </div>

          <div className="mt-4 max-h-[420px] overflow-auto rounded-xl border border-slate-100">
            <table className="w-full min-w-[720px] text-sm">
              <thead className="sticky top-0 bg-[#F9FAFB] text-left text-[#6B7280]">
                <tr>
                  <th className="px-4 py-3 font-medium">Employee</th>
                  <th className="px-4 py-3 font-medium">Position</th>
                  <th className="px-4 py-3 font-medium">Type</th>
                  <th className="px-4 py-3 font-medium">Availability</th>
                </tr>
              </thead>
              <tbody>
                {filteredEmployees.map((employee) => {
                  const availability = availabilityFor(employee);
                  const checked = selectedEmployeeIds.includes(employee.id);
                  return (
                    <tr
                      className={`border-t border-slate-100 ${availability === "available" ? "cursor-pointer hover:bg-[#FAFBFC]" : "opacity-70"}`}
                      key={employee.id}
                      onClick={() => toggleEmployee(employee)}
                    >
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-3">
                          <input
                            checked={checked}
                            disabled={availability !== "available"}
                            readOnly
                            type="checkbox"
                          />
                          <div className="flex h-9 w-9 items-center justify-center rounded-full bg-slate-100 text-xs font-semibold text-[#374151]">
                            {initials(employee.full_name)}
                          </div>
                          <span className="font-medium text-[#1F2937]">
                            {employee.full_name}
                          </span>
                        </div>
                      </td>
                      <td className="px-4 py-3 text-[#6B7280]">
                        {employee.position_title ?? "Unassigned"}
                      </td>
                      <td className="px-4 py-3 text-[#6B7280]">
                        {employee.employment_type === "full_time" ? "Full-Time" : "Part-Time"}
                      </td>
                      <td className="px-4 py-3">
                        <span className={`rounded-full border px-2.5 py-1 text-xs font-medium ${statusTone(availability)}`}>
                          {availability === "available"
                            ? "Available"
                            : availability === "assigned"
                              ? "Already assigned"
                              : "Conflict"}
                        </span>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>

          <DialogFooter className="flex-col items-stretch gap-3 sm:flex-col">
            <label className="flex items-center gap-2 rounded-xl border border-slate-200 bg-[#FAFBFC] px-4 py-3 text-sm text-[#1F2937]">
              <input
                type="checkbox"
                checked={isRestDayWork}
                onChange={(event) => setIsRestDayWork(event.target.checked)}
              />
              Mark as approved rest day work (premium applies)
            </label>
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => setEmployeeModalOpen(false)}>
                Cancel
              </Button>
              <Button
                className="bg-[#1E3A5F] hover:bg-[#284B73]"
                disabled={!selectedShiftId || selectedEmployeeIds.length === 0 || assign.isPending}
                onClick={() => assign.mutate()}
              >
                Save Schedule
              </Button>
            </div>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </OwnerPage>
  );
}

function ColorInput({
  label,
  value,
  onChange,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
}) {
  return (
    <label className="mb-2 flex items-center justify-between gap-4 text-sm text-[#374151]">
      <span>{label}</span>
      <input
        className="h-7 w-9 cursor-pointer rounded border border-slate-200 bg-transparent"
        type="color"
        value={value}
        onChange={(event) => onChange(event.target.value)}
      />
    </label>
  );
}

function ColorScheduleTable({
  rows,
  weekStart,
  colors,
  visibleDays,
  defaultStart,
  defaultEnd,
}: {
  rows: { employee: Employee; cells: ScheduleCell[] }[];
  weekStart: Date;
  colors: typeof defaultTableColors;
  visibleDays: string[];
  defaultStart: string;
  defaultEnd: string;
}) {
  const weekDays = getWeekDays(weekStart);
  const rowColors = [colors.row1, colors.row2, colors.row3, colors.row4, colors.row5];
  const visibleIndexes = WEEKDAY_LABELS.map((day, index) => ({ day, index })).filter(
    ({ day }) => visibleDays.includes(day)
  );

  function cellLabel(cells: ScheduleCell) {
    if (cells.length === 0) return "OFF";
    return cells
      .map(
        (cell) =>
          `${formatShiftTime(cell.shift_start_time)}-${formatShiftTime(cell.shift_end_time)}`
      )
      .join(", ");
  }

  return (
    <div className="overflow-x-auto rounded-xl bg-white p-4">
      <table className="mx-auto min-w-[720px] border-collapse text-[11px] shadow-sm">
        <thead>
          <tr style={{ backgroundColor: colors.header, color: "#FFFFFF" }}>
            <th className="border border-white/20 px-3 py-2 text-left font-medium">
              Employee
            </th>
            {visibleIndexes.map(({ day, index }) => (
              <th
                className="border border-white/20 px-3 py-2 text-center font-medium"
                key={day}
                title={toDateKey(weekDays[index])}
              >
                {day}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.length === 0 ? (
            <tr>
              <td
                className="px-4 py-8 text-center text-[#6B7280]"
                colSpan={visibleIndexes.length + 1}
              >
                No schedule records found.
              </td>
            </tr>
          ) : (
            rows.map(({ employee, cells }, rowIndex) => (
              <tr
                key={employee.id}
                style={{
                  backgroundColor: rowColors[rowIndex % rowColors.length],
                  color: colors.text,
                }}
              >
                <td className="border border-white/40 px-3 py-2 font-medium">
                  {employee.full_name}
                </td>
                {visibleIndexes.map(({ index }) => {
                  const label = cellLabel(cells[index]);
                  const isOff = label === "OFF";
                  return (
                    <td
                      className="border border-white/40 px-3 py-2 text-center"
                      key={`${employee.id}-${index}`}
                      style={isOff ? { backgroundColor: colors.off } : undefined}
                    >
                      {isOff
                        ? "OFF"
                        : label || `${formatShiftTime(defaultStart)}-${formatShiftTime(defaultEnd)}`}
                    </td>
                  );
                })}
              </tr>
            ))
          )}
        </tbody>
      </table>
    </div>
  );
}
