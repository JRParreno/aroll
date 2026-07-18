from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    database_url: str = "postgresql://aroll:aroll@localhost:5432/aroll"
    jwt_secret: str = "dev-secret-change-in-production"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 480
    cors_origins: str = (
        "http://localhost:5173,http://127.0.0.1:5173,"
        "http://localhost:5174,http://127.0.0.1:5174,"
        "http://localhost:5175,http://127.0.0.1:5175,"
        "http://localhost:4173,http://127.0.0.1:4173"
    )
    # Development-only: when true, allows any http(s) localhost/127.0.0.1 origin via regex.
    # Set to false in production and list explicit origins in CORS_ORIGINS instead.
    cors_allow_localhost_regex: bool = True
    registration_upload_dir: str = "uploads/registrations"
    # Cosine similarity threshold for face match. SFace's published
    # same-identity threshold is 0.363 cosine similarity (OpenCV zoo).
    face_match_threshold: float = 0.363
    face_model_version: str = "sface_v3"
    face_min_enrollment_samples: int = 3
    face_max_enrollment_samples: int = 5

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    @property
    def cors_origin_regex(self) -> str | None:
        if not self.cors_allow_localhost_regex:
            return None
        # Dev-only wildcard for local Vite/Flutter web ports.
        return r"https?://(localhost|127\.0\.0\.1)(:\d+)?"


settings = Settings()
