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
    if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }

    # Try curl.exe first (progress bar), then fall back to Invoke-WebRequest
    # with TLS 1.2 forced (fixes curl exit code 35 / SSL errors on some PCs).
    $downloaded = $false
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        & curl.exe -L --fail --retry 3 --ssl-no-revoke -o $tmp $spec.Url
        if ($LASTEXITCODE -eq 0) {
            $downloaded = $true
        } else {
            Write-Host ("  [WARN] curl failed (code {0}) - retrying with PowerShell downloader..." -f $LASTEXITCODE) -ForegroundColor Yellow
            if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
        }
    }

    if (-not $downloaded) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $prevProgress = $ProgressPreference
            $ProgressPreference = "SilentlyContinue"  # much faster large downloads
            Invoke-WebRequest -Uri $spec.Url -OutFile $tmp -UseBasicParsing
            $ProgressPreference = $prevProgress
        } catch {
            if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
            Write-Host ("  [FAIL] {0}: {1}" -f $spec.Name, $_.Exception.Message) -ForegroundColor Red
            Write-Host "         If this keeps failing: check internet/proxy/antivirus, or download manually:" -ForegroundColor Yellow
            Write-Host ("         {0}" -f $spec.Url) -ForegroundColor Yellow
            Write-Host ("         and save it as: {0}" -f $dest) -ForegroundColor Yellow
            throw
        }
    }

    $size = (Get-Item $tmp).Length
    if ($size -lt $spec.MinBytes) {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        throw "Downloaded file is too small ($size bytes) - check the URL / network."
    }
    Move-Item -Force $tmp $dest
    $mb = [math]::Round($size / 1MB, 1)
    Write-Host ("  [OK]   {0} downloaded ({1} MB)" -f $spec.Name, $mb) -ForegroundColor Green
}

foreach ($m in $Models) {
    Get-FaceModel $m
}

Write-Host ""
Write-Host "Face models ready." -ForegroundColor Green
Write-Host ""
