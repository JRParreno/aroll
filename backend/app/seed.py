"""Run: python -m app.seed (from backend/ with venv active)."""

from app.core.security import hash_password, verify_password
from app.db.base import Base
from app.db.session import SessionLocal, engine
from app.models.business import Business
from app.models.enums import UserRole
from app.models.user import User


def sync_owner_passwords() -> int:
    """Sync temp passwords for owners still on first login (must_change_password=True).

    Skips owners who already completed password change so seed/migrate does not
    reset custom passwords.
    """
    db = SessionLocal()
    try:
        owners = db.query(User).filter(User.role == UserRole.owner).all()
        updated = 0
        for owner in owners:
            if owner.business_id is None:
                continue
            business = db.get(Business, owner.business_id)
            if business is None:
                continue
            # Owner already completed first-time password change — never reset.
            if not owner.must_change_password:
                continue
            if verify_password(business.business_code, owner.password_hash):
                continue
            owner.password_hash = hash_password(business.business_code)
            owner.must_change_password = True
            updated += 1
        if updated:
            db.commit()
        return updated
    finally:
        db.close()


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
    count = sync_owner_passwords()
    if count:
        print(f"Synced {count} owner password(s) to business code")
