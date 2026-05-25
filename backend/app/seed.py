"""Run: python -m app.seed (from backend/ with venv active)."""

from app.core.security import hash_password
from app.db.base import Base
from app.db.session import SessionLocal, engine
from app.models.enums import UserRole
from app.models.user import User


def seed():
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        admin_email = "admin@example.com"
        admin = (
            db.query(User)
            .filter(User.role == UserRole.platform_admin)
            .first()
        )
        legacy = (
            db.query(User)
            .filter(User.email == "admin@aroll.test", User.role == UserRole.platform_admin)
            .first()
        )
        if legacy is not None:
            legacy.email = admin_email
            db.commit()
            print(f"Migrated platform admin email to {admin_email}")
        elif admin is None:
            db.add(
                User(
                    email=admin_email,
                    password_hash=hash_password("changeme123"),
                    role=UserRole.platform_admin,
                    business_id=None,
                    must_change_password=False,
                )
            )
            db.commit()
            print(f"Seeded platform admin: {admin_email} / changeme123")
        else:
            print(f"Platform admin already exists: {admin.email}")
    finally:
        db.close()


if __name__ == "__main__":
    seed()
