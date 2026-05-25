# W1 — Data Requirements (Aroll+)

**Status:** Locked for implementation (May 2026)  
**Pilot businesses:** Mr. Bean Cafe, Ugom Cafe, Pande Doc, Benzon Burger House

---

## 1. Roles and capabilities

| Capability | Platform admin | Owner | Manager | Employee |
|------------|:--------------:|:-----:|:-------:|:--------:|
| Approve business registration | Yes | — | — | — |
| Configure payroll rules | — | Yes | Yes* | — |
| Provision employee (temp password) | — | Yes | Yes | — |
| CRUD employees | — | Yes | Yes | — |
| Manual attendance (interim) | — | Yes | Yes | — |
| Clock in/out (face, later) | — | — | — | Yes |
| View own payslip | — | — | — | Yes |

\*Manager: same as owner on web for MVP unless restricted later.

---

## 2. Employee onboarding (confirmed)

1. Owner/manager creates employee on **web** (`POST /employees`).
2. System generates **one-time temporary password** (shown once to owner).
3. Employee logs in on **Flutter** with email + temp password.
4. Employee **must change password** before other screens (`must_change_password`).
5. Face enrollment **deferred** to final implementation block.

No employee self-registration. Business ID is display-only for support, not used at signup.

---

## 3. Geofence (per business location)

| Parameter | Default | Range |
|-----------|---------|-------|
| `geofence_radius_m` | **75 m** | 20–200 m (owner-adjustable in UI) |
| Center | `latitude`, `longitude` on `business_location` | Required before attendance |
| `address` | Text for display only | Not used in distance check |

Timezone default: `Asia/Manila`.

---

## 4. Payroll rules (per business)

### 4.1 Pay period

| Type | Code | Notes |
|------|------|-------|
| Weekly | `weekly` | Reset records after weekly payday |
| Twice monthly | `semi_monthly` | 15th + end of month (prototype “15th Day”) |
| Monthly | `monthly` | Single payday per month |

### 4.2 Salary basis

| Field | Rule |
|-------|------|
| Position daily rate | e.g. ₱500/day (Cashier, Barista), ₱800/day (Manager) |
| Employee | Linked to `position_id`; gross day pay from daily rate × worked day rules |

### 4.3 Attendance-based adjustments (MVP)

| Rule | Default | Configurable |
|------|---------|--------------|
| Late deduction | **Enabled**, ₱**1.00**/minute late | Toggle + amount |
| Overtime pay | **Enabled**, ₱**1.00**/minute OT | Toggle + amount |
| Absent | **No pay** for day | Fixed |
| Under time | Pro-rated from daily rate × hours worked | Derived |
| On time | Full daily rate | Derived |

Custom named rules (“Add New Rule” in prototype): **Phase 2** — not MVP.

### 4.4 Government deductions

Document in thesis interviews; **not automated in MVP** (manual line in `breakdown_json` optional later).

---

## 5. Attendance remarks (enum mapping)

| UI label | `attendance_status` / remarks |
|----------|-------------------------------|
| On Time | `complete` + on_time flag in breakdown |
| Late | `late` |
| Under Time | `incomplete` |
| Over Time | `complete` + OT hours |
| Absent | `absent` |

Interim: owner/manager enters `time_in` / `time_out` on web until face clock-in ships.

---

## 6. Core entities (implementation priority)

| Entity | W2 schema | W3 API | W4 UI |
|--------|-----------|--------|-------|
| `business_registration` | Yes | Yes | Admin review |
| `business`, `business_location` | Yes | Yes | Owner setup |
| `user`, `employee` | Yes | Yes | Add employee |
| `position`, `business_payroll_config` | Yes | Partial | Setup wizard (later) |
| `shift`, `shift_assignment` | Yes | — | W5+ |
| `attendance_record` | Yes | Interim POST | W6+ |
| `payroll_run`, `payslip` | Yes | — | W8+ |
| `employee_face_embedding` | Yes (empty) | — | Face block |

---

## 7. References

- [DATABASE-ERD.md](DATABASE-ERD.md) — schema
- [SOLUTION.md](SOLUTION.md) — RBAC §3.2
- [SYSTEM-WORKFLOWS.md](SYSTEM-WORKFLOWS.md) — employee journey §4
