import type { ScheduleColors } from "@/lib/api";
import { WEEKDAY_LABELS } from "@/components/owner/schedule/scheduleUtils";

export type ScheduleDisplaySettings = {
  default_start: string;
  default_end: string;
  visible_days: string[];
};

export const defaultScheduleColors: ScheduleColors = {
  header: "#1E3A5F",
  row1: "#FFE5A3",
  row2: "#FFB166",
  row3: "#B8F28C",
  row4: "#B9D8F7",
  row5: "#F2A7EA",
  off: "#F8B4B4",
  text: "#111827",
};

export const defaultScheduleDisplay: ScheduleDisplaySettings = {
  default_start: "09:00",
  default_end: "17:00",
  visible_days: [...WEEKDAY_LABELS],
};
