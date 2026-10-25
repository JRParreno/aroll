export const SCHEDULE_REMOVAL_FALLBACK = "Failed to remove schedule";

export function scheduleRemovalErrorMessage(error: unknown): string {
  if (
    typeof error !== "object" ||
    error === null ||
    !("response" in error) ||
    typeof error.response !== "object" ||
    error.response === null ||
    !("data" in error.response) ||
    typeof error.response.data !== "object" ||
    error.response.data === null ||
    !("detail" in error.response.data)
  ) {
    return SCHEDULE_REMOVAL_FALLBACK;
  }
  const detail = error.response.data.detail;
  if (typeof detail === "string" && detail.trim()) return detail;
  if (
    typeof detail === "object" &&
    detail !== null &&
    "message" in detail &&
    typeof detail.message === "string" &&
    detail.message.trim()
  ) {
    return detail.message;
  }
  return SCHEDULE_REMOVAL_FALLBACK;
}
