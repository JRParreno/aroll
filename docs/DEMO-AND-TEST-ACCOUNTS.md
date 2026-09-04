# Demo and Developer/Test accounts

AROLL+ has **two seeded tenants** plus the existing platform admin. They are not interchangeable.

| Account | Business code | Purpose | Use in defense / research evaluation? |
|---|---|---|---|
| **AROLL+ Demo Café** | `DEMO01` | Simulated research/presentation data | **Yes** |
| **AROLL+ Dev Lab** | `DEVTEST` | Internal technical testing | **No** |
| **Platform admin** | _(no business)_ | Approve real/test registrations | Not a café/lab employee |

`python -m app.seed` (from `backend/` with the venv active) is idempotent: it will not duplicate `DEMO01` or `DEVTEST`, and it will not convert other businesses into Demo.

Emails use `example.com` because the existing owner-login schema (`EmailStr`) rejects reserved TLDs such as `.test`. These addresses are fictional local-dev identifiers, not real people.

---

## DEMO01 — AROLL+ Demo Café

**Purpose:** Defense/research evaluation only.

`is_demo = true`  
`is_internal_test = false`

Uses:

- fictional employees (Hannah Cruz, Luis Mercado)
- fictional positions and sample rates
- seeded schedules and attendance (on-time, late, absent, completed Time In/Out)
- sample payroll adjustments (deduction + allowance)
- synthetic/test face embeddings (not photographs of real people)
- a **fictional** worksite pin (`100 Demo Street, Sample City`)

Does **not** use:

- a research participant’s live face
- live camera enrollment (blocked; seeded embeddings stay in place)
- real participant GPS (the server substitutes the fictional worksite pin)
- real payroll/salary release
- the Developer/Test tenant

### Phase 2 technical behavior

Identity and location are decided **only** from the authenticated `DEMO01` business record (`business.is_demo`). Clients cannot turn this on with `is_demo`, `mode=demo`, or similar fields.

**Face**

1. The logged-in seeded employee (Hannah Cruz or Luis Mercado) is resolved against that employee’s **already-seeded synthetic embeddings**.
2. YuNet / ArcFace are **not** run on a live camera probe. Phase 1 generated JPEGs are often not YuNet-detectable; demo Time In/Out does not depend on those images.
3. The surrounding attendance workflow still runs: identity result → geofence validation → attendance row under `DEMO01`.
4. `POST /employee/face-samples` and owner `POST /employees/{id}/face-samples` return **403** `demo_enrollment_locked`. Seeded embeddings are not deleted or overwritten. Owner delete of face samples is also locked.

**GPS**

1. Client-supplied latitude/longitude are ignored.
2. The server loads the authenticated demo business’s primary worksite coordinates (`14.5500000, 121.0000000`).
3. Those coordinates are passed through the **existing** geofence check (unchanged math).
4. Attendance `latitude_in` / `longitude_in` (and out) store the fictional worksite, not a participant device location.

Seeded historical attendance/payroll rows remain synthetic. Today’s shifts are left **open** so a live demo Time In/Out can run.

**Intended use:** defense / research demonstration of the attendance pipeline with simulated data only.

### Logins

| Role | Email | Business code |
|---|---|---|
| Demo Owner | `owner.demo@example.com` | `DEMO01` |
| Demo Manager | `manager.demo@example.com` | `DEMO01` |
| Demo Employee 01 (Hannah Cruz) | `employee.demo01@example.com` | _(employee login — no business code)_ |
| Demo Employee 02 (Luis Mercado) | `employee.demo02@example.com` | _(employee login — no business code)_ |

Owner/manager: admin-web or mobile **business owner** login with code `DEMO01`.  
Employees: mobile **employee** login with email + the local seed password.

Local seed password (development only): `DemoCafe!23`

Setup and first-password-change are already completed for these accounts so they are not trapped in onboarding.

---

## DEVTEST — AROLL+ Dev Lab

**Purpose:** Internal development/testing only.

`is_demo = false`  
`is_internal_test = true`

**DEVTEST will NOT be used during the defense/research participant evaluation.**

This tenant exists so the development team can later exercise the **real** pipeline:

- device camera
- live face enrollment
- liveness detection
- ArcFace matching
- actual device GPS
- geofence validation
- Time In / Time Out

It is **not** a Demo Employee under Demo Café. It has **no** seeded demo faces, demo attendance, or demo payroll rows. The test employee starts as `face_registration_status = not_registered`.

### Phase 2 technical behavior

`is_internal_test = true` does **not** enable the DEMO01 shortcuts. DEVTEST keeps the production pipeline so developers can exercise the real implementation:

- live camera enrollment (`POST /employee/face-samples` is **not** demo-locked)
- live face match + liveness on Time In / Time Out
- actual device GPS (no fictional DEMO01 pin substitution)
- existing geofence validation
- existing mock-GPS rejection on the mobile client (`LocationMockException`)

DEVTEST must not be used for research participant evaluation or for defense demonstration. It must not read or write DEMO01 embeddings, attendance, or payroll.

### Logins

| Role | Email | Business code |
|---|---|---|
| Developer/Test Owner | `owner.dev@example.com` | `DEVTEST` |
| Developer/Test Employee | `employee.dev@example.com` | _(employee login)_ |

Local seed password (development only): `DevLab!23`

---

## Platform admin (unchanged)

| Email | Role |
|---|---|
| `admin@example.com` | Platform admin (`business_id` is null) |

Password: see [PROJECT-SETUP.md](PROJECT-SETUP.md) (`changeme123` on a fresh seed).

This account is **not** Demo Café and **not** Dev Lab. The admin-web login copy that says “Demo admin” refers to this platform administrator, not `DEMO01`.

---

## Session flags

`GET /auth/me` (and login token payloads) expose:

- `is_demo` — true only when the user’s business is `DEMO01`
- `is_internal_test` — true only when the user’s business is `DEVTEST`

The client cannot opt into Demo Mode. There is no `?demo=true` or `X-Demo-Mode` header. Flags come from `user.business_id` → `business.is_demo` / `business.is_internal_test`.

---

## Ordinary businesses

For `is_demo = false` and `is_internal_test = false`, production behavior is unchanged:

```text
Live camera → face detection → liveness → face verification → real GPS → geofence → attendance
```

There is no generic bypass. Face enrollment, live match, device GPS, geofence math, mock-GPS rejection, and payroll formulas are the original production paths.

---

## Isolation rule

```text
DEMO ACCOUNT  ≠  DEVELOPER/TEST ACCOUNT  ≠  PLATFORM ADMIN
```

All employees, attendance, payroll adjustments, face embeddings, and locations for Demo Café belong to `DEMO01`. Dev Lab rows belong only to `DEVTEST`.

---

## Phase 3 — UI and research safeguards

Presentation-only. Face recognition, GPS substitution, enrollment lock, geofence math, and payroll formulas are unchanged from Phase 2.

### DEMO01

Visible when the authenticated session has `is_demo = true` (never from `?demo=true` or a localStorage toggle):

- Persistent **DEMO MODE** banner naming AROLL+ Demo Café and stating that records are simulated/demo data
- Prototype notice: simulated employee, attendance, payroll, biometric, and workplace-location data; not used for employment decisions, discipline, or salary payment
- Employees labeled **Demo Employee** / **Simulated**
- Attendance rows labeled **SIMULATED**
- Payroll titled **Sample Payroll**; payslip preview, on-screen payslip, and generated PDF show **SAMPLE — DEMONSTRATION ONLY** / **NOT FOR ACTUAL SALARY PAYMENT**
- Demo attendance explains that a seeded identity and fictional location are used; **no camera or personal GPS** is required
- Face enrollment remains locked (Phase 2). The employee app does not send DEMO01 users to face registration
- 18+ voluntary-participation attestation at DEMO01 login (owner web workspace and mobile app). Acknowledgement is UI-only for the current session; it does not grant demo behavior
- Platform admin approved-business list and detail show a read-only **DEMO** badge for Demo Café (and **INTERNAL TEST** for Dev Lab). These flags cannot be toggled from the client.

**DEMO01 is not an actual employee payroll environment and its records must not be interpreted as real employment or salary records.**

### DEVTEST

Visible when `is_internal_test = true`:

- **DEVELOPER TEST MODE** banner: internal technical testing only; not for defense/research demonstration
- No DEMO01 sample-payroll / SAMPLE payslip labeling
- Live camera enrollment, live face attendance, and real device GPS remain available

### Ordinary businesses

No demo banner, no internal-test banner, no sample payslip watermark. Production wording and workflows are unchanged.

### 18+ research evaluation

There is no separate participant-signup product flow. Defense/research evaluation uses the seeded DEMO01 logins. The 18+ checkbox and voluntary/non-retaliation wording appear when a DEMO01 session is first opened. DEVTEST and ordinary businesses do not see this gate. No date of birth or identity documents are collected.

Acknowledgement is stored only as a session UI flag (`sessionStorage` on admin-web; in-memory `AppState` on mobile). It is cleared on logout. It is **not** a source of truth for demo behavior.

### Security (unchanged)

Clients cannot opt into DEMO01 by sending `is_demo`, `mode=demo`, query params, or localStorage. Attendance, enrollment lock, GPS substitution, and sample-payslip PDF labeling are decided from the authenticated business record (`business.is_demo`). Platform admin `GET /admin/businesses` exposes the same flags as **read-only display fields**; they cannot be patched by the client.
