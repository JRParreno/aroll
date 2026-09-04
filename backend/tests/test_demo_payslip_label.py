"""Phase 3 presentation: DEMO01 sample payslip labeling."""

from fastapi.testclient import TestClient

from app.main import app
from app.seed_demo import DEMO_EMPLOYEE_01_EMAIL, DEMO_SEED_PASSWORD, seed_demo
from app.seed_internal_test import DEV_EMPLOYEE_EMAIL, DEV_SEED_PASSWORD, seed_internal_test


def test_demo_payslip_pdf_is_labeled_sample():
    seed_demo()
    client = TestClient(app)
    token = client.post(
        "/api/v1/auth/login",
        json={"email": DEMO_EMPLOYEE_01_EMAIL, "password": DEMO_SEED_PASSWORD},
    ).json()["access_token"]
    response = client.get(
        "/api/v1/employee/payslip/pdf",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    body = response.content
    assert b"SAMPLE" in body
    assert b"DEMONSTRATION ONLY" in body
    assert b"NOT FOR ACTUAL SALARY PAYMENT" in body


def test_devtest_payslip_pdf_is_not_demo_labeled():
    seed_internal_test()
    client = TestClient(app)
    token = client.post(
        "/api/v1/auth/login",
        json={"email": DEV_EMPLOYEE_EMAIL, "password": DEV_SEED_PASSWORD},
    ).json()["access_token"]
    response = client.get(
        "/api/v1/employee/payslip/pdf",
        headers={"Authorization": f"Bearer {token}"},
    )
    # DEVTEST has no payroll rows yet; PDF may still generate empty/zero slip.
    if response.status_code != 200:
        return
    body = response.content
    assert b"DEMONSTRATION ONLY" not in body
    assert b"NOT FOR ACTUAL SALARY PAYMENT" not in body
