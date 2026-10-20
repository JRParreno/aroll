"""Position / Role pay configuration helpers (Design B)."""

from __future__ import annotations

from fastapi import HTTPException

from app.models.enums import PayBasis
from app.models.payroll import Position, PositionPayConfig


def validate_pay_config_items(
    items: list[tuple[PayBasis, float]],
) -> list[tuple[PayBasis, float]]:
    """Normalize and validate (basis, rate) pairs for a Role."""
    if not items:
        raise ValueError("At least one pay configuration (Daily or Hourly) is required.")
    seen: set[PayBasis] = set()
    cleaned: list[tuple[PayBasis, float]] = []
    for basis, rate in items:
        if basis not in (PayBasis.daily, PayBasis.hourly):
            raise ValueError(
                "Position pay configurations must be daily or hourly. "
                "Monthly pay remains employee-only."
            )
        if basis in seen:
            raise ValueError(
                f"Duplicate pay basis '{basis.value}' is not allowed for the same role."
            )
        amount = float(rate)
        if amount <= 0:
            raise ValueError("Pay configuration rate must be greater than zero.")
        seen.add(basis)
        cleaned.append((basis, amount))
    return cleaned


def sync_legacy_position_rates(pos: Position) -> None:
    """Keep Position.daily_rate / hourly_rate / pay_basis aligned for fallbacks."""
    daily = None
    hourly = None
    for cfg in pos.pay_configs:
        if cfg.pay_basis == PayBasis.daily:
            daily = float(cfg.rate)
        elif cfg.pay_basis == PayBasis.hourly:
            hourly = float(cfg.rate)
    pos.daily_rate = daily
    pos.hourly_rate = hourly
    if hourly is not None and daily is None:
        pos.pay_basis = PayBasis.hourly
    else:
        pos.pay_basis = PayBasis.daily


def replace_pay_configs(
    pos: Position,
    items: list[tuple[PayBasis, float]],
) -> None:
    cleaned = validate_pay_config_items(items)
    pos.pay_configs.clear()
    for basis, rate in cleaned:
        pos.pay_configs.append(PositionPayConfig(pay_basis=basis, rate=rate))
    sync_legacy_position_rates(pos)


def resolve_pay_config(pos: Position, pay_basis: PayBasis) -> PositionPayConfig:
    """Return the matching config or raise HTTP 400."""
    if pay_basis not in (PayBasis.daily, PayBasis.hourly):
        raise HTTPException(
            status_code=400,
            detail={
                "code": "pay_config_not_found",
                "message": (
                    "Selected pay basis is not configured for this role in "
                    "Setup Wizard. Choose Daily or Hourly from the role's "
                    "configured options."
                ),
            },
        )
    for cfg in pos.pay_configs:
        if cfg.pay_basis == pay_basis:
            return cfg
    # Legacy fallback: Position columns if configs not yet backfilled/loaded
    if pay_basis == PayBasis.daily and pos.daily_rate is not None and float(pos.daily_rate) > 0:
        return PositionPayConfig(
            position_id=pos.id,
            pay_basis=PayBasis.daily,
            rate=float(pos.daily_rate),
        )
    if (
        pay_basis == PayBasis.hourly
        and pos.hourly_rate is not None
        and float(pos.hourly_rate) > 0
    ):
        return PositionPayConfig(
            position_id=pos.id,
            pay_basis=PayBasis.hourly,
            rate=float(pos.hourly_rate),
        )
    raise HTTPException(
        status_code=400,
        detail={
            "code": "pay_config_not_found",
            "message": (
                "Selected pay basis is not configured for this role in "
                "Setup Wizard. Update the role's pay configurations first."
            ),
        },
    )


def apply_config_to_employee_fields(cfg: PositionPayConfig) -> dict:
    """Authoritative employee pay fields from a PositionPayConfig."""
    rate = float(cfg.rate)
    if cfg.pay_basis == PayBasis.daily:
        return {
            "pay_basis": PayBasis.daily,
            "daily_rate": rate,
            "hourly_rate": None,
            "monthly_salary": None,
        }
    return {
        "pay_basis": PayBasis.hourly,
        "daily_rate": None,
        "hourly_rate": rate,
        "monthly_salary": None,
    }
