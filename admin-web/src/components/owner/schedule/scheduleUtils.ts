import {
  addDays,
  format,
  parseISO,
  startOfWeek,
  subWeeks,
  addWeeks,
} from "date-fns";
import type { Employee, ScheduleAssignment } from "@/lib/api";

export const WEEKDAY_LABELS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

export function getWeekStart(date: Date): Date {
  return startOfWeek(date, { weekStartsOn: 1 });
}

export function formatWeekRange(weekStart: Date): string {
  const weekEnd = addDays(weekStart, 6);
  return `${format(weekStart, "MMM d")} – ${format(weekEnd, "MMM d, yyyy")}`;
}

export function toDateKey(date: Date): string {
  return format(date, "yyyy-MM-dd");
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
    const employeeMap =
      byEmployeeDate.get(assignment.employee_id) ??
      new Map<string, ScheduleAssignment[]>();
    const dayAssignments = employeeMap.get(assignment.work_date) ?? [];
    dayAssignments.push(assignment);
    employeeMap.set(assignment.work_date, dayAssignments);
    byEmployeeDate.set(assignment.employee_id, employeeMap);
  }

  return employees.map((employee) => ({
    employee,
    cells: dateKeys.map(
      (dateKey) => byEmployeeDate.get(employee.id)?.get(dateKey) ?? []
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
      assignment.shift_id === shiftId && assignment.work_date === workDate
  ).length;
}

export function navigateWeek(weekStart: Date, direction: "prev" | "next"): Date {
  return direction === "prev" ? subWeeks(weekStart, 1) : addWeeks(weekStart, 1);
}

export function parseWeekStart(value: string): Date {
  return parseISO(value);
}
