/** Format an attendance UTC instant in the business IANA timezone. */
export function formatAttendanceTime(
  value: string | null | undefined,
  timeZone?: string | null,
) {
  if (!value) return "--:--";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "--:--";
  return date.toLocaleTimeString("en-US", {
    timeZone: timeZone?.trim() || undefined,
    hour: "numeric",
    minute: "2-digit",
  });
}
