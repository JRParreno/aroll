# Aroll+ first-time project setup - run from repo root: .\scripts\setup.ps1
param(
    [switch]$SkipDatabase,
    [switch]$SkipFlutter
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

Write-Host ""
Write-Host "=== Aroll+ Project Setup ===" -ForegroundColor Cyan
Write-Host ""

function Test-CommandExists($name) {
    return $null -ne (Get-Command $name -ErrorAction SilentlyContinue)
}

function Require-Command($name, $installHint) {
    if (-not (Test-CommandExists $name)) {
        Write-Host ('[FAIL] ' + $name + ' not found. ' + $installHint) -ForegroundColor Red
        return $false
    }
    Write-Host ('[OK]   ' + $name) -ForegroundColor Green
    return $true
}

# --- Prerequisites ---
Write-Host "Checking prerequisites..." -ForegroundColor Yellow
$ok = $true
$ok = (Require-Command "python" "Install Python 3.11+ from https://www.python.org/downloads/") -and $ok
$ok = (Require-Command "node" "Install Node.js 18+ from https://nodejs.org/") -and $ok
$ok = (Require-Command "npm" "Comes with Node.js") -and $ok

$hasDocker = Test-CommandExists "docker"
if ($hasDocker) {
    Write-Host '[OK]   docker' -ForegroundColor Green
} else {
    Write-Host '[WARN] docker not found - skip DB steps or install Docker Desktop' -ForegroundColor Yellow
}

$hasFlutter = Test-CommandExists "flutter"
if ($SkipFlutter) {
    Write-Host '[SKIP] flutter (-SkipFlutter)' -ForegroundColor DarkGray
} elseif ($hasFlutter) {
    Write-Host '[OK]   flutter' -ForegroundColor Green
} else {
    Write-Host '[WARN] flutter not found - install from https://docs.flutter.dev/get-started/install' -ForegroundColor Yellow
}

if (-not $ok) {
    Write-Host ""
    Write-Host "Fix missing required tools and run setup again." -ForegroundColor Red
    exit 1
}

Write-Host ""

# --- Environment files ---
Write-Host "Environment files..." -ForegroundColor Yellow

function Ensure-EnvFile($example, $target) {
    if (-not (Test-Path $target)) {
        if (Test-Path $example) {
            Copy-Item $example $target
            Write-Host "  Created $target from example" -ForegroundColor Green
        } else {
            Write-Host "  Missing $example" -ForegroundColor Red
        }
    } else {
        Write-Host "  Exists $target" -ForegroundColor DarkGray
    }
}

Ensure-EnvFile "$Root\backend\.env.example" "$Root\backend\.env"
Ensure-EnvFile "$Root\admin-web\.env.example" "$Root\admin-web\.env"
Ensure-EnvFile "$Root\mobile\.env.example" "$Root\mobile\.env"

Write-Host ""

# --- Backend ---
Write-Host "Backend (Python)..." -ForegroundColor Yellow
Push-Location "$Root\backend"
if (-not (Test-Path ".venv")) {
    python -m venv .venv
    Write-Host "  Created .venv" -ForegroundColor Green
}
& .\.venv\Scripts\pip install -q -r requirements.txt
Write-Host "  Dependencies installed" -ForegroundColor Green
Pop-Location

# --- Admin web ---
Write-Host "Admin web (npm)..." -ForegroundColor Yellow
Push-Location "$Root\admin-web"
npm install --silent 2>$null
if ($LASTEXITCODE -ne 0) { npm install }
Write-Host "  Dependencies installed" -ForegroundColor Green
Pop-Location

# --- Mobile ---
if (-not $SkipFlutter -and $hasFlutter) {
    Write-Host "Mobile (Flutter)..." -ForegroundColor Yellow
    Push-Location "$Root\mobile"
    flutter pub get
    Write-Host "  Dependencies installed" -ForegroundColor Green
    Pop-Location
}

# --- Face models (YuNet + ArcFace) ---
Write-Host "Face recognition models..." -ForegroundColor Yellow
& "$Root\scripts\download-face-models.ps1"

# --- Database ---
if (-not $SkipDatabase -and $hasDocker) {
    Write-Host ""
    Write-Host "Database (Docker)..." -ForegroundColor Yellow
    docker compose up -d
    Write-Host "  Waiting for PostgreSQL..." -ForegroundColor Yellow
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        docker exec aroll-db pg_isready -U aroll -d aroll 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        Start-Sleep -Seconds 2
    }
    if ($ready) {
        Push-Location "$Root\backend"
        & .\.venv\Scripts\alembic upgrade head
        & .\.venv\Scripts\python -m app.seed
        Pop-Location
        Write-Host "  Migrations and seed complete" -ForegroundColor Green
        Write-Host "  Platform admin: admin@example.com / changeme123" -ForegroundColor Cyan
    } else {
        Write-Host '  Database not ready - run menu option 2 later' -ForegroundColor Yellow
    }
} elseif ($SkipDatabase) {
    Write-Host ""
    Write-Host 'Database skipped (-SkipDatabase)' -ForegroundColor DarkGray
} else {
    Write-Host ""
    Write-Host "Database skipped (no Docker). After Postgres is running:" -ForegroundColor Yellow
    Write-Host "  cd backend; .\.venv\Scripts\alembic upgrade head; .\.venv\Scripts\python -m app.seed" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "=== Setup complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host '  .\scripts\aroll.ps1     - dev menu (start services)'
Write-Host '  .\scripts\download-face-models.ps1 - re-download face models if needed'
Write-Host '  docs/PROJECT-SETUP.md  - full setup guide'
Write-Host '  docs/FACE-RECOGNITION.md - face enroll / liveness demo'
Write-Host '  http://localhost:8000/docs - API (after starting backend)'
Write-Host '  http://localhost:5173      - Admin web'
Write-Host ""
