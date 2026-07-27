import jsPDF from "jspdf";
import autoTable from "jspdf-autotable";
import { format } from "date-fns";
import type { Employee, ScheduleColors } from "@/lib/api";
import {
  WEEKDAY_LABELS,
  formatShiftTime,
  formatWeekRange,
  getWeekDays,
  toDateKey,
  type ScheduleCell,
} from "@/components/owner/schedule/scheduleUtils";
import {
  defaultScheduleColors,
  defaultScheduleDisplay,
} from "@/components/owner/schedule/scheduleThemeDefaults";

type ExportRow = {
  employee: Employee;
  cells: ScheduleCell[];
};

export type ScheduleExportTheme = {
  colors: ScheduleColors;
  visibleDays: string[];
  defaultStart: string;
  defaultEnd: string;
};

function resolveTheme(theme?: Partial<ScheduleExportTheme>): ScheduleExportTheme {
  return {
    colors: theme?.colors ?? defaultScheduleColors,
    visibleDays: theme?.visibleDays ?? defaultScheduleDisplay.visible_days,
    defaultStart: theme?.defaultStart ?? defaultScheduleDisplay.default_start,
    defaultEnd: theme?.defaultEnd ?? defaultScheduleDisplay.default_end,
  };
}

function hexToRgb(hex: string): [number, number, number] {
  const normalized = hex.replace("#", "").trim();
  const expanded =
    normalized.length === 3
      ? normalized
          .split("")
          .map((char) => char + char)
          .join("")
      : normalized;
  const value = Number.parseInt(expanded, 16);
  return [(value >> 16) & 255, (value >> 8) & 255, value & 255];
}

function visibleDayIndexes(visibleDays: string[]) {
  return WEEKDAY_LABELS.map((day, index) => ({ day, index })).filter(({ day }) =>
    visibleDays.includes(day)
  );
}

function cellLabel(
  cells: ScheduleCell[],
  defaultStart: string,
  defaultEnd: string
): string {
  if (cells.length === 0) {
    return "OFF";
  }
  const label = cells
    .map(
      (cell) =>
        `${formatShiftTime(cell.shift_start_time)}-${formatShiftTime(cell.shift_end_time)}`
    )
    .join(", ");
  return label || `${formatShiftTime(defaultStart)}-${formatShiftTime(defaultEnd)}`;
}

function buildVisibleTableBody(
  rows: ExportRow[],
  weekStart: Date,
  theme: ScheduleExportTheme
): string[][] {
  const weekDays = getWeekDays(weekStart);
  const indexes = visibleDayIndexes(theme.visibleDays);
  return rows.map(({ employee, cells }) => [
    employee.full_name,
    ...indexes.map(({ index }) => cellLabel(cells[index], theme.defaultStart, theme.defaultEnd)),
  ]);
}

export function downloadSchedulePdf(options: {
  businessName: string;
  weekStart: Date;
  rows: ExportRow[];
  theme?: Partial<ScheduleExportTheme>;
}) {
  const theme = resolveTheme(options.theme);
  const doc = new jsPDF({ orientation: "landscape" });
  const generatedAt = new Date();
  const indexes = visibleDayIndexes(theme.visibleDays);
  const rowColors = [
    theme.colors.row1,
    theme.colors.row2,
    theme.colors.row3,
    theme.colors.row4,
    theme.colors.row5,
  ];
  const weekDays = getWeekDays(options.weekStart);

  doc.setFontSize(16);
  doc.text(options.businessName, 14, 16);
  doc.setFontSize(11);
  doc.text(`Weekly Schedule: ${formatWeekRange(options.weekStart)}`, 14, 24);
  doc.text(`Generated: ${generatedAt.toLocaleString()}`, 14, 31);

  autoTable(doc, {
    startY: 38,
    head: [["Employee", ...indexes.map(({ day }) => day)]],
    body: buildVisibleTableBody(options.rows, options.weekStart, theme),
    styles: {
      fontSize: 8,
      cellPadding: 2,
      textColor: hexToRgb(theme.colors.text),
    },
    headStyles: {
      fillColor: hexToRgb(theme.colors.header),
      textColor: [255, 255, 255],
    },
    didParseCell: (data) => {
      if (data.section !== "body") return;
      const rowIndex = data.row.index;
      const colIndex = data.column.index;
      data.cell.styles.fillColor = hexToRgb(rowColors[rowIndex % rowColors.length]);
      data.cell.styles.textColor = hexToRgb(theme.colors.text);
      if (colIndex > 0) {
        const dayIndex = indexes[colIndex - 1]?.index;
        if (dayIndex !== undefined) {
          const row = options.rows[rowIndex];
          const cells = row?.cells[dayIndex] ?? [];
          if (cells.length === 0) {
            data.cell.styles.fillColor = hexToRgb(theme.colors.off);
          }
        }
      }
    },
    columnStyles: Object.fromEntries(
      indexes.map((_, columnIndex) => [
        columnIndex + 1,
        { halign: "center" as const },
      ])
    ),
  });

  doc.save(
    `${options.businessName.replace(/\s+/g, "-").toLowerCase()}-schedule-${toDateKey(options.weekStart)}.pdf`
  );
}

export function downloadScheduleExcel(options: {
  businessName: string;
  weekStart: Date;
  rows: ExportRow[];
  theme?: Partial<ScheduleExportTheme>;
}) {
  const theme = resolveTheme(options.theme);
  const weekDays = getWeekDays(options.weekStart);
  const indexes = visibleDayIndexes(theme.visibleDays);
  const headers = ["Employee", ...indexes.map(({ day }) => day)];
  const lines = [
    [`Business: ${options.businessName}`],
    [`Week: ${formatWeekRange(options.weekStart)}`],
    [`Generated: ${new Date().toLocaleString()}`],
    [],
    headers,
    ...options.rows.map(({ employee, cells }) => [
      employee.full_name,
      ...indexes.map(({ index }) =>
        cellLabel(cells[index], theme.defaultStart, theme.defaultEnd).replace("\n", " ")
      ),
    ]),
    [],
    ...indexes.map(({ day, index }) => [day, format(weekDays[index], "yyyy-MM-dd")]),
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
  theme?: Partial<ScheduleExportTheme>;
}) {
  const theme = resolveTheme(options.theme);
  const weekDays = getWeekDays(options.weekStart);
  const indexes = visibleDayIndexes(theme.visibleDays);
  const rowColors = [
    theme.colors.row1,
    theme.colors.row2,
    theme.colors.row3,
    theme.colors.row4,
    theme.colors.row5,
  ];

  const tableRows = options.rows
    .map(({ employee, cells }, rowIndex) => {
      const rowBackground = rowColors[rowIndex % rowColors.length];
      const cellsHtml = indexes
        .map(({ index }) => {
          const dayCells = cells[index];
          const label = cellLabel(dayCells, theme.defaultStart, theme.defaultEnd);
          const isOff = label === "OFF";
          const background = isOff ? theme.colors.off : rowBackground;
          return `<td style="padding:8px;font-size:12px;vertical-align:top;text-align:center;background:${background};color:${theme.colors.text};border:1px solid rgba(255,255,255,0.35);">${label}</td>`;
        })
        .join("");
      return `<tr><td style="padding:8px;font-weight:600;background:${rowBackground};color:${theme.colors.text};border:1px solid rgba(255,255,255,0.35);"><strong>${employee.full_name}</strong></td>${cellsHtml}</tr>`;
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
          th { border: 1px solid rgba(255,255,255,0.25); text-align: center; vertical-align: top; padding: 10px; background: ${theme.colors.header}; color: #ffffff; }
          td { text-align: left; vertical-align: top; }
        </style>
      </head>
      <body>
        <h1>${options.businessName}</h1>
        <p>Weekly Schedule: ${formatWeekRange(options.weekStart)}</p>
        <p>Generated: ${new Date().toLocaleString()}</p>
        <table>
          <thead>
            <tr>
              <th style="text-align:left;">Employee</th>
              ${indexes
                .map(
                  ({ day, index }) =>
                    `<th>${day}<br/><span style="font-weight:normal;font-size:11px;">${format(weekDays[index], "yyyy-MM-dd")}</span></th>`
                )
                .join("")}
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

export async function downloadScheduleImage(options: {
  businessName: string;
  weekStart: Date;
  rows: ExportRow[];
  theme?: Partial<ScheduleExportTheme>;
}) {
  const theme = resolveTheme(options.theme);
  const weekDays = getWeekDays(options.weekStart);
  const indexes = visibleDayIndexes(theme.visibleDays);
  const rowColors = [
    theme.colors.row1,
    theme.colors.row2,
    theme.colors.row3,
    theme.colors.row4,
    theme.colors.row5,
  ];

  const container = document.createElement("div");
  container.style.position = "fixed";
  container.style.left = "-10000px";
  container.style.top = "0";
  container.style.background = "#ffffff";
  container.style.padding = "24px";
  container.innerHTML = `
    <h1 style="margin:0 0 8px;font-family:Arial,sans-serif;font-size:24px;">${options.businessName}</h1>
    <p style="margin:0 0 16px;font-family:Arial,sans-serif;color:#475569;">Weekly Schedule: ${formatWeekRange(options.weekStart)}</p>
    <table style="border-collapse:collapse;font-family:Arial,sans-serif;font-size:12px;">
      <thead>
        <tr>
          <th style="padding:10px;background:${theme.colors.header};color:#fff;border:1px solid rgba(255,255,255,0.25);text-align:left;">Employee</th>
          ${indexes
            .map(
              ({ day, index }) =>
                `<th style="padding:10px;background:${theme.colors.header};color:#fff;border:1px solid rgba(255,255,255,0.25);text-align:center;">${day}<br/><span style="font-weight:normal;font-size:11px;">${format(weekDays[index], "yyyy-MM-dd")}</span></th>`
            )
            .join("")}
        </tr>
      </thead>
      <tbody>
        ${options.rows
          .map(({ employee, cells }, rowIndex) => {
            const rowBackground = rowColors[rowIndex % rowColors.length];
            return `<tr>
              <td style="padding:8px;background:${rowBackground};color:${theme.colors.text};border:1px solid rgba(255,255,255,0.35);font-weight:600;">${employee.full_name}</td>
              ${indexes
                .map(({ index }) => {
                  const label = cellLabel(cells[index], theme.defaultStart, theme.defaultEnd);
                  const isOff = label === "OFF";
                  const background = isOff ? theme.colors.off : rowBackground;
                  return `<td style="padding:8px;background:${background};color:${theme.colors.text};border:1px solid rgba(255,255,255,0.35);text-align:center;">${label}</td>`;
                })
                .join("")}
            </tr>`;
          })
          .join("")}
      </tbody>
    </table>
  `;
  document.body.appendChild(container);

  const { default: html2canvas } = await import("html2canvas");
  const canvas = await html2canvas(container, { backgroundColor: "#ffffff", scale: 2 });
  document.body.removeChild(container);

  const link = document.createElement("a");
  link.href = canvas.toDataURL("image/png");
  link.download = `${options.businessName.replace(/\s+/g, "-").toLowerCase()}-schedule-${toDateKey(options.weekStart)}.png`;
  link.click();
}
