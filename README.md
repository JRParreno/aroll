# Aroll+

**Face Recognition-Based Attendance and Payroll System**

Capstone / thesis project for small food-and-service businesses in Bicol, Philippines. Aroll+ replaces manual logbooks and spreadsheet payroll with a mobile app that clocks attendance using **facial recognition**, **liveness detection**, and **geolocation**, then computes payroll from recorded work time.

---

## Pilot businesses

| Business | Type |
|----------|------|
| Mr. Bean Cafe | Cafe |
| Ugom Cafe | Cafe |
| Pande Doc | Service |
| Benzon Burger House | Quick-service restaurant |

---

## Study objectives

1. Determine data requirements for system development  
2. Design a mobile application for attendance and payroll using facial recognition  
3. Evaluate the system using **ISO/IEC 25010** (Functional Suitability and Reliability)

---

## Tech stack (planned)

| Layer | Technology |
|-------|------------|
| Mobile | Flutter |
| Admin web | React |
| API | FastAPI (Python) |
| Face pipeline | OpenCV (+ embeddings) |
| Database | PostgreSQL + pgvector |

---

## Documentation

Design documents live in [`docs/`](docs/). Use them as the source for **Thesis Chapter 3** (System Design).

| Document | Description |
|----------|-------------|
| [**SOLUTION.md**](docs/SOLUTION.md) | Main system design — architecture, stack, use cases, core sequences |
| [**DATABASE-ERD.md**](docs/DATABASE-ERD.md) | Detailed ERD, entity dictionary, enums, relationships |
| [**SYSTEM-WORKFLOWS.md**](docs/SYSTEM-WORKFLOWS.md) | How the system works — activity, sequence, and state diagrams |
| [**diagrams/**](docs/diagrams/) | 24 standalone `.puml` files (export PNG/SVG for thesis) |

### Viewing PlantUML diagrams

Diagrams use `@startuml` blocks inside the markdown files.

1. Open any file in [`docs/diagrams/`](docs/diagrams/) with the [PlantUML](https://marketplace.visualstudio.com/items?itemName=jebbs.plantuml) extension, or  
2. Paste a diagram block into [plantuml.com/plantuml](https://www.plantuml.com/plantuml)

---

## Project status

| Phase | Status |
|-------|--------|
| Chapter 1 (problem & scope) | Done |
| System design docs | Done |
| W1 data requirements (ERD, payroll rules) | Pending |
| Application code (`backend/`, `mobile/`, etc.) | Not started |

**Build timeline:** June – mid-September 2026 (see [`aroll+_thesis_understanding_0f94b20e.plan.md`](aroll+_thesis_understanding_0f94b20e.plan.md))

---

## Planned repository layout

```
aroll/
  backend/           # FastAPI + Alembic migrations
  face-service/      # OpenCV embedding API
  mobile/            # Flutter app
  admin-web/         # React admin dashboard
  docs/              # Design documentation (this repo phase)
  docker-compose.yml # PostgreSQL + pgvector (dev)
```

---

## Key features (in scope)

- Business registration and platform admin approval  
- Role-based access: platform admin, owner, manager, employee  
- Face enrollment and clock-in/out with liveness + geofence  
- Shift scheduling and attendance monitoring  
- Automated payroll and digital payslips  
- Email notifications for attendance and payroll records  

**Out of scope:** inventory, POS, customer purchases.

---

## Authentication note (thesis manuscript)

Chapter 1 **Scope** specifies facial recognition. The **Significance** section still mentions QR/pincode — update that text before defense. The implemented system uses **face recognition only** for clock-in.

---

## Institutional alignment

- UN **SDG 8** — Decent Work and Economic Growth  
- **Bicol University** Thematic Area 2 — Industry, Energy, and Emerging Technology

---

## License & authors

Thesis project — add author names, institution, and year before submission.
