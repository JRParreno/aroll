from pydantic import BaseModel, Field

from app.models.enums import PayPeriodType


class LocationUpdate(BaseModel):
    label: str = "Main"
    address: str = Field(min_length=5)
    latitude: float | None = None
    longitude: float | None = None
    geofence_radius_m: int = Field(default=75, ge=20, le=200)


class PayrollConfigUpdate(BaseModel):
    pay_period_type: PayPeriodType = PayPeriodType.monthly
    late_deduction_enabled: bool = True
    late_deduction_per_minute: float = 1.0
    overtime_enabled: bool = True
    overtime_per_minute: float = 1.0
