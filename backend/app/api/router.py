from fastapi import APIRouter

from app.api import (
    admin,
    auth,
    businesses,
    employee_mobile,
    employees,
    holidays,
    owner_performance,
    owner_reports,
    positions,
    registrations,
    schedules,
    shifts,
)

api_router = APIRouter(prefix="/api/v1")
api_router.include_router(auth.router)
api_router.include_router(registrations.router)
api_router.include_router(admin.router)
api_router.include_router(employee_mobile.router)
api_router.include_router(employees.router)
api_router.include_router(businesses.router)
api_router.include_router(shifts.router)
api_router.include_router(schedules.router)
api_router.include_router(positions.router)
api_router.include_router(holidays.router)
api_router.include_router(owner_performance.router)
api_router.include_router(owner_reports.router)
