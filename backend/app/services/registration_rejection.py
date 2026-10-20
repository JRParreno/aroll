"""Canonical registration rejection reasons used by admin reject and email."""

from __future__ import annotations

from fastapi import HTTPException

REJECTION_REASON_OPTIONS: tuple[tuple[str, str], ...] = (
    ("missing_documents", "Required documents are missing."),
    ("incomplete_documents", "Submitted documents are incomplete."),
    ("invalid_documents", "One or more submitted documents are invalid or unreadable."),
    ("incomplete_business_info", "Business information is incomplete."),
    ("info_mismatch", "Business information does not match the submitted documents."),
    ("unverified_information", "Submitted information could not be verified."),
    ("incorrect_inconsistent", "The application contains incorrect or inconsistent information."),
    ("expired_documents", "The submitted documents appear to be expired."),
    ("does_not_meet_requirements", "The application does not meet the registration requirements."),
    ("other", "Other reason"),
)

REJECTION_REASON_LABELS = {key: label for key, label in REJECTION_REASON_OPTIONS}
OTHER_REASON_ID = "other"


def rejection_reason_lines(stored: str | None) -> list[str]:
    return [line.strip() for line in (stored or "").splitlines() if line.strip()]


def format_rejection_reasons(
    reason_ids: list[str],
    other_explanation: str | None = None,
) -> str:
    labels: list[str] = []
    for reason_id in reason_ids:
        if reason_id == OTHER_REASON_ID:
            labels.append((other_explanation or "").strip())
        else:
            labels.append(REJECTION_REASON_LABELS[reason_id])
    return "\n".join(labels)


def validate_rejection_reasons(
    reason_ids: list[str] | None,
    other_explanation: str | None = None,
) -> list[str]:
    ids = [str(item).strip() for item in (reason_ids or []) if str(item).strip()]
    if not ids:
        raise HTTPException(400, "Select at least one rejection reason")
    if len(ids) != len(set(ids)):
        raise HTTPException(400, "Duplicate rejection reasons are not allowed")

    unknown = [item for item in ids if item not in REJECTION_REASON_LABELS]
    if unknown:
        raise HTTPException(400, "One or more rejection reasons are not valid")

    explanation = (other_explanation or "").strip()
    if OTHER_REASON_ID in ids and not explanation:
        raise HTTPException(400, "Provide a short explanation for Other reason")
    return ids
