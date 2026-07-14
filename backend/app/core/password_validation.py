import re

PASSWORD_MIN_LENGTH = 8
_HAS_UPPERCASE = re.compile(r"[A-Z]")
_HAS_SPECIAL = re.compile(r"[!@#$%^&*(),.?\":{}|<>_\-+=\[\]\\;/'`~]")


def validate_password_strength(password: str) -> None:
    if len(password) < PASSWORD_MIN_LENGTH:
        raise ValueError("Password must be at least 8 characters")
    if not _HAS_UPPERCASE.search(password):
        raise ValueError("Password must contain at least one uppercase letter")
    if not _HAS_SPECIAL.search(password):
        raise ValueError("Password must contain at least one special character")
