$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

Write-Host "Building Aroll+..." -ForegroundColor Cyan

# Backend
Push-Location "$Root\backend"
if (-not (Test-Path ".venv")) { python -m venv .venv }
& .\.venv\Scripts\pip install -q -r requirements.txt
& .\.venv\Scripts\alembic upgrade head
& .\.venv\Scripts\python -m app.seed
Pop-Location

# Admin web
if (Test-Path "$Root\admin-web\package.json") {
    Push-Location "$Root\admin-web"
    npm install
    npm run build
    Pop-Location
}

# Mobile
if (Get-Command flutter -ErrorAction SilentlyContinue) {
    Push-Location "$Root\mobile"
    flutter pub get
    Pop-Location
}

Write-Host "Build complete." -ForegroundColor Green
