export const SHIFT_DELETE_BLOCKED_MESSAGE =
  "This shift cannot be deleted because an employee assigned to it is currently timed in. Ask them to complete Time Out, then try again.";

export function shiftDeleteBlockedMessage(error: unknown): string | null {
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
    return null;
  }
  const detail = error.response.data.detail;
  if (
    typeof detail === "object" &&
    detail !== null &&
    "code" in detail &&
    detail.code === "shift_delete_blocked"
  ) {
    return "message" in detail && typeof detail.message === "string" && detail.message
      ? detail.message
      : SHIFT_DELETE_BLOCKED_MESSAGE;
  }
  return null;
}
