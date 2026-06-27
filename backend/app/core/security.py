import secrets
import string
from datetime import datetime, timedelta, timezone

from jose import JWTError, jwt
from passlib.context import CryptContext

from app.core.config import settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


def verify_user_password(
    plain: str,
    password_hash: str,
    *,
    pending_temporary_password: str | None = None,
    must_change_password: bool = False,
) -> tuple[bool, str | None]:
    """Verify a login password against bcrypt hash and optional pending temp password.

    Returns (is_valid, canonical_password). When canonical_password is set, callers
    should re-hash and persist it so future bcrypt checks succeed.
    """
    password = plain.strip()
    if not password:
        return False, None

    if verify_password(password, password_hash):
        return True, None

    if not must_change_password or not pending_temporary_password:
        return False, None

    if secrets.compare_digest(password, pending_temporary_password):
        return True, None

    # Generated temp passwords are uppercase (EMP-XXXXXX); accept case-insensitive entry.
    if secrets.compare_digest(
        password.upper(), pending_temporary_password.upper()
    ):
        return True, pending_temporary_password

    return False, None


def create_access_token(subject: str, extra: dict | None = None) -> str:
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=settings.access_token_expire_minutes
    )
    payload = {"sub": subject, "exp": expire}
    if extra:
        payload.update(extra)
    return jwt.encode(
        payload, settings.jwt_secret, algorithm=settings.jwt_algorithm
    )


def decode_access_token(token: str) -> dict | None:
    try:
        return jwt.decode(
            token, settings.jwt_secret, algorithms=[settings.jwt_algorithm]
        )
    except JWTError:
        return None


def generate_temporary_password(length: int = 6) -> str:
    """Generate a one-time employee password like EMP-8F2A91."""
    alphabet = string.ascii_uppercase + string.digits
    suffix = "".join(secrets.choice(alphabet) for _ in range(length))
    return f"EMP-{suffix}"
