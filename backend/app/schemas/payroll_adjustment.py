from datetime import date

from pydantic import BaseModel, Field


class PayrollAdjustmentCreateRequest(BaseModel):
    kind: str = Field(default="deduction", description="deduction or allowance")
    type_key: str
    custom_name: str | None = None
    description: str | None = None
    amount: float


class PayrollAdjustmentUpdateRequest(BaseModel):
    kind: str | None = None
    type_key: str | None = None
    custom_name: str | None = None
    description: str | None = None
    amount: float | None = None


class PayrollAdjustmentResponse(BaseModel):
    id: str
    employee_id: str
    period_start: date | str
    period_end: date | str
    kind: str
    type_key: str
    custom_name: str | None = None
    display_name: str
    description: str | None = None
    amount: float
    created_by: str | None = None
    created_at: str | None = None
    updated_by: str | None = None
    updated_at: str | None = None
    previous_amount: float | None = None
