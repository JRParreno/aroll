import asyncio
import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.router import api_router
from app.core.config import settings

logger = logging.getLogger("aroll.reminders")


def _sync_official_consent_defaults() -> None:
    """Copy version-controlled consent defaults into unedited platform rows.

    Does not delete data, does not touch acceptance history, and does not
    replace a platform document an administrator has already edited.
    """
    from app.db.session import SessionLocal
    from app.services.legal_consent import ensure_platform_legal_defaults

    db = SessionLocal()
    try:
        ensure_platform_legal_defaults(db)
        db.commit()
    except Exception:
        db.rollback()
        logger.exception("official consent default sync failed")
    finally:
        db.close()


@asynccontextmanager
async def lifespan(_app: FastAPI):
    if not os.environ.get("PYTEST_CURRENT_TEST"):
        _sync_official_consent_defaults()
    stop = asyncio.Event()
    task: asyncio.Task | None = None
    if settings.schedule_reminder_loop_enabled and not os.environ.get(
        "PYTEST_CURRENT_TEST"
    ):

        async def _worker() -> None:
            try:
                await asyncio.wait_for(stop.wait(), timeout=30)
                return
            except asyncio.TimeoutError:
                pass
            while not stop.is_set():
                try:
                    from app.services.schedule_reminders import reminder_tick

                    await asyncio.to_thread(reminder_tick)
                except Exception:
                    logger.exception("schedule reminder loop failed")
                try:
                    await asyncio.wait_for(
                        stop.wait(),
                        timeout=max(60, settings.schedule_reminder_interval_seconds),
                    )
                    return
                except asyncio.TimeoutError:
                    continue

        task = asyncio.create_task(_worker())
    yield
    stop.set()
    if task is not None:
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass


app = FastAPI(
    title="Aroll+ API",
    description="Face recognition attendance and payroll system",
    version="0.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_origin_regex=settings.cors_origin_regex,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


app.include_router(api_router)


@app.get("/health")
def health():
    return {"status": "ok"}
