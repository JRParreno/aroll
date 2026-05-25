# Aroll+ project menu — run from repo root: .\scripts\aroll.ps1
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

function Show-Menu {
    Write-Host ""
    Write-Host "=== Aroll+ Dev Menu ===" -ForegroundColor Cyan
    Write-Host "  0. Project setup (first time)"
    Write-Host "  1. Start database (Docker)"
    Write-Host "  2. Migrate + seed database"
    Write-Host "  3. Start backend (FastAPI)"
    Write-Host "  4. Start admin-web (Vite)"
    Write-Host "  5. Start mobile (Flutter)"
    Write-Host "  6. Start all (DB + migrate + backend + admin-web)"
    Write-Host "  7. Build all"
    Write-Host "  8. Clean all"
    Write-Host "  9. Exit"
    Write-Host ""
}

function Start-Database {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Host "Docker not found. Install Docker Desktop or use a local PostgreSQL and set backend/.env DATABASE_URL." -ForegroundColor Red
        return
    }
    docker compose up -d
    Write-Host "Waiting for PostgreSQL..." -ForegroundColor Yellow
    $max = 30
    for ($i = 0; $i -lt $max; $i++) {
        $ok = docker exec aroll-db pg_isready -U aroll -d aroll 2>$null
        if ($LASTEXITCODE -eq 0) { Write-Host "Database ready." -ForegroundColor Green; return }
        Start-Sleep -Seconds 2
    }
    Write-Warning "Database may not be ready yet."
}

function Invoke-Migrate {
    Push-Location "$Root\backend"
    if (-not (Test-Path ".venv")) {
        python -m venv .venv
    }
    & .\.venv\Scripts\pip install -q -r requirements.txt
    & .\.venv\Scripts\alembic upgrade head
    & .\.venv\Scripts\python -m app.seed
    Pop-Location
}

function Start-Backend {
    Push-Location "$Root\backend"
    if (-not (Test-Path ".venv")) { python -m venv .venv; & .\.venv\Scripts\pip install -q -r requirements.txt }
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$Root\backend'; .\.venv\Scripts\uvicorn app.main:app --reload --host 0.0.0.0 --port 8000"
    Write-Host "Backend starting at http://localhost:8000/docs" -ForegroundColor Green
    Pop-Location
}

function Start-AdminWeb {
    Push-Location "$Root\admin-web"
    if (-not (Test-Path "node_modules")) { npm install }
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$Root\admin-web'; npm run dev"
    Write-Host "Admin web at http://localhost:5173" -ForegroundColor Green
    Pop-Location
}

function Start-Mobile {
    Push-Location "$Root\mobile"
    flutter pub get
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$Root\mobile'; flutter run"
    Pop-Location
}

function Start-All {
    Start-Database
    Invoke-Migrate
    Start-Backend
    Start-Sleep -Seconds 2
    Start-AdminWeb
}

while ($true) {
    Show-Menu
    $choice = Read-Host "Choose option"
    switch ($choice) {
        "0" { & "$Root\scripts\setup.ps1" }
        "1" { Start-Database }
        "2" { Start-Database; Invoke-Migrate }
        "3" { Start-Backend }
        "4" { Start-AdminWeb }
        "5" { Start-Mobile }
        "6" { Start-All }
        "7" { & "$Root\scripts\build.ps1" }
        "8" { & "$Root\scripts\clean.ps1" }
        "9" { exit 0 }
        default { Write-Host "Invalid option" -ForegroundColor Red }
    }
}
