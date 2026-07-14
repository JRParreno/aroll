import uuid
from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient

from app.core.deps import get_current_user
from app.main import app
from app.models.enums import UserRole


@pytest.fixture
def client():
    user = MagicMock()
    user.id = uuid.uuid4()
    user.role = UserRole.employee
    user.business_id = uuid.uuid4()
    user.is_active = True

    app.dependency_overrides[get_current_user] = lambda: user
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()
