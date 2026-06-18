import type { ScheduleCell } from "@/components/owner/schedule/scheduleUtils";
import {
  WEEKDAY_LABELS,
  formatShiftTime,
  getWeekDays,
  textColorForBackground,
  toDateKey,
} from "@/components/owner/schedule/scheduleUtils";
import type { Employee } from "@/lib/api";

type Props = {
  weekStart: Date;
  rows: {
    employee: Employee;
    cells: ScheduleCell[];
  }[];
};

function ScheduleCellView({ cells }: { cells: ScheduleCell }) {
  if (cells.length === 0) {
    return <span className="text-xs text-muted-foreground">OFF</span>;
  }

  return (
    <div className="space-y-1">
      {cells.map((cell) => {
        const backgroundColor = cell.shift_color ?? undefined;

        return (
          <div
            key={cell.id}
            className="rounded-md px-2 py-1.5 text-xs"
            style={
              backgroundColor
                ? {
                    backgroundColor,
                    color: textColorForBackground(backgroundColor),
                  }
                : undefined
            }
          >
            <p className="font-medium">{cell.shift_name}</p>
            <p>
              {formatShiftTime(cell.shift_start_time)} –{" "}
              {formatShiftTime(cell.shift_end_time)}
            </p>
          </div>
        );
      })}
    </div>
  );
}

export function WeeklyScheduleTable({ weekStart, rows }: Props) {
  const weekDays = getWeekDays(weekStart);

  return (
    <div id="owner-weekly-schedule" className="overflow-x-auto">
      <table className="w-full min-w-[960px] border-collapse text-sm">
        <thead>
          <tr className="border-b bg-[#1e3a5f] text-left text-white">
            <th className="px-4 py-3 font-medium">Employee</th>
            {WEEKDAY_LABELS.map((label, index) => (
              <th key={label} className="px-3 py-3 font-medium">
                <div>{label}</div>
                <div className="text-xs font-normal opacity-80">
                  {toDateKey(weekDays[index])}
                </div>
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.length === 0 && (
            <tr>
              <td
                colSpan={8}
                className="px-4 py-8 text-center text-muted-foreground"
              >
                No employees found. Add employees before building a schedule.
              </td>
            </tr>
          )}
          {rows.map(({ employee, cells }) => (
            <tr key={employee.id} className="border-b align-top">
              <td className="px-4 py-3 font-medium">{employee.full_name}</td>
              {cells.map((cell, index) => (
                <td key={`${employee.id}-${index}`} className="px-3 py-3">
                  <ScheduleCellView cells={cell} />
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
