import {
  addDays,
  format,
  parseISO,
  startOfWeek,
  subWeeks,
  addWeeks,
} from "date-fns";
import type { Employee, ScheduleAssignment } from "@/lib/api";

export function isEmployeeFullyActivated(
  employee: Pick<Employee, "must_change_password" | "face_registration_status">
) {
  return (
    employee.must_change_password !== true &&
    employee.face_registration_status === "completed"
  );
}

export const WEEKDAY_LABELS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

export function getWeekStart(date: Date): Date {
  return startOfWeek(date, { weekStartsOn: 1 });
}

export function formatWeekRange(weekStart: Date): string {
  const weekEnd = addDays(weekStart, 6);
  return `${format(weekStart, "MMM d")} – ${format(weekEnd, "MMM d, yyyy")}`;
}

export function toDateKey(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

const CALENDAR_DATE = /^(\d{4}-\d{2}-\d{2})/;

export function assignmentDateKey(value: string | Date | null | undefined): string {
  if (value == null || value === "") return "";
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? "" : toDateKey(value);
  }
  const raw = String(value).trim();
  const match = raw.match(CALENDAR_DATE);
  if (match) return match[1];
  const parsed = new Date(raw);
  return Number.isNaN(parsed.getTime()) ? raw : toDateKey(parsed);
}

export function scheduleRangeError(startDate: string, endDate: string): string | null {
  if (!startDate || !endDate) return "Choose a start date and an end date.";
  if (endDate < startDate) {
    return "End date must be the same as or later than the start date.";
  }
  return null;
}

/** Library start/end dates are independent of the calendar's selected date. */
export function templateApplyRange(startDate: string, endDate: string) {
  return { start_date: startDate, end_date: endDate };
}

export function restDayPremiumInitialValue() {
  return false;
}

export function assignmentsOnDate(
  assignments: ScheduleAssignment[],
  dateKey: string
): ScheduleAssignment[] {
  return assignments.filter(
    (assignment) => assignmentDateKey(assignment.work_date) === dateKey
  );
}

function employeeFromAssignment(assignment: ScheduleAssignment): Employee {
  return {
    id: String(assignment.employee_id),
    email: "",
    username: "",
    generated_username: null,
    full_name: assignment.employee_name,
    position_title: null,
    phone: null,
    employment_type: "",
    pay_basis: "daily",
    daily_rate: null,
    hourly_rate: null,
    monthly_salary: null,
    status: "active",
    must_change_password: false,
    temporary_password: null,
    profile_image_url: null,
  };
}

/** Keep listed employees and append anyone who has a weekly assignment. */
export function employeesWithScheduleAssignments(
  employees: Employee[],
  assignments: ScheduleAssignment[]
): Employee[] {
  const listedIds = new Set(employees.map((employee) => String(employee.id)));
  const extras: Employee[] = [];
  for (const assignment of assignments) {
    const id = String(assignment.employee_id);
    if (listedIds.has(id)) continue;
    listedIds.add(id);
    extras.push(employeeFromAssignment(assignment));
  }
  return extras.length === 0 ? employees : [...employees, ...extras];
}

export function getWeekDays(weekStart: Date): Date[] {
  return WEEKDAY_LABELS.map((_, index) => addDays(weekStart, index));
}

export function formatShiftTime(value: string): string {
  const parts = value.split(":");
  const hour = Number(parts[0]);
  const minute = parts[1] ?? "00";
  const period = hour >= 12 ? "PM" : "AM";
  const hour12 = hour % 12 || 12;
  return `${hour12}:${minute} ${period}`;
}

export function textColorForBackground(hex: string): string {
  const normalized = hex.replace("#", "");
  if (normalized.length !== 6) {
    return "#1e293b";
  }
  const r = parseInt(normalized.slice(0, 2), 16);
  const g = parseInt(normalized.slice(2, 4), 16);
  const b = parseInt(normalized.slice(4, 6), 16);
  const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  return luminance > 0.6 ? "#1e293b" : "#ffffff";
}

export type ScheduleCell = ScheduleAssignment[];

export function buildScheduleMatrix(
  employees: Employee[],
  assignments: ScheduleAssignment[],
  weekStart: Date
): {
  employee: Employee;
  cells: ScheduleCell[];
}[] {
  const weekDays = getWeekDays(weekStart);
  const dateKeys = weekDays.map(toDateKey);

  const byEmployeeDate = new Map<string, Map<string, ScheduleAssignment[]>>();
  for (const assignment of assignments) {
    const workDateKey = assignmentDateKey(assignment.work_date);
    const employeeId = String(assignment.employee_id);
    const employeeMap =
      byEmployeeDate.get(employeeId) ??
      new Map<string, ScheduleAssignment[]>();
    const dayAssignments = employeeMap.get(workDateKey) ?? [];
    dayAssignments.push(assignment);
    employeeMap.set(workDateKey, dayAssignments);
    byEmployeeDate.set(employeeId, employeeMap);
  }

  return employees.map((employee) => ({
    employee,
    cells: dateKeys.map(
      (dateKey) => byEmployeeDate.get(String(employee.id))?.get(dateKey) ?? []
    ),
  }));
}

export function countShiftAssignmentsOnDate(
  assignments: ScheduleAssignment[],
  shiftId: string,
  workDate: string
): number {
  return assignments.filter(
    (assignment) =>
      assignment.shift_id === shiftId &&
      assignmentDateKey(assignment.work_date) === workDate
  ).length;
}

export function navigateWeek(weekStart: Date, direction: "prev" | "next"): Date {
  return direction === "prev" ? subWeeks(weekStart, 1) : addWeeks(weekStart, 1);
}

export function parseWeekStart(value: string): Date {
  return parseISO(value);
}
