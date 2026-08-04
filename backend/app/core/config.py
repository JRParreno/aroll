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
    # Attendance identity is 1:1 (logged-in employee gallery only).
    # Decision: mean + min (+ centroid) cosine vs that gallery.
    #
    # Thresholds are InsightFace ArcFace (w600k_r50) 1:1 norms for a *correctly
    # aligned* face — not the collapsed ~0.9 band from the v1 landmark bug.
    # Typical ArcFace: same-person ≈ 0.4–0.8, different people usually < 0.35.
    # mean≥0.50 and min≥0.42 targets low FAR while accepting genuine live probes.
    face_match_threshold: float = 0.50
    face_min_match_threshold: float = 0.42
    # Kept for older callers / logs that still mention "best"; not the accept gate.
    face_best_match_threshold: float = 0.42
    # Enrollment frames of the same person (correct ArcFace scale).
    face_enrollment_consistency_min: float = 0.40
    face_model_version: str = "arcface_r50_v2"
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
