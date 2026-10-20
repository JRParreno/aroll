export const OTHER_REJECTION_REASON_ID = "other";

export const REGISTRATION_REJECTION_REASONS = [
  {
    id: "missing_documents",
    label: "Required documents are missing.",
  },
  {
    id: "incomplete_documents",
    label: "Submitted documents are incomplete.",
  },
  {
    id: "invalid_documents",
    label: "One or more submitted documents are invalid or unreadable.",
  },
  {
    id: "incomplete_business_info",
    label: "Business information is incomplete.",
  },
  {
    id: "info_mismatch",
    label: "Business information does not match the submitted documents.",
  },
  {
    id: "unverified_information",
    label: "Submitted information could not be verified.",
  },
  {
    id: "incorrect_inconsistent",
    label: "The application contains incorrect or inconsistent information.",
  },
  {
    id: "expired_documents",
    label: "The submitted documents appear to be expired.",
  },
  {
    id: "does_not_meet_requirements",
    label: "The application does not meet the registration requirements.",
  },
  {
    id: OTHER_REJECTION_REASON_ID,
    label: "Other reason — requires a short explanation.",
  },
] as const;

export type RejectionReasonId =
  (typeof REGISTRATION_REJECTION_REASONS)[number]["id"];

export function toggleRejectionReason(
  selected: string[],
  reasonId: string
): string[] {
  return selected.includes(reasonId)
    ? selected.filter((id) => id !== reasonId)
    : [...selected, reasonId];
}

export function canConfirmRejection(
  selected: string[],
  otherExplanation: string
): boolean {
  if (selected.length === 0) return false;
  if (
    selected.includes(OTHER_REJECTION_REASON_ID) &&
    !otherExplanation.trim()
  ) {
    return false;
  }
  return true;
}

export function buildRejectionPayload(
  selected: string[],
  otherExplanation: string
): { reasons: string[]; other_explanation?: string } {
  const reasons = selected.filter((id) =>
    REGISTRATION_REJECTION_REASONS.some((option) => option.id === id)
  );
  const payload: { reasons: string[]; other_explanation?: string } = { reasons };
  if (reasons.includes(OTHER_REJECTION_REASON_ID)) {
    payload.other_explanation = otherExplanation.trim();
  }
  return payload;
}
