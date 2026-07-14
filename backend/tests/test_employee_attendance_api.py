def test_invalid_shift_assignment_id_returns_422(client):
    response = client.post(
        "/api/v1/employee/attendance/clock-in",
        json={
            "latitude": 14.6760,
            "longitude": 121.0437,
            "shift_assignment_id": "not-a-valid-uuid",
        },
        headers={"Authorization": "Bearer test-token"},
    )
    assert response.status_code == 422


def test_clock_in_missing_body_fields_returns_422(client):
    response = client.post(
        "/api/v1/employee/attendance/clock-in",
        json={"shift_assignment_id": "not-a-valid-uuid"},
        headers={"Authorization": "Bearer test-token"},
    )
    assert response.status_code == 422
