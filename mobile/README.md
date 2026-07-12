# Aroll+ Mobile (Flutter)

Flutter mobile client for the Aroll+ thesis project. Follows **clean architecture** with a live FastAPI backend — no mock repositories.

## Architecture layers

| Layer | What lives here |
|-------|----------------|
| **Domain** | Entities (`UserSession`, `EmployeeRecord`, …), repository contracts, use cases (`LoginUsecase`, `RestoreSessionUsecase`, …) |
| **Data** | `AuthRepositoryImpl`, `EmployeeRepositoryImpl`, `OwnerRepository` — all backed by real API calls via `ApiClient` (Dio + FlutterSecureStorage) |
| **Presentation** | Screens + BLoC where needed (`LoginBloc`, `ChangePasswordBloc`); simpler screens call repositories directly |
| **Core** | AppState (ChangeNotifier), GoRouter, GetIt DI, Dio interceptors, error types |

## Project structure

```
lib/
  core/           # AppState, router, DI, network, error types
  domain/         # entities, repository contracts, use cases
  data/           # repository implementations (live API)
  presentation/   # screens organised by feature
    auth/         # RoleLandingScreen, EmployeeLoginScreen, OwnerLoginScreen, ChangePasswordScreen
    home/         # HomeScreen (employee dashboard), ScanAttendanceScreen
    employee/     # Schedule, ShiftHistory, Payroll, Payslip, Profile, FaceRegistration
    owner/        # OwnerDashboard, Attendance, Employees, Payroll, Schedule, Settings, SetupWizard
  app.dart        # session restore + GoRouter mount
  main.dart
```

## Prerequisites

1. [Install Flutter](https://docs.flutter.dev/get-started/install) (SDK 3.2+).
2. Add Flutter to your `PATH`.
3. Copy `.env.example` to `.env` and set `API_BASE_URL` to your backend.

## First-time setup

```powershell
cd mobile
flutter pub get
```

## Run

```powershell
flutter run
```

Or press **F5** in VS Code / Cursor with the **Dart** and **Flutter** extensions installed.

**Demo login:** `owner@mrbean.test` / `demo1234`

After sign-in the app restores your session automatically on next launch (JWT stored in FlutterSecureStorage, validated via `GET /auth/me`).

## Tests

```powershell
flutter test
```

## Adding a new BLoC

Register it at the bottom of `core/di/bloc_service_locator.dart`.
