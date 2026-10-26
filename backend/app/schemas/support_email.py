from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.services.support_email import MESSAGE_MAX_LENGTH, SUBJECT_MAX_LENGTH


class SupportEmailRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    subject: str = Field(min_length=1, max_length=SUBJECT_MAX_LENGTH)
    message: str = Field(min_length=1, max_length=MESSAGE_MAX_LENGTH)

    @field_validator("subject", "message", mode="before")
    @classmethod
    def _must_be_text(cls, value: object) -> str:
        if not isinstance(value, str):
            raise ValueError("Enter text.")
        return value

    @field_validator("subject")
    @classmethod
    def _subject_is_one_line(cls, value: str) -> str:
        if "\r" in value or "\n" in value or "\x00" in value:
            raise ValueError("Subject cannot contain line breaks.")
        cleaned = " ".join(value.split())
        if not cleaned:
            raise ValueError("Enter a subject.")
        return cleaned

    @field_validator("message")
    @classmethod
    def _message_present(cls, value: str) -> str:
        cleaned = value.replace("\x00", "").strip()
        if not cleaned:
            raise ValueError("Enter the concern or message.")
        return cleaned


class SupportEmailResponse(BaseModel):
    status: str
    detail: str
