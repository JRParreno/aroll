"""Account-level permissions onboarding completion."""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.main import app
from app.models.employee import Employee
from tests.test_legal_consent import _auth, _create_tenant


def test_permissions_onboarding_is_account_scoped_via_auth_identity():
    db, _business, _owner, employee_user, emp = _create_tenant()
    client = TestClient(app)
    try:
        assert emp.permissions_onboarding_completed_at is None

        me = client.get("/api/v1/auth/me", headers=_auth(employee_user))
        assert me.status_code == 200
        assert me.json()["permissions_onboarding_completed"] is False

        complete = client.post(
            "/api/v1/employee/permissions-onboarding/complete",
            headers=_auth(employee_user),
        )
        assert complete.status_code == 200, complete.text
        assert complete.json()["permissions_onboarding_completed"] is True

        db.refresh(emp)
        assert emp.permissions_onboarding_completed_at is not None

        me_after = client.get("/api/v1/auth/me", headers=_auth(employee_user))
        assert me_after.json()["permissions_onboarding_completed"] is True

        # Idempotent — does not clear or require a client-supplied account id.
        again = client.post(
            "/api/v1/employee/permissions-onboarding/complete",
            headers=_auth(employee_user),
        )
        assert again.status_code == 200

        # A second employee on the same business stays incomplete.
        other = (
            db.query(Employee)
            .filter(Employee.business_id == emp.business_id, Employee.id != emp.id)
            .first()
        )
        if other is None:
            return
        assert other.permissions_onboarding_completed_at is None
    finally:
        db.close()
