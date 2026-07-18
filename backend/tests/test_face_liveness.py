"""Unit tests for head-turn liveness challenge validation."""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

import pytest

from app.services.face_embedding import FaceObservation
from app.services.face_liveness import (
    LivenessError,
    _require_centered,
    _require_continuity,
    _require_turn,
    observe_pose,
    validate_liveness_sequence,
)


def _obs(*, yaw: float, embedding: list[float] | None = None) -> FaceObservation:
    emb = embedding or ([1.0] + [0.0] * 127)
    # Normalize-ish for continuity tests
    return FaceObservation(
        embedding=emb,
        score=0.99,
        yaw=yaw,
        left_eye=(60.0, 40.0),
        right_eye=(40.0, 40.0),
        nose=(50.0, 55.0),
        box=(20.0, 20.0, 80.0, 80.0),
    )


def test_require_centered_rejects_turned_pose():
    with pytest.raises(LivenessError) as exc:
        _require_centered(_obs(yaw=0.35), label="Center")
    assert exc.value.detail["code"] == "pose_not_centered"


def test_require_centered_accepts_front():
    _require_centered(_obs(yaw=0.05), label="Center")


def test_require_turn_detects_left():
    _require_turn(_obs(yaw=-0.40), "turn_left", center_yaw=0.0)


def test_require_turn_rejects_wrong_direction():
    with pytest.raises(LivenessError) as exc:
        _require_turn(_obs(yaw=0.40), "turn_left", center_yaw=0.0)
    assert exc.value.detail["code"] == "turn_wrong_direction"


def test_require_turn_rejects_small_delta():
    with pytest.raises(LivenessError) as exc:
        _require_turn(_obs(yaw=-0.30), "turn_left", center_yaw=-0.20)
    assert exc.value.detail["code"] == "turn_not_detected"


def test_require_continuity_rejects_different_identity():
    a = _obs(yaw=0.0, embedding=[1.0] + [0.0] * 127)
    b = _obs(yaw=0.0, embedding=[0.0, 1.0] + [0.0] * 126)
    with pytest.raises(LivenessError) as exc:
        _require_continuity(a, b, pair="center/turn")
    assert exc.value.detail["code"] == "identity_changed"


def test_validate_rejects_expired_challenge():
    db = MagicMock()
    challenge = MagicMock()
    challenge.id = uuid.uuid4()
    challenge.employee_id = uuid.uuid4()
    challenge.direction = "turn_left"
    challenge.consumed_at = None
    challenge.expires_at = datetime.now(timezone.utc) - timedelta(seconds=5)
    db.get.return_value = challenge

    employee = MagicMock()
    employee.id = challenge.employee_id

    with pytest.raises(LivenessError) as exc:
        validate_liveness_sequence(
            db,
            challenge_id=challenge.id,
            employee=employee,
            center_bytes=b"a",
            turn_bytes=b"b",
            return_bytes=b"c",
        )
    assert exc.value.detail["code"] == "challenge_expired"


def test_validate_rejects_used_challenge():
    db = MagicMock()
    challenge = MagicMock()
    challenge.id = uuid.uuid4()
    challenge.employee_id = uuid.uuid4()
    challenge.direction = "turn_right"
    challenge.consumed_at = datetime.now(timezone.utc)
    challenge.expires_at = datetime.now(timezone.utc) + timedelta(seconds=60)
    db.get.return_value = challenge

    employee = MagicMock()
    employee.id = challenge.employee_id

    with pytest.raises(LivenessError) as exc:
        validate_liveness_sequence(
            db,
            challenge_id=challenge.id,
            employee=employee,
            center_bytes=b"a",
            turn_bytes=b"b",
            return_bytes=b"c",
        )
    assert exc.value.detail["code"] == "challenge_used"


def test_validate_happy_path_consumes_challenge():
    db = MagicMock()
    challenge = MagicMock()
    challenge.id = uuid.uuid4()
    challenge.employee_id = uuid.uuid4()
    challenge.direction = "turn_right"
    challenge.consumed_at = None
    challenge.expires_at = datetime.now(timezone.utc) + timedelta(seconds=60)
    db.get.return_value = challenge

    sample = MagicMock()
    sample.embedding = [1.0] + [0.0] * 127
    db.query.return_value.filter.return_value.all.return_value = [sample]

    employee = MagicMock()
    employee.id = challenge.employee_id

    center = _obs(yaw=0.02, embedding=[1.0] + [0.0] * 127)
    turn = _obs(yaw=0.42, embedding=[1.0] + [0.0] * 127)
    ret = _obs(yaw=-0.01, embedding=[1.0] + [0.0] * 127)

    with patch(
        "app.services.face_liveness.detect_and_observe",
        side_effect=[center, turn, ret],
    ):
        result = validate_liveness_sequence(
            db,
            challenge_id=challenge.id,
            employee=employee,
            center_bytes=b"a",
            turn_bytes=b"b",
            return_bytes=b"c",
            consume=True,
        )

    assert result.liveness_passed is True
    assert result.match_score >= 0.45
    assert challenge.consumed_at is not None
    db.commit.assert_called()


def _challenge_mock(*, direction: str = "turn_left"):
    challenge = MagicMock()
    challenge.id = uuid.uuid4()
    challenge.employee_id = uuid.uuid4()
    challenge.direction = direction
    challenge.consumed_at = None
    challenge.expires_at = datetime.now(timezone.utc) + timedelta(seconds=60)
    return challenge


def test_observe_center_ready_does_not_consume():
    db = MagicMock()
    challenge = _challenge_mock(direction="turn_right")
    db.get.return_value = challenge
    db.query.return_value.filter.return_value.first.return_value = MagicMock(id=1)

    employee = MagicMock()
    employee.id = challenge.employee_id
    obs = _obs(yaw=0.05)

    with patch(
        "app.services.face_liveness.detect_and_observe",
        return_value=obs,
    ):
        result = observe_pose(
            db,
            challenge_id=challenge.id,
            employee=employee,
            step="center",
            frame_bytes=b"frame",
        )

    assert result.ready is True
    assert result.reason_code is None
    assert challenge.consumed_at is None
    db.commit.assert_not_called()


def test_observe_center_not_ready_when_turned():
    db = MagicMock()
    challenge = _challenge_mock()
    db.get.return_value = challenge
    db.query.return_value.filter.return_value.first.return_value = MagicMock(id=1)

    employee = MagicMock()
    employee.id = challenge.employee_id

    with patch(
        "app.services.face_liveness.detect_and_observe",
        return_value=_obs(yaw=0.40),
    ):
        result = observe_pose(
            db,
            challenge_id=challenge.id,
            employee=employee,
            step="center",
            frame_bytes=b"frame",
        )

    assert result.ready is False
    assert result.reason_code == "pose_not_centered"


def test_observe_turn_ready_for_correct_direction():
    db = MagicMock()
    challenge = _challenge_mock(direction="turn_left")
    db.get.return_value = challenge
    db.query.return_value.filter.return_value.first.return_value = MagicMock(id=1)

    employee = MagicMock()
    employee.id = challenge.employee_id

    with patch(
        "app.services.face_liveness.detect_and_observe",
        return_value=_obs(yaw=-0.40),
    ):
        result = observe_pose(
            db,
            challenge_id=challenge.id,
            employee=employee,
            step="turn",
            frame_bytes=b"frame",
        )

    assert result.ready is True
    assert result.direction == "turn_left"


def test_observe_turn_wrong_direction():
    db = MagicMock()
    challenge = _challenge_mock(direction="turn_left")
    db.get.return_value = challenge
    db.query.return_value.filter.return_value.first.return_value = MagicMock(id=1)

    employee = MagicMock()
    employee.id = challenge.employee_id

    with patch(
        "app.services.face_liveness.detect_and_observe",
        return_value=_obs(yaw=0.40),
    ):
        result = observe_pose(
            db,
            challenge_id=challenge.id,
            employee=employee,
            step="turn",
            frame_bytes=b"frame",
        )

    assert result.ready is False
    assert result.reason_code == "turn_wrong_direction"


def test_observe_rejects_expired_challenge():
    db = MagicMock()
    challenge = _challenge_mock()
    challenge.expires_at = datetime.now(timezone.utc) - timedelta(seconds=5)
    db.get.return_value = challenge

    employee = MagicMock()
    employee.id = challenge.employee_id

    with pytest.raises(LivenessError) as exc:
        observe_pose(
            db,
            challenge_id=challenge.id,
            employee=employee,
            step="center",
            frame_bytes=b"frame",
        )
    assert exc.value.detail["code"] == "challenge_expired"


def test_observe_multiple_faces_not_ready():
    db = MagicMock()
    challenge = _challenge_mock()
    db.get.return_value = challenge
    db.query.return_value.filter.return_value.first.return_value = MagicMock(id=1)

    employee = MagicMock()
    employee.id = challenge.employee_id
    obs = _obs(yaw=0.0)
    obs = FaceObservation(
        embedding=obs.embedding,
        score=obs.score,
        yaw=obs.yaw,
        left_eye=obs.left_eye,
        right_eye=obs.right_eye,
        nose=obs.nose,
        box=obs.box,
        face_count=2,
    )

    with patch(
        "app.services.face_liveness.detect_and_observe",
        return_value=obs,
    ):
        result = observe_pose(
            db,
            challenge_id=challenge.id,
            employee=employee,
            step="center",
            frame_bytes=b"frame",
        )

    assert result.ready is False
    assert result.reason_code == "multiple_faces"
