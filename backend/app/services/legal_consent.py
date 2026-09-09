"""Per-business consent webpage helpers and employee consent persistence."""

from __future__ import annotations

import html
from datetime import datetime, timezone

from fastapi import HTTPException, Request
from fastapi.responses import HTMLResponse

from app.models.business import Business
from app.models.employee import Employee

LEGAL_CONSENT_PATH_PREFIX = "/legal/b/"
LEGAL_CONSENT_API_PAGE_SUFFIX = "/page"
MAX_LEGAL_CONSENT_CHARS = 50_000


def legal_consent_path(business_code: str) -> str:
    return f"{LEGAL_CONSENT_PATH_PREFIX}{business_code.strip().upper()}"


def legal_consent_url_for(business: Business) -> str:
    return business.legal_consent_url or legal_consent_path(business.business_code)


def ensure_legal_consent_url(business: Business) -> str:
    path = legal_consent_path(business.business_code)
    if business.legal_consent_url != path:
        business.legal_consent_url = path
    return path


def legal_consent_api_page_path(business_code: str) -> str:
    code = business_code.strip().upper()
    return f"/api/v1/public/legal/{code}{LEGAL_CONSENT_API_PAGE_SUFFIX}"


def absolute_legal_page_url(request: Request, business_code: str) -> str:
    base = str(request.base_url).rstrip("/")
    return f"{base}{legal_consent_api_page_path(business_code)}"


def require_employee_legal_consent(employee: Employee) -> None:
    if not bool(employee.legal_consent_accepted):
        raise HTTPException(
            status_code=403,
            detail={
                "code": "legal_consent_required",
                "message": (
                    "Please review and agree to your workplace consent page "
                    "before continuing."
                ),
            },
        )


def record_employee_legal_consent(employee: Employee) -> None:
    if employee.legal_consent_accepted:
        return
    employee.legal_consent_accepted = True
    employee.legal_consent_accepted_at = datetime.now(timezone.utc)


def default_legal_consent_content(
    business_name: str,
    *,
    is_demo: bool = False,
) -> str:
    name = business_name.strip() or "this workplace"
    demo_note = ""
    if is_demo:
        demo_note = (
            "\n\nThis Demo account does not collect live camera images or "
            "phone GPS for attendance. Demo Time In / Time Out uses the "
            "seeded research identity and the fictional worksite."
        )
    return (
        f"{name} — Terms, Privacy, and Biometric Consent\n\n"
        f"This page is configured by {name} for the Aroll+ attendance and "
        "payroll app.\n\n"
        "By tapping I agree, you confirm that you have read this page and "
        "consent to:\n"
        "• Using Aroll+ for attendance, scheduling, and payroll\n"
        "• Face enrollment and face-based Time In / Time Out on live accounts\n"
        "• Workplace location checks during live attendance"
        f"{demo_note}\n\n"
        "If you have questions, contact your supervisor or Aroll+ support."
    )


def fallback_unpublished_content(business_name: str) -> str:
    name = business_name.strip() or "This workplace"
    return (
        f"{name} has not published a consent page yet. Please contact your "
        "employer before using face enrollment or live attendance."
    )


def resolve_legal_content(business: Business) -> str:
    content = (business.legal_consent_content or "").strip()
    if content:
        return content
    return fallback_unpublished_content(business.name)


def render_legal_html_page(business: Business) -> HTMLResponse:
    title = html.escape(f"{business.name} — Consent")
    name = html.escape(business.name)
    code = html.escape(business.business_code)
    body = html.escape(resolve_legal_content(business)).replace("\n", "<br>\n")
    markup = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{title}</title>
  <style>
    :root {{ color-scheme: light; }}
    body {{
      margin: 0;
      font-family: system-ui, -apple-system, Segoe UI, sans-serif;
      background: #F4F6F8;
      color: #111827;
    }}
    main {{
      max-width: 40rem;
      margin: 0 auto;
      padding: 1.5rem 1.25rem 3rem;
    }}
    .card {{
      background: #fff;
      border: 1px solid #E5E7EB;
      border-radius: 1.25rem;
      padding: 1.5rem;
      box-shadow: 0 1px 2px rgba(15, 23, 42, 0.06);
    }}
    .kicker {{
      font-size: 0.75rem;
      letter-spacing: 0.14em;
      text-transform: uppercase;
      color: #6B7280;
      font-weight: 600;
    }}
    h1 {{
      margin: 0.5rem 0 0.75rem;
      font-size: 1.5rem;
      line-height: 1.25;
    }}
    .meta {{ margin: 0 0 1.25rem; color: #6B7280; font-size: 0.875rem; }}
    .body {{ font-size: 0.95rem; line-height: 1.7; color: #111827; }}
  </style>
</head>
<body>
  <main>
    <section class="card">
      <p class="kicker">Workplace consent</p>
      <h1>{name}</h1>
      <p class="meta">Business code {code}</p>
      <div class="body">{body}</div>
    </section>
  </main>
</body>
</html>
"""
    return HTMLResponse(markup)
