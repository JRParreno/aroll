"""Push delivery is optional and must not undo inbox writes."""

from unittest.mock import MagicMock, patch
from uuid import uuid4

from app.models.device_push_token import DevicePushToken
from app.models.notification import Notification
from app.services import push_delivery
from app.services.notifications import create_notification


def test_deliver_skips_when_fcm_not_configured():
    notification = Notification(
        id=uuid4(),
        recipient_user_id=uuid4(),
        recipient_role="employee",
        type="overtime_approved",
        title="Overtime Approved",
        message="Your overtime was approved.",
    )
    with patch.object(push_delivery, "fcm_configured", return_value=False):
        result = push_delivery.deliver_notification_push(MagicMock(), notification)
    assert result["skipped"] is True
    assert result["attempted"] == 0


def test_invalid_token_is_removed_and_does_not_block_others():
    user_id = uuid4()
    good = DevicePushToken(
        id=uuid4(), user_id=user_id, token="good-token", platform="android"
    )
    bad = DevicePushToken(
        id=uuid4(), user_id=user_id, token="bad-token", platform="android"
    )
    db = MagicMock()
    notification = Notification(
        id=uuid4(),
        recipient_user_id=user_id,
        recipient_role="employee",
        type="schedule_assigned",
        title="New Schedule",
        message="You have a new shift.",
    )
    with (
        patch.object(push_delivery, "fcm_configured", return_value=True),
        patch.object(push_delivery, "tokens_for_user", return_value=[bad, good]),
        patch.object(
            push_delivery,
            "_send_fcm",
            side_effect=lambda token, _n: "invalid" if token == "bad-token" else None,
        ),
    ):
        result = push_delivery.deliver_notification_push(db, notification)
    assert result["attempted"] == 2
    assert result["invalid_removed"] == 1
    db.delete.assert_called_once_with(bad)


def test_create_notification_survives_push_failure():
    db = MagicMock()
    with patch(
        "app.services.push_delivery.deliver_notification_push",
        side_effect=RuntimeError("fcm down"),
    ):
        row = create_notification(
            db,
            recipient_user_id=uuid4(),
            recipient_role="employee",
            type="overtime_submitted",
            title="Overtime Submitted",
            message="Awaiting approval.",
            commit=True,
        )
    assert row.title == "Overtime Submitted"
    db.add.assert_called()
    db.commit.assert_called()
