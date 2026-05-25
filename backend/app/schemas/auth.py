from pydantic import BaseModel, EmailStr, Field


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str = Field(min_length=8)


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    must_change_password: bool = False


class UserMeResponse(BaseModel):
    id: str
    email: str
    role: str
    business_id: str | None
    must_change_password: bool
    full_name: str | None = None
    business_name: str | None = None
