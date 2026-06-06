from sqlalchemy.orm import Session
from app.models.activity_log import ActivityLog


def create_log(
    db: Session,
    user_id,
    action: str,
    description: str | None = None,
):
    log = ActivityLog(
        user_id=user_id,
        action=action,
        description=description,
    )

    db.add(log)
    db.commit()
    db.refresh(log)

    return log