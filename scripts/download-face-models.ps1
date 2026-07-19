# Download face recognition ONNX models into backend/models/.
# Safe to re-run: skips files that already exist.
# Usage (from repo root): .\scripts\download-face-models.ps1
#                         .\scripts\download-face-models.ps1 -Force

param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ModelsDir = Join-Path $Root "backend\models"

if (-not (Test-Path $ModelsDir)) {
    New-Item -ItemType Directory -Path $ModelsDir | Out-Null
}

# YuNet (~0.2 MB) - tracked in git, but download if someone deleted it.
# ArcFace R50 (~166 MB) - NOT in git (GitHub 100 MB limit); required for face match.
$Models = @(
    @{
        Name = "face_detection_yunet_2023mar.onnx"
        Url  = "https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx"
        MinBytes = 100KB
    },
    @{
        Name = "arcface_w600k_r50.onnx"
        Url  = "https://huggingface.co/immich-app/buffalo_l/resolve/main/recognition/model.onnx"
        MinBytes = 100MB
    }
)

Write-Host ""
Write-Host "=== Face models ===" -ForegroundColor Cyan
Write-Host "  Directory: $ModelsDir"
Write-Host ""

function Get-FaceModel($spec) {
    $dest = Join-Path $ModelsDir $spec.Name
    if ((Test-Path $dest) -and -not $Force) {
        $size = (Get-Item $dest).Length
        if ($size -ge $spec.MinBytes) {
            $mb = [math]::Round($size / 1MB, 1)
            Write-Host ("  [OK]   {0} ({1} MB)" -f $spec.Name, $mb) -ForegroundColor Green
            return
        }
        Write-Host ("  [WARN] {0} looks incomplete ({1} bytes) - re-downloading" -f $spec.Name, $size) -ForegroundColor Yellow
    }

    Write-Host ("  [GET]  {0} ..." -f $spec.Name) -ForegroundColor Yellow
    $tmp = "$dest.download"
    try {
        # Prefer curl.exe (progress bar); fall back to Invoke-WebRequest.
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
            & curl.exe -L --fail --retry 3 -o $tmp $spec.Url
            if ($LASTEXITCODE -ne 0) { throw "curl exited with code $LASTEXITCODE" }
        } else {
            Invoke-WebRequest -Uri $spec.Url -OutFile $tmp -UseBasicParsing
        }
        $size = (Get-Item $tmp).Length
        if ($size -lt $spec.MinBytes) {
            throw "Downloaded file is too small ($size bytes) - check the URL / network."
        }
        Move-Item -Force $tmp $dest
        $mb = [math]::Round($size / 1MB, 1)
        Write-Host ("  [OK]   {0} downloaded ({1} MB)" -f $spec.Name, $mb) -ForegroundColor Green
    } catch {
        if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
        Write-Host ("  [FAIL] {0}: {1}" -f $spec.Name, $_.Exception.Message) -ForegroundColor Red
        throw
    }
}

foreach ($m in $Models) {
    Get-FaceModel $m
}

Write-Host ""
Write-Host "Face models ready." -ForegroundColor Green
Write-Host ""
