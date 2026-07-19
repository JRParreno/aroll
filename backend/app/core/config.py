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
    # Cosine similarity threshold for face match. Higher = stricter (fewer
    # false accepts, more "try again" for genuine people in bad lighting).
    # Scale is model-specific. For ArcFace R50 (arcface_r50_v1) we score the
    # *mean* similarity across all enrolled samples (not the single best), which
    # is stricter against lookalikes. Close siblings have scored ~0.77 on the
    # old "best sample" rule; mean scoring + default 0.78 rejects that band
    # while a clear genuine capture (~0.80–0.85) still passes. Raise toward
    # 0.82 if lookalikes still pass; lower toward 0.70 if genuine people fail
    # in poor lighting (prefer re-enrolling clear samples first).
    face_match_threshold: float = 0.78
    face_model_version: str = "arcface_r50_v1"
    face_min_enrollment_samples: int = 3
    face_max_enrollment_samples: int = 5
    # One-time head-turn challenge settings.
    face_liveness_challenge_ttl_seconds: int = 90
    # Absolute yaw proxy (nose offset / inter-eye distance) for a front-facing frame.
    face_liveness_center_yaw_max: float = 0.18
    # Minimum absolute yaw for the instructed turn frame.
    face_liveness_turn_yaw_min: float = 0.28
    # Minimum absolute yaw delta between center and turn frames.
    face_liveness_turn_delta_min: float = 0.22
    # Cosine similarity required between consecutive challenge frames (same person).
    face_liveness_continuity_threshold: float = 0.40

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
