"""Phase 3: payroll adjustments become read-only after finalization."""

from datetime import date
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest
from fastapi import HTTPException

from app.models.enums import UserRole
from app.models.payroll_adjustment import PayrollAdjustment
from app.models.user import User
from app.services.payroll_adjustments import (
    create_adjustment,
    raise_if_period_finalized,
    soft_delete_adjustment,
    update_adjustment,
)

OPEN_START = date(2026, 9, 16)
OPEN_END = date(2099, 12, 31)
PERIOD_1_START = date(2026, 9, 1)
PERIOD_1_END = date(2026, 9, 15)


def _finalized_run(*, business_id, start=PERIOD_1_START, end=PERIOD_1_END):
    return SimpleNamespace(
        id=uuid4(),
        business_id=business_id,
        period_start=start,
        period_end=end,
        snapshot_version=1,
    )


def _db(*, row=None):
    db = MagicMock()
    captured = {"added": []}

    def add(obj):
        captured["added"].append(obj)
        if getattr(obj, "id", None) is None:
            obj.id = uuid4()

    db.add.side_effect = add
    q = MagicMock()
    q.filter.return_value.first.return_value = row
    db.query.return_value = q
    return db, captured


def _row(*, business_id, employee_id, start=OPEN_START, end=OPEN_END, amount=50.0):
    return SimpleNamespace(
        id=uuid4(),
        business_id=business_id,
        employee_id=employee_id,
        period_start=start,
        period_end=end,
        kind="allowance",
        type_key="meal_allowance",
        custom_name=None,
        description=None,
        amount=amount,
        previous_amount=None,
        updated_by=None,
        updated_at=None,
        deleted_at=None,
        deleted_by=None,
    )


def _assert_conflict(exc):
    assert exc.value.status_code == 409
    assert exc.value.detail["code"] == "payroll_finalized"
    assert "finalized" in exc.value.detail["message"].lower()


@patch("app.services.payroll_snapshot.find_finalized_run_for_period", return_value=None)
def test_create_adjustment_before_finalization(_find):
    business_id = uuid4()
    db, captured = _db()
    row = create_adjustment(
        db,
        business_id=business_id,
        employee_id=uuid4(),
        period_start=OPEN_START,
        period_end=OPEN_END,
        kind="allowance",
        type_key="meal_allowance",
        custom_name=None,
        description=None,
        amount=50,
        actor_id=uuid4(),
    )
    assert db.commit.called
    assert captured["added"]
    assert isinstance(row, PayrollAdjustment)
    assert float(row.amount) == 50


@patch("app.services.payroll_snapshot.find_finalized_run_for_period", return_value=None)
def test_update_adjustment_before_finalization(_find):
    business_id = uuid4()
    existing = _row(business_id=business_id, employee_id=uuid4(), amount=50)
    db, _captured = _db(row=existing)
    updated = update_adjustment(
        db,
        business_id=business_id,
        adjustment_id=existing.id,
        amount=75,
        actor_id=uuid4(),
    )
    assert db.commit.called
    assert float(updated.amount) == 75
    assert float(updated.previous_amount) == 50


@patch("app.services.payroll_snapshot.find_finalized_run_for_period", return_value=None)
def test_delete_adjustment_before_finalization(_find):
    business_id = uuid4()
    existing = _row(business_id=business_id, employee_id=uuid4())
    db, _captured = _db(row=existing)
    soft_delete_adjustment(
        db,
        business_id=business_id,
        adjustment_id=existing.id,
        actor_id=uuid4(),
    )
    assert db.commit.called
    assert existing.deleted_at is not None


def test_create_adjustment_after_finalization_is_rejected():
    business_id = uuid4()
    db, captured = _db()
    with patch(
        "app.services.payroll_snapshot.find_finalized_run_for_period",
        return_value=_finalized_run(business_id=business_id),
    ):
        with pytest.raises(HTTPException) as exc:
            create_adjustment(
                db,
                business_id=business_id,
                employee_id=uuid4(),
                period_start=PERIOD_1_START,
                period_end=PERIOD_1_END,
                kind="allowance",
                type_key="meal_allowance",
                custom_name=None,
                description=None,
                amount=50,
                actor_id=uuid4(),
            )
    _assert_conflict(exc)
    assert captured["added"] == []
    assert db.commit.called is False


def test_update_adjustment_after_finalization_is_rejected():
    business_id = uuid4()
    existing = _row(
        business_id=business_id,
        employee_id=uuid4(),
        start=PERIOD_1_START,
        end=PERIOD_1_END,
        amount=50,
    )
    db, _captured = _db(row=existing)
    with patch(
        "app.services.payroll_snapshot.find_finalized_run_for_period",
        return_value=_finalized_run(business_id=business_id),
    ):
        with pytest.raises(HTTPException) as exc:
            update_adjustment(
                db,
                business_id=business_id,
                adjustment_id=existing.id,
                amount=99,
                actor_id=uuid4(),
            )
    _assert_conflict(exc)
    assert float(existing.amount) == 50
    assert db.commit.called is False


def test_delete_adjustment_after_finalization_is_rejected():
    business_id = uuid4()
    existing = _row(
        business_id=business_id,
        employee_id=uuid4(),
        start=PERIOD_1_START,
        end=PERIOD_1_END,
    )
    db, _captured = _db(row=existing)
    with patch(
        "app.services.payroll_snapshot.find_finalized_run_for_period",
        return_value=_finalized_run(business_id=business_id),
    ):
        with pytest.raises(HTTPException) as exc:
            soft_delete_adjustment(
                db,
                business_id=business_id,
                adjustment_id=existing.id,
                actor_id=uuid4(),
            )
    _assert_conflict(exc)
    assert existing.deleted_at is None
    assert db.commit.called is False


def test_early_finalization_locks_adjustments_before_period_end():
    business_id = uuid4()
    employee_id = uuid4()
    existing = _row(business_id=business_id, employee_id=employee_id)
    db, captured = _db(row=existing)
    run = _finalized_run(business_id=business_id, start=OPEN_START, end=OPEN_END)
    with patch(
        "app.services.payroll_snapshot.find_finalized_run_for_period",
        return_value=run,
    ):
        with pytest.raises(HTTPException) as create_exc:
            create_adjustment(
                db,
                business_id=business_id,
                employee_id=employee_id,
                period_start=OPEN_START,
                period_end=OPEN_END,
                kind="deduction",
                type_key="cash_shortage",
                custom_name=None,
                description=None,
                amount=10,
                actor_id=uuid4(),
            )
        with pytest.raises(HTTPException) as update_exc:
            update_adjustment(
                db,
                business_id=business_id,
                adjustment_id=existing.id,
                amount=80,
                actor_id=uuid4(),
            )
        with pytest.raises(HTTPException) as delete_exc:
            soft_delete_adjustment(
                db,
                business_id=business_id,
                adjustment_id=existing.id,
                actor_id=uuid4(),
            )
    _assert_conflict(create_exc)
    _assert_conflict(update_exc)
    _assert_conflict(delete_exc)
    assert captured["added"] == []
    assert float(existing.amount) == 50
    assert existing.deleted_at is None


def test_unfinalized_period_remains_editable_when_another_period_is_finalized():
    business_id = uuid4()
    db, captured = _db()

    def find_run(_db, *, business_id, period_start, period_end):
        if period_start == PERIOD_1_START and period_end == PERIOD_1_END:
            return _finalized_run(
                business_id=business_id, start=PERIOD_1_START, end=PERIOD_1_END
            )
        return None

    with patch(
        "app.services.payroll_snapshot.find_finalized_run_for_period",
        side_effect=find_run,
    ):
        with pytest.raises(HTTPException) as locked:
            create_adjustment(
                db,
                business_id=business_id,
                employee_id=uuid4(),
                period_start=PERIOD_1_START,
                period_end=PERIOD_1_END,
                kind="allowance",
                type_key="meal_allowance",
                custom_name=None,
                description=None,
                amount=50,
                actor_id=uuid4(),
            )
        created = create_adjustment(
            db,
            business_id=business_id,
            employee_id=uuid4(),
            period_start=OPEN_START,
            period_end=OPEN_END,
            kind="allowance",
            type_key="meal_allowance",
            custom_name=None,
            description=None,
            amount=25,
            actor_id=uuid4(),
        )
    _assert_conflict(locked)
    assert float(created.amount) == 25
    assert captured["added"]


def test_other_employee_unfinalized_period_is_not_blocked():
    business_id = uuid4()
    employee_b = uuid4()
    db, captured = _db()
    with patch(
        "app.services.payroll_snapshot.find_finalized_run_for_period",
        return_value=None,
    ):
        created = create_adjustment(
            db,
            business_id=business_id,
            employee_id=employee_b,
            period_start=OPEN_START,
            period_end=OPEN_END,
            kind="allowance",
            type_key="incentive",
            custom_name=None,
            description=None,
            amount=40,
            actor_id=uuid4(),
        )
    assert created.employee_id == employee_b
    assert captured["added"]


def test_authorization_still_scopes_mutations_to_business():
    owner_business = uuid4()
    existing = _row(business_id=uuid4(), employee_id=uuid4())
    db, _captured = _db(row=None)
    with patch(
        "app.services.payroll_snapshot.find_finalized_run_for_period",
        return_value=None,
    ):
        with pytest.raises(HTTPException) as exc:
            update_adjustment(
                db,
                business_id=owner_business,
                adjustment_id=existing.id,
                amount=1,
                actor_id=uuid4(),
            )
        with pytest.raises(HTTPException) as delete_exc:
            soft_delete_adjustment(
                db,
                business_id=owner_business,
                adjustment_id=existing.id,
                actor_id=uuid4(),
            )
    assert exc.value.status_code == 404
    assert delete_exc.value.status_code == 404


def test_rejected_mutation_does_not_change_finalized_snapshot():
    business_id = uuid4()
    snapshot = {
        "final_net_pay": 741.26,
        "payroll_adjustments": [{"amount": 50.0}],
        "breakdown": "frozen",
    }
    existing = _row(
        business_id=business_id,
        employee_id=uuid4(),
        start=PERIOD_1_START,
        end=PERIOD_1_END,
        amount=50,
    )
    db, captured = _db(row=existing)
    with patch(
        "app.services.payroll_snapshot.find_finalized_run_for_period",
        return_value=_finalized_run(business_id=business_id),
    ):
        with pytest.raises(HTTPException):
            update_adjustment(
                db,
                business_id=business_id,
                adjustment_id=existing.id,
                amount=999,
                actor_id=uuid4(),
            )
        with pytest.raises(HTTPException):
            create_adjustment(
                db,
                business_id=business_id,
                employee_id=existing.employee_id,
                period_start=PERIOD_1_START,
                period_end=PERIOD_1_END,
                kind="allowance",
                type_key="meal_allowance",
                custom_name=None,
                description=None,
                amount=1,
                actor_id=uuid4(),
            )
        with pytest.raises(HTTPException):
            soft_delete_adjustment(
                db,
                business_id=business_id,
                adjustment_id=existing.id,
                actor_id=uuid4(),
            )
    assert snapshot["final_net_pay"] == 741.26
    assert snapshot["payroll_adjustments"][0]["amount"] == 50.0
    assert float(existing.amount) == 50
    assert existing.deleted_at is None
    assert captured["added"] == []


def test_raise_if_period_finalized_uses_stored_period_dates():
    business_id = uuid4()
    db = MagicMock()
    with patch(
        "app.services.payroll_snapshot.find_finalized_run_for_period",
        return_value=_finalized_run(business_id=business_id),
    ) as find_run:
        with pytest.raises(HTTPException):
            raise_if_period_finalized(
                db,
                business_id=business_id,
                period_start=PERIOD_1_START,
                period_end=PERIOD_1_END,
            )
    find_run.assert_called_once_with(
        db,
        business_id=business_id,
        period_start=PERIOD_1_START,
        period_end=PERIOD_1_END,
    )


def test_owner_api_create_uses_service_lock():
    from app.api.payroll_adjustments import create_employee_adjustment

    business_id = uuid4()
    user = User(
        id=uuid4(),
        business_id=business_id,
        role=UserRole.owner,
        is_active=True,
    )
    employee = SimpleNamespace(id=uuid4(), business_id=business_id)
    db = MagicMock()
    db.get.side_effect = lambda model, key: (
        employee if key == employee.id else SimpleNamespace()
    )
    with (
        patch(
            "app.api.payroll_adjustments.resolve_pay_period",
            return_value=(PERIOD_1_START, PERIOD_1_END),
        ),
        patch(
            "app.api.payroll_adjustments.create_adjustment",
            side_effect=HTTPException(
                status_code=409,
                detail={
                    "code": "payroll_finalized",
                    "message": "This payroll period is already finalized.",
                },
            ),
        ) as create,
    ):
        with pytest.raises(HTTPException) as exc:
            create_employee_adjustment(
                employee_id=employee.id,
                body=SimpleNamespace(
                    kind="allowance",
                    type_key="meal_allowance",
                    custom_name=None,
                    description=None,
                    amount=50,
                ),
                db=db,
                user=user,
                as_of=date(2026, 9, 10),
            )
    assert exc.value.status_code == 409
    create.assert_called_once()


def test_owner_api_update_and_delete_use_service_lock():
    from app.api.payroll_adjustments import delete_adjustment, patch_adjustment

    business_id = uuid4()
    user = User(
        id=uuid4(),
        business_id=business_id,
        role=UserRole.owner,
        is_active=True,
    )
    adjustment_id = uuid4()
    db = MagicMock()
    conflict = HTTPException(
        status_code=409,
        detail={
            "code": "payroll_finalized",
            "message": "This payroll period is already finalized.",
        },
    )
    with (
        patch(
            "app.api.payroll_adjustments.update_adjustment",
            side_effect=conflict,
        ) as update,
        patch(
            "app.api.payroll_adjustments.soft_delete_adjustment",
            side_effect=conflict,
        ) as delete,
    ):
        with pytest.raises(HTTPException) as update_exc:
            patch_adjustment(
                adjustment_id=adjustment_id,
                body=SimpleNamespace(
                    kind=None,
                    type_key=None,
                    custom_name=None,
                    description=None,
                    amount=99,
                ),
                db=db,
                user=user,
            )
        with pytest.raises(HTTPException) as delete_exc:
            delete_adjustment(
                adjustment_id=adjustment_id,
                db=db,
                user=user,
            )
    assert update_exc.value.status_code == 409
    assert delete_exc.value.status_code == 409
    update.assert_called_once()
    delete.assert_called_once()
