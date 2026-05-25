param(
    [switch]$Deep
)

$ErrorActionPreference = "SilentlyContinue"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

Write-Host "Cleaning Aroll+..." -ForegroundColor Cyan

docker compose down 2>$null

$paths = @(
    "$Root\backend\__pycache__",
    "$Root\backend\app\__pycache__",
    "$Root\backend\.pytest_cache",
    "$Root\admin-web\dist",
    "$Root\mobile\build"
)

foreach ($p in $paths) {
    if (Test-Path $p) { Remove-Item -Recurse -Force $p }
}

Get-ChildItem -Path "$Root\backend" -Recurse -Directory -Filter "__pycache__" | Remove-Item -Recurse -Force

if ($Deep) {
    if (Test-Path "$Root\admin-web\node_modules") { Remove-Item -Recurse -Force "$Root\admin-web\node_modules" }
    if (Test-Path "$Root\mobile\.dart_tool") { Remove-Item -Recurse -Force "$Root\mobile\.dart_tool" }
    if (Test-Path "$Root\backend\.venv") { Remove-Item -Recurse -Force "$Root\backend\.venv" }
}

Write-Host "Clean complete. Use -Deep to remove node_modules, .venv, .dart_tool" -ForegroundColor Green
