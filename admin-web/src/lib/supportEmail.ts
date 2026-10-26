export const SUPPORT_EMAIL = "arollplus1111@gmail.com";
export const SUPPORT_SUBJECT_MAX = 120;
export const SUPPORT_MESSAGE_MAX = 4000;

const FALLBACK_ERROR =
  "The support message could not be sent. Try again in a moment.";

export function validateSupportDraft(subject: string, message: string): string | null {
  const cleanSubject = subject.trim();
  const cleanMessage = message.trim();
  if (!cleanSubject) return "Enter a subject.";
  if (cleanSubject.length > SUPPORT_SUBJECT_MAX) {
    return `Subject must be ${SUPPORT_SUBJECT_MAX} characters or less.`;
  }
  if (!cleanMessage) return "Enter the concern or message.";
  if (cleanMessage.length > SUPPORT_MESSAGE_MAX) {
    return `Message must be ${SUPPORT_MESSAGE_MAX} characters or less.`;
  }
  return null;
}

export function claimSupportSubmit(inFlight: { current: boolean }): boolean {
  if (inFlight.current) return false;
  inFlight.current = true;
  return true;
}

export function supportRequestErrorMessage(error: unknown): string {
  const detail = readDetail(error);
  if (
    typeof detail === "string" &&
    detail.trim() &&
    detail.length <= 300 &&
    !/traceback|smtp|password|exception/i.test(detail)
  ) {
    return detail.trim();
  }
  return FALLBACK_ERROR;
}

function readDetail(error: unknown): unknown {
  if (!error || typeof error !== "object" || !("response" in error)) return null;
  const response = (error as { response?: { data?: { detail?: unknown } } }).response;
  return response?.data?.detail ?? null;
}
