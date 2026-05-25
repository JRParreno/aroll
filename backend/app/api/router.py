from fastapi import APIRouter

from app.api import admin, auth, businesses, employees, registrations

api_router = APIRouter(prefix="/api/v1")
api_router.include_router(auth.router)
api_router.include_router(registrations.router)
api_router.include_router(admin.router)
api_router.include_router(employees.router)
api_router.include_router(businesses.router)
