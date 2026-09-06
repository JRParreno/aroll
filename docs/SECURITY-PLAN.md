# Aroll+ Deployment Security Plan

**Related:** [SOLUTION.md](SOLUTION.md) · [FACE-RECOGNITION.md](FACE-RECOGNITION.md) · [DATABASE-ERD.md](DATABASE-ERD.md) · [SYSTEM-WORKFLOWS.md](SYSTEM-WORKFLOWS.md) · [legal/](legal/) (Terms, Privacy Policy, Biometric Consent)

**Scope:** Staging (UAT) → pilot production for the study’s small businesses  
**Stack:** Flutter mobile, React admin web, FastAPI, PostgreSQL + pgvector  
**Out of scope for MVP:** Face ID–style Secure Enclave encryption; enterprise SOC 2 / full pen-test program

This document is the **security plan for deployment**. Application-level controls (JWT, RBAC, tenancy, face + liveness + geofence) are already designed in the system docs; this plan states what must be true **before and after go-live**.

---

## 1. Objectives

1. Protect account credentials and JWT sessions.
2. Keep each business’s data isolated (`business_id` tenancy).
3. Protect biometric-related data (embeddings; no long-term raw face photos).
4. Reduce attendance fraud (face match + Strong liveness + geofence).
5. Support pilot ops with PH **Data Privacy Act** basics (consent, purpose limitation, retention/deletion).

---

## 2. Threat model (what we defend against)

| Threat | Mitigation |
|--------|------------|
| Stolen / weak password | bcrypt hashes; password strength rules; forced change after temporary password |
| Token theft from device | FlutterSecureStorage; HTTPS only; finite JWT expiry (`ACCESS_TOKEN_EXPIRE_MINUTES`) |
| Cross-business data leak | JWT `business_id` + query filters; RBAC via `require_roles` |
| Buddy punching / still-photo spoof | Face match + **Strong** head-turn liveness (server-validated) + geofence |
| Unauthorized admin / owner actions | Role gates: `platform_admin`, `owner`, `manager`, `employee` |
| Secret leakage in git or logs | Never commit `.env`; rotate `JWT_SECRET` if exposed |
| Overly open CORS in production | Explicit `CORS_ORIGINS`; `CORS_ALLOW_LOCALHOST_REGEX=false` |

**Accepted residual risk:** Pre-recorded video of a valid head-turn sequence or advanced deepfake may still pass Strong liveness. Documented in [FACE-RECOGNITION.md](FACE-RECOGNITION.md) § Security limits. Stronger anti-spoof ML can be added later without changing the multipart API contract.

---

## 3. Security controls (by layer)

### 3.1 Transport

- All client → API traffic over **HTTPS** in staging and production.
- Admin web served over HTTPS.
- No production client configured with `http://` API bases.

### 3.2 Authentication

- Email + password login; API issues **JWT** with `sub`, `role`, and `business_id`.
- Passwords stored with **bcrypt** (`app.core.security`).
- Change-password enforces strength (min length, uppercase, special character).
- Employees provisioned by owner/manager with a **one-time temporary password**; `must_change_password` until changed.
- **No employee self-registration.**

### 3.3 Authorization & tenancy

- **RBAC:** platform admin (registrations), owner/manager (tenant ops), employee (own data + clock-in).
- Every operational query scoped by the authenticated user’s `business_id` (except platform-admin registration endpoints).
- Platform admin does not use day-to-day payroll of tenant businesses as a normal path.

### 3.4 Mobile / web clients

- Mobile JWT in **FlutterSecureStorage** (not plaintext prefs).
- Admin web sends `Authorization: Bearer <token>` on API calls.
- Production builds use production `API_BASE_URL` / API host only.

### 3.5 Attendance anti-fraud

- Clock-in with face: server verifies identity embeddings; **no client-trusted `liveness_passed` flag**.
- Prefer **Strong** (head-turn) liveness for production attendance; Quick (blink/smile) is client-assisted and weaker.
- Geofence: Haversine vs primary `business_location`; reject outside `geofence_radius_m`.

### 3.6 Biometric data

- Store **512-d ArcFace embeddings** in `employee_face_embedding` (pgvector).
- Do **not** retain raw enrollment images long-term (design principle in [DATABASE-ERD.md](DATABASE-ERD.md)).
- Match is 1:1 against the logged-in employee’s gallery (not open-set search across all tenants).
- Clear embeddings on face reset / offboarding flows when used.

> **Not Face ID:** Templates live in the application database for server-side matching. This is **not** hardware-backed Secure Enclave encryption.

---

## 4. Environment configuration (deploy)

| Setting | Development | Staging / Production |
|---------|-------------|----------------------|
| `JWT_SECRET` | Local default OK | Unique long random string (never the repo default) |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | Convenient (e.g. 480) | Same or shorter per pilot policy |
| `CORS_ALLOW_LOCALHOST_REGEX` | `true` | **`false`** |
| `CORS_ORIGINS` | Local Vite ports | Exact deployed admin/owner web origins only |
| `DATABASE_URL` | Local Docker | Private network; strong DB password; no public `5432` |
| HTTPS | Optional | **Required** |
| Seed / demo accounts | Allowed | Disable or change all default passwords |
| Face thresholds | Tunable | Freeze after UAT (`FACE_MATCH_THRESHOLD`, etc.) |

Reference: `backend/.env.example`.

---

## 5. Pre-deploy checklist

Complete on **staging** before promoting to pilot production.

### Infrastructure

- [ ] TLS/HTTPS on API and admin web
- [ ] Postgres not exposed publicly; backups enabled; one restore drill done
- [ ] Strong unique `JWT_SECRET`
- [ ] `CORS_ALLOW_LOCALHOST_REGEX=false`
- [ ] `CORS_ORIGINS` lists only production web origins
- [ ] Registration upload directory writable only by the API process
- [ ] Hosting secrets stored in the platform secret store (not in the repo)

### Application verification

- [ ] Login issues JWT; inactive users rejected
- [ ] Role-restricted routes return 403 for wrong roles
- [ ] Tenant A cannot read tenant B employees / attendance / payroll
- [ ] Temp password + forced change works end-to-end
- [ ] `clock-in-face` requires Strong liveness + geofence on staging
- [ ] Face embeddings created on enroll; raw images not kept long-term

### Privacy (pilot)

- [ ] Fill placeholders in [legal/](legal/) (`[ORGANIZATION NAME]`, contacts, dates)
- [ ] Employee signs [legal/BIOMETRIC-CONSENT.md](legal/BIOMETRIC-CONSENT.md) before face enrollment
- [ ] Users can access [legal/PRIVACY-POLICY.md](legal/PRIVACY-POLICY.md) and [legal/TERMS-AND-CONDITIONS.md](legal/TERMS-AND-CONDITIONS.md)
- [ ] Owners briefed on who may enroll / clear faces
- [ ] ArcFace / InsightFace weights: academic thesis OK; commercial deployment needs a proper license or model swap ([FACE-RECOGNITION.md](FACE-RECOGNITION.md))

---

## 6. Operational access

| Role | Allowed in production |
|------|------------------------|
| Platform admin | Approve/reject business registrations; platform dashboards |
| Owner / manager | Workforce, shifts, enrollment, payroll **within own business** |
| Employee | Own attendance, payslips; face clock-in |
| Hosting operator | Server/DB/console with least privilege; MFA on host account where available |

**Rule:** Do not share platform-admin credentials with pilot business staff.

---

## 7. Biometric lifecycle (deployment policy)

1. **Collect** — enrollment after written/recorded consent.
2. **Process** — detect → align → ArcFace embedding on server.
3. **Store** — vectors in Postgres only.
4. **Use** — clock-in/out verification for that employee.
5. **Share** — never across businesses; never for marketing.
6. **Delete** — remove embeddings when employment ends or face is cleared.

---

## 8. Incident response (pilot-scale)

| Event | Immediate action |
|-------|------------------|
| Suspected account compromise | Set `is_active=false`; force password reset; review recent attendance for that user |
| `JWT_SECRET` leaked | Rotate secret (invalidates all sessions); redeploy API; notify operators |
| Spoof / buddy-punch report | Confirm Strong liveness only; consider raising face thresholds; re-enroll if needed |
| Suspected DB exposure | Snapshot DB; rotate DB password + JWT; notify affected business owners (DPA good practice) |

Keep a short log: date, event, actions, who was notified.

---

## 9. Go-live sequence

1. Deploy **staging** with production-like env flags (section 4).
2. Complete the checklist (section 5).
3. UAT with one business: login → enroll face → clock-in-face → payroll view.
4. Freeze face thresholds and env config.
5. Deploy **production**; onboard remaining pilot businesses with consent forms.
6. Monitor structured errors: failed login, `outside_geofence`, `face_mismatch`, `challenge_expired` / `challenge_used`, `identity_changed`.

---

## 10. Thesis / Chapter 4 wording (suggested)

> Aroll+ deployment security relies on HTTPS, JWT authentication, role-based access control, multi-tenant data isolation, bcrypt password hashing, secure mobile token storage, and attendance anti-fraud via face embeddings, server-validated liveness, and geofencing. Biometric templates are stored as vectors without long-term raw face images. Hardware-backed Face ID encryption is out of scope; residual spoofing risk from video replay is acknowledged as a limitation.

---

## 11. Document ownership

| Item | Owner |
|------|--------|
| This plan | Project team / thesis authors |
| Env secrets & hosting | Deployment operator |
| Consent forms & employee briefing | Pilot business owners (with team guidance) |
| Face threshold tuning | Team after UAT |
