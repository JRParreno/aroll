from datetime import datetime

from pydantic import BaseModel, EmailStr, Field, field_validator, model_validator

from app.core.password_validation import validate_password_strength
from app.schemas.business import BusinessBrandingSettings


class LoginRequest(BaseModel):
    email: str | None = None
    username: str | None = None
    password: str

    @model_validator(mode="after")
    def resolve_login_identifier(self):
        login_id = (self.username or self.email or "").strip()
        if not login_id:
            raise ValueError("email or username is required")
        self.email = login_id
        return self


class BusinessOwnerLoginRequest(BaseModel):
    business_code: str
    email: EmailStr
    password: str


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str = Field(min_length=8)

    @field_validator("new_password")
    @classmethod
    def validate_new_password(cls, value: str) -> str:
        validate_password_strength(value)
        return value


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    must_change_password: bool = False
    employee_id: str | None = None
    business_id: str | None = None
    full_name: str | None = None
    position: str | None = None
    role: str | None = None
    business_name: str | None = None


class UserMeResponse(BaseModel):
    id: str
    email: str
    role: str
    business_id: str | None
    must_change_password: bool
    employee_id: str | None = None
    full_name: str | None = None
    position: str | None = None
    business_name: str | None = None
    business_code: str | None = None
    setup_completed_at: datetime | None = None
    branding: BusinessBrandingSettings | None = None
