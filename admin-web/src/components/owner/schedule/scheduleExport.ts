import jsPDF from "jspdf";
import autoTable from "jspdf-autotable";
import { format } from "date-fns";
import type { Employee } from "@/lib/api";
import {
  WEEKDAY_LABELS,
  formatShiftTime,
  formatWeekRange,
  getWeekDays,
  textColorForBackground,
  toDateKey,
  type ScheduleCell,
} from "@/components/owner/schedule/scheduleUtils";

export type ScheduleTableColors = {
  header: string;
  row1: string;
  row2: string;
  row3: string;
  row4: string;
  row5: string;
  off: string;
  text: string;
};

export const DEFAULT_SCHEDULE_TABLE_COLORS: ScheduleTableColors = {
  header: "#1E3A5F",
  row1: "#FFE5A3",
  row2: "#FFB166",
  row3: "#B8F28C",
  row4: "#B9D8F7",
  row5: "#F2A7EA",
  off: "#F8B4B4",
  text: "#111827",
};

type ExportRow = {
  employee: Employee;
  cells: ScheduleCell[];
};

type ExportOptions = {
  businessName: string;
  weekStart: Date;
  rows: ExportRow[];
  colors?: ScheduleTableColors;
  visibleDays?: string[];
  defaultStart?: string;
  defaultEnd?: string;
};

function hexToRgb(hex: string): [number, number, number] {
  const normalized = hex.replace("#", "").trim();
  if (normalized.length !== 6) {
    return [30, 58, 95];
  }
  return [
    parseInt(normalized.slice(0, 2), 16),
    parseInt(normalized.slice(2, 4), 16),
    parseInt(normalized.slice(4, 6), 16),
  ];
}

function visibleDayIndexes(visibleDays: string[]) {
  return WEEKDAY_LABELS.map((day, index) => ({ day, index })).filter(({ day }) =>
    visibleDays.includes(day)
  );
}

function dayCellLabel(
  dayCells: ScheduleCell,
  defaultStart: string,
  defaultEnd: string
): string {
  if (dayCells.length === 0) return "OFF";
  const label = dayCells
    .map((cell) => {
      if (cell.on_leave && !cell.assigned_during_leave) {
        return "On Leave";
      }
      const times = `${formatShiftTime(cell.shift_start_time)}-${formatShiftTime(cell.shift_end_time)}`;
      if (cell.assigned_during_leave) {
        return `${times} · Assigned During Leave`;
      }
      return times;
    })
    .join(", ");
  return (
    label ||
    `${formatShiftTime(defaultStart)}-${formatShiftTime(defaultEnd)}`
  );
}

function resolveOptions(options: ExportOptions) {
  const colors = options.colors ?? DEFAULT_SCHEDULE_TABLE_COLORS;
  const visibleDays = options.visibleDays?.length
    ? options.visibleDays
    : WEEKDAY_LABELS;
  const defaultStart = options.defaultStart ?? "09:00";
  const defaultEnd = options.defaultEnd ?? "17:00";
  const weekDays = getWeekDays(options.weekStart);
  const visibleIndexes = visibleDayIndexes(visibleDays);
  const rowColors = [
    colors.row1,
    colors.row2,
    colors.row3,
    colors.row4,
    colors.row5,
  ];

  const headers = [
    "Employee",
    ...visibleIndexes.map(({ day, index }) => {
      const dateLabel = format(weekDays[index], "MMM d");
      return `${day}\n${dateLabel}`;
    }),
  ];

  const body = options.rows.map(({ employee, cells }) => [
    employee.full_name,
    ...visibleIndexes.map(({ index }) =>
      dayCellLabel(cells[index] ?? [], defaultStart, defaultEnd)
    ),
  ]);

  return {
    colors,
    weekDays,
    visibleIndexes,
    rowColors,
    headers,
    body,
    defaultStart,
    defaultEnd,
  };
}

export function downloadSchedulePdf(options: ExportOptions) {
  const doc = new jsPDF({ orientation: "landscape" });
  const generatedAt = new Date();
  const { colors, headers, body, rowColors } = resolveOptions(options);
  const headerRgb = hexToRgb(colors.header);
  const textRgb = hexToRgb(colors.text);
  const offRgb = hexToRgb(colors.off);

  doc.setFontSize(16);
  doc.text(options.businessName, 14, 16);
  doc.setFontSize(11);
  doc.text(`Weekly Schedule: ${formatWeekRange(options.weekStart)}`, 14, 24);
  doc.text(`Generated: ${generatedAt.toLocaleString()}`, 14, 31);

  autoTable(doc, {
    startY: 38,
    head: [headers.map((header) => header.replace("\n", " · "))],
    body,
    styles: {
      fontSize: 8,
      cellPadding: 2.5,
      valign: "middle",
      halign: "center",
      textColor: textRgb,
      lineColor: [255, 255, 255],
      lineWidth: 0.2,
    },
    columnStyles: {
      0: { halign: "left", cellWidth: 36 },
    },
    headStyles: {
      fillColor: headerRgb,
      textColor: [255, 255, 255],
      fontStyle: "bold",
      halign: "center",
    },
    didParseCell: (data) => {
      if (data.section !== "body") return;
      const rowColor = rowColors[data.row.index % rowColors.length];
      data.cell.styles.fillColor = hexToRgb(rowColor);
      data.cell.styles.textColor = textRgb;
      if (data.column.index > 0 && String(data.cell.raw).trim() === "OFF") {
        data.cell.styles.fillColor = offRgb;
      }
      if (
        data.column.index > 0 &&
        String(data.cell.raw).toLowerCase().includes("on leave")
      ) {
        data.cell.styles.fillColor = [254, 202, 202];
      }
    },
  });

  doc.save(
    `${options.businessName.replace(/\s+/g, "-").toLowerCase()}-schedule-${toDateKey(options.weekStart)}.pdf`
  );
}

/** Colored .xls (HTML) so Excel retains the customized table colors. */
export function downloadScheduleExcel(options: ExportOptions) {
  const {
    colors,
    headers,
    body,
    rowColors,
    weekDays,
    visibleIndexes,
  } = resolveOptions(options);

  const headHtml = headers
    .map(
      (header) =>
        `<th style="background:${colors.header};color:#FFFFFF;border:1px solid #ffffff;padding:8px;text-align:center;">${header.replace("\n", "<br/>")}</th>`
    )
    .join("");

  const bodyHtml = body
    .map((row, rowIndex) => {
      const rowBg = rowColors[rowIndex % rowColors.length];
      const cells = row
        .map((value, colIndex) => {
          const isOff = colIndex > 0 && value.trim() === "OFF";
          const onLeave =
            colIndex > 0 && value.toLowerCase().includes("on leave");
          const bg = isOff
            ? colors.off
            : onLeave
              ? "#FECACA"
              : rowBg;
          const align = colIndex === 0 ? "left" : "center";
          return `<td style="background:${bg};color:${colors.text};border:1px solid #ffffff;padding:8px;text-align:${align};">${value}</td>`;
        })
        .join("");
      return `<tr>${cells}</tr>`;
    })
    .join("");

  const dayLegend = visibleIndexes
    .map(
      ({ day, index }) =>
        `<tr><td style="padding:4px 8px;">${day}</td><td style="padding:4px 8px;">${format(weekDays[index], "yyyy-MM-dd")}</td></tr>`
    )
    .join("");

  const html = `
<html xmlns:o="urn:schemas-microsoft-com:office:office"
      xmlns:x="urn:schemas-microsoft-com:office:excel"
      xmlns="http://www.w3.org/TR/REC-html40">
  <head>
    <meta charset="UTF-8" />
    <!--[if gte mso 9]>
    <xml>
      <x:ExcelWorkbook>
        <x:ExcelWorksheets>
          <x:ExcelWorksheet>
            <x:Name>Weekly Schedule</x:Name>
            <x:WorksheetOptions><x:DisplayGridlines/></x:WorksheetOptions>
          </x:ExcelWorksheet>
        </x:ExcelWorksheets>
      </x:ExcelWorkbook>
    </xml>
    <![endif]-->
    <style>
      table { border-collapse: collapse; font-family: Arial, sans-serif; font-size: 11px; }
    </style>
  </head>
  <body>
    <h2>${options.businessName}</h2>
    <p>Weekly Schedule: ${formatWeekRange(options.weekStart)}</p>
    <p>Generated: ${new Date().toLocaleString()}</p>
    <table>
      <thead><tr>${headHtml}</tr></thead>
      <tbody>${bodyHtml}</tbody>
    </table>
    <br/>
    <table>
      <thead>
        <tr>
          <th style="text-align:left;padding:4px 8px;">Day</th>
          <th style="text-align:left;padding:4px 8px;">Date</th>
        </tr>
      </thead>
      <tbody>${dayLegend}</tbody>
    </table>
  </body>
</html>`;

  const blob = new Blob(["\uFEFF" + html], {
    type: "application/vnd.ms-excel;charset=utf-8;",
  });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = `${options.businessName.replace(/\s+/g, "-").toLowerCase()}-schedule-${toDateKey(options.weekStart)}.xls`;
  link.click();
  URL.revokeObjectURL(url);
}

export function printSchedule(options: ExportOptions) {
  const {
    colors,
    weekDays,
    visibleIndexes,
    rowColors,
    defaultStart,
    defaultEnd,
  } = resolveOptions(options);

  const headHtml = `
    <th style="background:${colors.header};color:#fff;padding:10px;">Employee</th>
    ${visibleIndexes
      .map(
        ({ day, index }) =>
          `<th style="background:${colors.header};color:#fff;padding:10px;">${day}<br/><span style="font-weight:normal;font-size:11px;">${format(weekDays[index], "yyyy-MM-dd")}</span></th>`
      )
      .join("")}
  `;

  const tableRows = options.rows
    .map(({ employee, cells }, rowIndex) => {
      const rowBg = rowColors[rowIndex % rowColors.length];
      const cellsHtml = visibleIndexes
        .map(({ index }) => {
          const dayCells = cells[index] ?? [];
          const label = dayCellLabel(dayCells, defaultStart, defaultEnd);
          const isOff = label === "OFF";
          const onLeaveOnly =
            dayCells.length > 0 &&
            dayCells.every(
              (cell) => cell.on_leave && !cell.assigned_during_leave
            );

          if (dayCells.length > 0 && !onLeaveOnly) {
            const chips = dayCells
              .map((cell) => {
                if (cell.on_leave && !cell.assigned_during_leave) {
                  return `<div style="background:#FECACA;color:#7F1D1D;padding:6px;border-radius:4px;margin-bottom:4px;">On Leave</div>`;
                }
                const bg = cell.shift_color ?? rowBg;
                const fg = cell.shift_color
                  ? textColorForBackground(cell.shift_color)
                  : colors.text;
                const times = `${formatShiftTime(cell.shift_start_time)} – ${formatShiftTime(cell.shift_end_time)}`;
                const note = cell.assigned_during_leave
                  ? "<br/><span style='font-size:10px;'>Assigned During Leave</span>"
                  : "";
                return `<div style="background:${bg};color:${fg};padding:6px;border-radius:4px;margin-bottom:4px;"><strong>${cell.shift_name}</strong><br/>${times}${note}</div>`;
              })
              .join("");
            return `<td style="background:${rowBg};color:${colors.text};padding:8px;vertical-align:top;">${chips}</td>`;
          }

          const bg = isOff ? colors.off : onLeaveOnly ? "#FECACA" : rowBg;
          return `<td style="background:${bg};color:${colors.text};padding:8px;text-align:center;vertical-align:top;">${label}</td>`;
        })
        .join("");

      return `<tr><td style="background:${rowBg};color:${colors.text};padding:8px;"><strong>${employee.full_name}</strong></td>${cellsHtml}</tr>`;
    })
    .join("");

  const printWindow = window.open(
    "",
    "_blank",
    "noopener,noreferrer,width=1200,height=800"
  );
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
          th, td { border: 1px solid #ffffff; }
        </style>
      </head>
      <body>
        <h1>${options.businessName}</h1>
        <p>Weekly Schedule: ${formatWeekRange(options.weekStart)}</p>
        <p>Generated: ${new Date().toLocaleString()}</p>
        <table>
          <thead><tr>${headHtml}</tr></thead>
          <tbody>${tableRows}</tbody>
        </table>
      </body>
    </html>
  `);
  printWindow.document.close();
  printWindow.focus();
  printWindow.print();
}
