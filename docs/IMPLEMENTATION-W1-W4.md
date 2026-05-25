# W1–W4 Implementation Guide

**W1 docs:** Done in repo (`W1-DATA-REQUIREMENTS.md`, updated `SOLUTION.md`, `SYSTEM-WORKFLOWS.md`, `DATABASE-ERD.md`).

**W2–W4 + scripts:** Implemented in repo (`backend/`, `admin-web/`, `scripts/`, `docker-compose.yml`, updated `mobile/`).

---

## Repository layout (target)

```
aroll/
  docker-compose.yml
  scripts/
    aroll.ps1          # Interactive menu
    build.ps1
    clean.ps1
    run-db.ps1
    run-backend.ps1
    run-admin-web.ps1
    run-mobile.ps1
  backend/
    requirements.txt
    .env.example
    alembic/
    app/
      main.py
      api/ auth, admin, employees, registrations
      models/
  admin-web/           # Vite + React + shadcn + TanStack Query
  mobile/              # shadcn_ui + go_router + dio (updated)
  docs/
```

---

## Scripts (PowerShell — Windows)

### `scripts/aroll.ps1` (menu)

Options:

1. Start database (Docker)
2. Run migrations + seed
3. Start backend (uvicorn)
4. Start admin-web (npm run dev)
5. Start mobile (flutter run)
6. **Start all** (db + backend + admin-web in separate windows)
7. **Build all**
8. **Clean all**
9. Exit

### `scripts/build.ps1`

- `docker compose build` (if needed)
- `backend`: pip install, `alembic upgrade head`
- `admin-web`: `npm ci`, `npm run build`
- `mobile`: `flutter pub get`, `flutter build apk --debug` (optional)

### `scripts/clean.ps1`

- Stop docker containers
- Remove `backend/__pycache__`, `.pytest_cache`, `admin-web/dist`, `admin-web/node_modules`, `mobile/build`, `.dart_tool` (optional flags)

---

## W2 — Backend scaffold

1. `docker compose up -d` — PostgreSQL + pgvector
2. `backend/.env` from `.env.example`
3. Alembic initial migration: all ERD tables + `CREATE EXTENSION vector`
4. Seed: platform admin `admin@example.com` / `changeme123`

---

## W3 — API (prefix `/api/v1`)

| Method | Path | Role |
|--------|------|------|
| POST | `/auth/login` | All |
| POST | `/auth/change-password` | Authenticated + must_change_password |
| GET | `/auth/me` | Authenticated |
| POST | `/registrations` | Public (business signup) |
| GET | `/admin/registrations` | platform_admin |
| POST | `/admin/registrations/{id}/approve` | platform_admin |
| POST | `/admin/registrations/{id}/reject` | platform_admin |
| POST | `/employees` | owner, manager |
| GET | `/employees` | owner, manager |
| PATCH | `/businesses/me/location` | owner |
| PUT | `/businesses/me/payroll-config` | owner, manager |

Employee create response includes `temporary_password` (once).

---

## W4 — Frontends

### admin-web

```powershell
npm create vite@latest admin-web -- --template react-ts
cd admin-web
npm install react-router-dom @tanstack/react-query axios zod react-hook-form @hookform/resolvers date-fns sonner jwt-decode
npx shadcn@latest init
npx shadcn@latest add button input label card table dialog form select badge sonner
```

Pages: Login, Admin registrations, Owner employees (+ add employee modal showing temp password).

### mobile

`pubspec.yaml` add: `shadcn_ui`, `go_router`, `dio`, `flutter_secure_storage`, `flutter_dotenv`

Routes: `/login` → `/change-password` (if flag) → `/home`

Replace mock `AuthRepositoryImpl` with Dio → FastAPI.

---

## Quick start (after Agent build)

```powershell
cd c:\Users\jrparreno\Development\aroll
.\scripts\aroll.ps1
# Choose 6 — Start all
```

API: http://localhost:8000/docs  
Admin: http://localhost:5173
