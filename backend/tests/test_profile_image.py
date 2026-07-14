import pytest
from fastapi import HTTPException

from app.core.profile_image import validate_profile_image_data


def test_validate_profile_image_accepts_data_uri():
    value = "data:image/png;base64,abcd"
    assert validate_profile_image_data(value) == value


def test_validate_profile_image_rejects_invalid_prefix():
    with pytest.raises(HTTPException) as exc:
        validate_profile_image_data("https://example.com/a.png")
    assert exc.value.status_code == 400


def test_validate_profile_image_rejects_oversized_payload():
    oversized = "data:image/png;base64," + ("a" * 2_500_000)
    with pytest.raises(HTTPException) as exc:
        validate_profile_image_data(oversized)
    assert exc.value.status_code == 400
