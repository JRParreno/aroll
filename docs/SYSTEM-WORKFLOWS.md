# Aroll+ System Workflows

**Related:** [SOLUTION.md](SOLUTION.md) · [DATABASE-ERD.md](DATABASE-ERD.md)

This document explains **how Aroll+ works** end-to-end using PlantUML diagrams. Use it alongside Chapter 3 for process descriptions and demo narration.

---

## 1. How the system works (overview)

At a high level, Aroll+ connects four user types to one shared backend. Employees prove identity with **face + liveness + GPS**; managers and owners run the business on **web dashboards**; a platform admin onboards new tenants.

```plantuml
@startuml System_Overview
title Figure 1 — How Aroll+ Works (Overview)

|Employee|
start
:Login (Flutter);
:Enroll face\n(if first time, by manager);
:Clock in:\nface + liveness + GPS;
:Work shift;
:Clock out;
:View attendance & payslip;
stop

|Manager|
start
:Login (Web or Flutter);
:Add employees & shifts;
:Monitor attendance dashboard;
:Run payroll for period;
:Send / finalize payslips;
stop

|Platform Admin|
start
:Login (React);
:Review business signup;
:Approve or reject;
stop

@enduml
```

---

## 2. System layers and request flow

Every action flows **client → FastAPI → database** (and **face service** when biometrics are involved).

```plantuml
@startuml Request_Flow
title Figure 2 — Typical Request Flow

actor User
participant "Flutter / React" as UI
participant "FastAPI" as API
participant "Auth\n(JWT)" as Auth
participant "Face Service" as Face
database "PostgreSQL" as DB

User -> UI : action
UI -> API : HTTPS + Bearer token
API -> Auth : validate JWT\n(role, business_id)
Auth --> API : OK / 401

alt needs face
  API -> Face : image bytes
  Face --> API : embedding / error
  API -> DB : query / insert
else normal CRUD
  API -> DB : SQL
end

DB --> API : result
API --> UI : JSON response
UI --> User : screen update

@enduml
```

---

## 3. Business lifecycle

From signup to active tenant.

```plantuml
@startuml Business_State
title Figure 3 — Business Registration State Machine

[*] --> Pending : owner submits form

Pending --> Approved : admin approves
Pending --> Rejected : admin rejects

Approved --> Active : owner completes\nprofile + location
Active --> Suspended : admin/owner suspend
Suspended --> Active : reactivate

Rejected --> [*]
note right of Pending
  business_registration.status
  = pending
end note

note right of Active
  business.status = active
  employees can be added
end note

@enduml
```

**Steps in plain language:**

1. Owner fills registration on web → `pending`.
2. Platform admin approves → `business` row created → owner invited to set password.
3. Owner adds **business_location** (`address` + `latitude`/`longitude` + geofence radius) → business is **active**.
4. Manager enrolls employees and assigns shifts.

---

## 4. Employee journey (end-to-end)

```plantuml
@startuml Employee_Journey
title Figure 4 — Employee Journey

|#LightBlue|Employee|#LightBlue|
start
:Receive email + temp password\nfrom owner/manager;
:First login\n(Flutter);
:Forced change password\n(must_change_password);
if (Face enrolled?) then (no)
  :Face enrollment\n(deferred — last build block);
  note right: Interim: view schedule/payslip only
else (yes)
endif
:Open Clock In;
:Liveness challenge;
:Capture face + GPS;
if (Verified?) then (yes)
  :Attendance recorded;
else (no)
  :Show error\n(retry or contact manager);
  stop
endif
:Work until shift end;
:Clock Out\n(face + GPS again);
:View attendance history;
:View payslip\n(after payroll run);
stop

@enduml
```

---

## 5. Face enrollment workflow

Managers enroll employees **before** they can clock in.

```plantuml
@startuml Face_Enrollment
title Figure 5 — Face Enrollment Sequence

actor Manager
participant "Flutter / Web" as UI
participant "FastAPI" as API
participant "Face Service" as Face
database "PostgreSQL" as DB

Manager -> UI : select employee
loop 3 to 5 samples
  Manager -> UI : capture photo
  UI -> API : POST /employees/{id}/face-samples
  API -> Face : detect + align + embed
  alt no face detected
    Face --> API : error
    API --> UI : retry message
  else OK
    Face --> API : vector[128]
    API -> DB : INSERT employee_face_embedding
    API --> UI : sample saved
  end
end
API --> UI : enrollment complete
Manager --> Manager : employee can clock in

@enduml
```

---

## 6. Clock-in / clock-out workflow

Core attendance path (matches thesis scope: face + liveness + geolocation).

```plantuml
@startuml Clock_Workflow
title Figure 6 — Clock-In Activity Diagram

start
:Employee opens app;
:JWT valid?;

if (no) then (yes)
  :Redirect to login;
  stop
endif

:Start liveness check;
if (liveness failed?) then (yes)
  :Reject;
  stop
endif

:Capture selfie + GPS;
:POST /attendance/clock-in;

partition "Server" {
  :Extract face embedding;
  if (face found?) then (no)
    :403 not recognized;
    stop
  endif
  :Compare to employee embeddings\n(pgvector cosine);
  if (score < threshold?) then (yes)
    :403 low confidence;
    stop
  endif
  :Compute distance to\nbusiness_location;
  if (outside geofence?) then (yes)
    :403 outside location;
    stop
  endif
  :Insert attendance_record\n(time_in, GPS, score);
}

:Show success + time;
stop

@enduml
```

### Attendance record state

```plantuml
@startuml Attendance_State
title Figure 7 — Attendance Record States

[*] --> InProgress : clock in

InProgress --> Complete : clock out\n(on time)
InProgress --> Late : clock in after\nshift start
InProgress --> Incomplete : no clock out\nby cutoff
Late --> Complete : clock out

Complete --> [*]
Incomplete --> [*]

@enduml
```

---

## 7. Shift and scheduling workflow

```plantuml
@startuml Shift_Workflow
title Figure 8 — Shift Assignment Flow

|Manager|
start
:Create shift template\n(name, start, end);
:Assign shift to employee\nfor work_date;
:Saved as shift_assignment;

|Employee|
:View schedule in Flutter\n(read-only);

|System|
:On clock-in, optional link\nto shift_assignment;
:Compare time_in vs shift.start_time;
:Mark late if after grace period;

stop
@enduml
```

---

## 8. Payroll workflow

```plantuml
@startuml Payroll_Activity
title Figure 9 — Payroll Processing Activity

|Manager|
start
:Select pay period\n(start, end);
:POST /payroll/runs (draft);

partition "Payroll engine" {
  :Load attendance_records\nin period;
  :Load shift_assignments;
  :Apply rules (TBD W1)\nhours, OT, deductions;
  :Generate payslip rows;
}

:Review totals on dashboard;
if (Correct?) then (no)
  :Adjust attendance or rules;
  :Recalculate draft;
else (yes)
endif
:Finalize payroll_run;
:Email payslips (optional);
:Employees view in app;

stop
@enduml
```

### Payroll run state

```plantuml
@startuml Payroll_State
title Figure 10 — Payroll Run State Machine

[*] --> Draft : create run

Draft --> Draft : recalculate
Draft --> Finalized : finalize
Draft --> Cancelled : cancel

Finalized --> [*] : payslips locked
Cancelled --> [*]

note right of Finalized
  payslip rows immutable
  employees can view
end note

@enduml
```

---

## 9. Role-based access flow

```plantuml
@startuml RBAC_Flow
title Figure 11 — Login and Role Routing

actor User
participant "Client App" as Client
participant "FastAPI" as API
database "PostgreSQL" as DB

User -> Client : email + password
Client -> API : POST /auth/login
API -> DB : find user + verify hash
API --> Client : JWT (role, business_id)

alt platform_admin
  Client --> User : React admin\n(registrations)
elseif owner or manager
  Client --> User : React dashboards\n+ optional Flutter
elseif employee
  Client --> User : Flutter\n(clock-in, payslip)
end

@enduml
```

---

## 10. End-to-end data flow (attendance → payroll)

How time captured at clock-in becomes pay on a payslip.

```plantuml
@startuml Data_Flow
title Figure 12 — Data Flow: Attendance to Payroll

rectangle "Capture" {
  (Clock in/out) as CI
  (attendance_record) as AR
}

rectangle "Schedule" {
  (shift_assignment) as SA
}

rectangle "Compute" {
  (payroll_run) as PR
  (payslip) as PS
}

rectangle "Deliver" {
  (Flutter payslip view) as View
  (Email) as Mail
}

CI --> AR : creates/updates
SA --> AR : expected hours
AR --> PR : aggregate hours
PR --> PS : calculate pay
PS --> View
PS --> Mail

@enduml
```

---

## 11. Error handling (reliability preview)

How the system behaves when something fails (supports ISO 25010 Reliability discussion in Ch. 5).


| Failure                   | System response       | User message                   |
| ------------------------- | --------------------- | ------------------------------ |
| No network                | Request fails         | Check internet connection      |
| Face not detected         | 400 from face service | Center face in frame           |
| Face not recognized       | 403                   | Identity not verified          |
| Outside geofence          | 403                   | You must be at the workplace   |
| Liveness failed           | 403                   | Please try liveness again      |
| No enrollment             | 403                   | Contact manager for face setup |
| Payroll already finalized | 409                   | Period already closed          |


```plantuml
@startuml Error_Flow
title Figure 13 — Clock-In Failure Paths

start
:Clock-in request;

if (network?) then (down)
  :Fail fast;
  stop
endif

if (liveness?) then (fail)
  :403;
  stop
endif

if (face match?) then (fail)
  :403;
  stop
endif

if (geofence?) then (fail)
  :403;
  stop
endif

:200 success;
stop

@enduml
```

---

## 12. Diagram index


| Figure | File section | Diagram type                |
| ------ | ------------ | --------------------------- |
| 1      | §1           | Activity — overview         |
| 2      | §2           | Sequence — request flow     |
| 3      | §3           | State — business lifecycle  |
| 4      | §4           | Activity — employee journey |
| 5      | §5           | Sequence — face enrollment  |
| 6      | §6           | Activity — clock-in         |
| 7      | §6           | State — attendance          |
| 8      | §7           | Activity — shifts           |
| 9      | §8           | Activity — payroll          |
| 10     | §8           | State — payroll run         |
| 11     | §9           | Sequence — login/RBAC       |
| 12     | §10          | Component — data flow       |
| 13     | §11          | Activity — errors           |


---

## 13. Rendering PlantUML

1. Install **PlantUML** extension in Cursor/VS Code.
2. Open this file and preview diagrams, or export PNG/SVG for thesis figures.
3. Online: paste a `@startuml` block into [https://www.plantuml.com/plantuml](https://www.plantuml.com/plantuml).

---

## Document history


| Version | Date     | Notes                     |
| ------- | -------- | ------------------------- |
| 1.0     | May 2026 | Initial workflow document |


