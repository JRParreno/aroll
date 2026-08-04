"""Helpers to capture platform / device / IP for audit logs."""

from __future__ import annotations

from fastapi import Request


def audit_meta_from_request(request: Request | None) -> dict[str, str | None]:
    if request is None:
        return {"platform": None, "device": None, "ip_address": None}
    platform = request.headers.get("X-Client-Platform") or request.headers.get(
        "X-Platform"
    )
    device = request.headers.get("X-Client-Device") or request.headers.get(
        "User-Agent"
    )
    if device and len(device) > 120:
        device = device[:120]
    ip = request.client.host if request.client else None
    forwarded = request.headers.get("X-Forwarded-For")
    if forwarded:
        ip = forwarded.split(",")[0].strip()
    return {"platform": platform, "device": device, "ip_address": ip}
