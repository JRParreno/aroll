# Aroll+ Mobile (Flutter sample)

Sample Flutter app for the Aroll+ thesis project. It demonstrates **clean architecture** and the **BLoC patterns** described in [`../clean_code_bloc.md`](../clean_code_bloc.md).

## What’s included

| Layer | Example |
|-------|---------|
| **Domain** | `LoginUsecase`, `GetAttendanceHistoryUsecase` |
| **Data** | Mock repositories (no API yet) |
| **Presentation** | Login (submit-only BLoC), Attendance history (pageable BLoC) |
| **Core** | `PageData<T>`, `StateEnum`, GetIt DI |

## Project structure

```
lib/
  core/           # shared enums, models, DI
  domain/         # entities, repository contracts, use cases
  data/           # repository implementations (mock)
  presentation/   # screens + bloc/FeatureName/
  app.dart
  main.dart
```

## Prerequisites

1. [Install Flutter](https://docs.flutter.dev/get-started/install) (SDK 3.2+).
2. Add Flutter to your `PATH`.

## First-time setup

From the repo root:

```powershell
cd mobile
flutter create . --org ph.edu.bicol.aroll --project-name aroll_mobile
flutter pub get
```

`flutter create .` adds `android/`, `ios/`, `web/`, etc. It keeps existing `lib/` and `pubspec.yaml`.

## Run from VS Code / Cursor

1. Install extensions: **Dart** and **Flutter** (VS Code will prompt via `.vscode/extensions.json`).
2. Open the repo root (`aroll/`) or the `mobile/` folder.
3. Press **F5** or **Run and Debug** → choose **Aroll+ Mobile (debug)**.

If you open only `mobile/`, use **Aroll+ (debug)** from `mobile/.vscode/launch.json`.

## Run from terminal

```powershell
flutter run
```

**Demo login:** `owner@mrbean.test` / `demo1234`

After sign-in, open **Attendance history** to see pagination and search.

## Tests

```powershell
flutter test
```

## Next steps (real app)

- Replace mock repositories with API clients (FastAPI backend).
- Add `data/datasources` and DTO models.
- Wire face enrollment and clock-in flows per `docs/SOLUTION.md`.
- Register new BLoCs at the bottom of `core/di/bloc_service_locator.dart`.
