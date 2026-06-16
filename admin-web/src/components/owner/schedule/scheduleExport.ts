import jsPDF from "jspdf";
import autoTable from "jspdf-autotable";
import { format } from "date-fns";
import type { Employee, ScheduleAssignment } from "@/lib/api";
import {
  WEEKDAY_LABELS,
  formatShiftTime,
  formatWeekRange,
  getWeekDays,
  textColorForBackground,
  toDateKey,
  type ScheduleCell,
} from "@/components/owner/schedule/scheduleUtils";

type ExportRow = {
  employee: Employee;
  cells: ScheduleCell[];
};

function cellLabel(cell: ScheduleCell): string {
  if (!cell) {
    return "OFF";
  }
  return `${cell.shift_name}\n${formatShiftTime(cell.shift_start_time)} – ${formatShiftTime(cell.shift_end_time)}`;
}

function buildTableBody(rows: ExportRow[], weekStart: Date): string[][] {
  const weekDays = getWeekDays(weekStart);
  return rows.map(({ employee, cells }) => [
    employee.full_name,
    ...cells.map((cell, index) => {
      const dateKey = toDateKey(weekDays[index]);
      if (!cell) {
        return "OFF";
      }
      return `${cell.shift_name} (${formatShiftTime(cell.shift_start_time)} – ${formatShiftTime(cell.shift_end_time)}) [${dateKey}]`;
    }),
  ]);
}

export function downloadSchedulePdf(options: {
  businessName: string;
  weekStart: Date;
  rows: ExportRow[];
}) {
  const doc = new jsPDF({ orientation: "landscape" });
  const generatedAt = new Date();

  doc.setFontSize(16);
  doc.text(options.businessName, 14, 16);
  doc.setFontSize(11);
  doc.text(`Weekly Schedule: ${formatWeekRange(options.weekStart)}`, 14, 24);
  doc.text(`Generated: ${generatedAt.toLocaleString()}`, 14, 31);

  autoTable(doc, {
    startY: 38,
    head: [["Employee", ...WEEKDAY_LABELS]],
    body: buildTableBody(options.rows, options.weekStart).map((row) =>
      row.map((value) => value.replace(/\s*\[\d{4}-\d{2}-\d{2}\]/, ""))
    ),
    styles: { fontSize: 8, cellPadding: 2 },
    headStyles: { fillColor: [30, 58, 95] },
  });

  doc.save(
    `${options.businessName.replace(/\s+/g, "-").toLowerCase()}-schedule-${toDateKey(options.weekStart)}.pdf`
  );
}

export function downloadScheduleExcel(options: {
  businessName: string;
  weekStart: Date;
  rows: ExportRow[];
}) {
  const weekDays = getWeekDays(options.weekStart);
  const headers = ["Employee", ...WEEKDAY_LABELS];
  const lines = [
    [`Business: ${options.businessName}`],
    [`Week: ${formatWeekRange(options.weekStart)}`],
    [`Generated: ${new Date().toLocaleString()}`],
    [],
    headers,
    ...options.rows.map(({ employee, cells }) => [
      employee.full_name,
      ...cells.map((cell) => cellLabel(cell).replace("\n", " ")),
    ]),
    [],
    ...weekDays.map((day, index) => [
      WEEKDAY_LABELS[index],
      format(day, "yyyy-MM-dd"),
    ]),
  ];

  const csv = lines
    .map((row) =>
      row
        .map((value) => `"${String(value).replace(/"/g, '""')}"`)
        .join(",")
    )
    .join("\r\n");

  const blob = new Blob(["\uFEFF" + csv], {
    type: "text/csv;charset=utf-8;",
  });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = `${options.businessName.replace(/\s+/g, "-").toLowerCase()}-schedule-${toDateKey(options.weekStart)}.csv`;
  link.click();
  URL.revokeObjectURL(url);
}

export function printSchedule(options: {
  businessName: string;
  weekStart: Date;
  rows: ExportRow[];
}) {
  const weekDays = getWeekDays(options.weekStart);
  const tableRows = options.rows
    .map(({ employee, cells }) => {
      const cellsHtml = cells
        .map((cell) => {
          if (!cell) {
            return "<td>OFF</td>";
          }
          const bg = cell.shift_color ?? "#f1f5f9";
          const color = cell.shift_color
            ? textColorForBackground(cell.shift_color)
            : "#334155";
          return `<td style="background:${bg};color:${color};padding:8px;font-size:12px;"><strong>${cell.shift_name}</strong><br/>${formatShiftTime(cell.shift_start_time)} – ${formatShiftTime(cell.shift_end_time)}</td>`;
        })
        .join("");
      return `<tr><td><strong>${employee.full_name}</strong></td>${cellsHtml}</tr>`;
    })
    .join("");

  const printWindow = window.open("", "_blank", "noopener,noreferrer,width=1200,height=800");
  if (!printWindow) {
    return;
  }

  printWindow.document.write(`
    <!DOCTYPE html>
    <html>
      <head>
        <title>${options.businessName} Schedule</title>
        <style>
          body { font-family: Arial, sans-serif; padding: 24px; color: #0f172a; }
          h1 { margin: 0 0 8px; font-size: 24px; }
          p { margin: 0 0 16px; color: #475569; }
          table { width: 100%; border-collapse: collapse; }
          th, td { border: 1px solid #cbd5e1; text-align: left; vertical-align: top; }
          th { background: #1e3a5f; color: white; padding: 10px; }
        </style>
      </head>
      <body>
        <h1>${options.businessName}</h1>
        <p>Weekly Schedule: ${formatWeekRange(options.weekStart)}</p>
        <p>Generated: ${new Date().toLocaleString()}</p>
        <table>
          <thead>
            <tr>
              <th>Employee</th>
              ${WEEKDAY_LABELS.map((label, index) => `<th>${label}<br/><span style="font-weight:normal;font-size:11px;">${format(weekDays[index], "yyyy-MM-dd")}</span></th>`).join("")}
            </tr>
          </thead>
          <tbody>${tableRows}</tbody>
        </table>
      </body>
    </html>
  `);
  printWindow.document.close();
  printWindow.focus();
  printWindow.print();
}
