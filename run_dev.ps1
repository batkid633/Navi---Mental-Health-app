# Run Development Pipeline - Windows PowerShell Version
# Usage: .\run_dev.ps1 [--retrain]

param(
    [switch]$retrain = $false
)

# Stop on error
$ErrorActionPreference = "Stop"

# Ensure we're in the project root
Set-Location $PSScriptRoot

Write-Host "=== Navi Dev Pipeline Starting ===" -ForegroundColor Green

# 1. Sync + merge WHOOP data (tokens auto-refresh)
Write-Host "Syncing WHOOP data..." -ForegroundColor Yellow
$env:PYTHONPATH = "$PWD;$env:PYTHONPATH"
python navi_ml/whoop_sync_and_merge.py

# 2. Train model
$trainModel = $retrain
if (-not $trainModel) {
    $response = Read-Host "Retrain model? [y/N]"
    if ($response -eq "y" -or $response -eq "Y") {
        $trainModel = $true
    }
}

Write-Host "Training next-day mood model..." -ForegroundColor Yellow
$env:PYTHONPATH = "$PWD;$env:PYTHONPATH"
$args = if ($trainModel) { "--force" } else { "" }
python backend/ml/train_next_day_mood.py $args

# 3. Build features
Write-Host "Building feature schema..." -ForegroundColor Yellow
$env:PYTHONPATH = "$PWD;$env:PYTHONPATH"
python backend/ml/feature_builder.py

# 4. Start backend (background) - listening on all interfaces for WiFi
Write-Host "Starting backend server on 0.0.0.0:8000..." -ForegroundColor Yellow
Write-Host ""
Write-Host "⚠️  WiFi SETUP INSTRUCTIONS:" -ForegroundColor Cyan
Write-Host "1. Find your computer's IP address:"
Write-Host "   - Windows PowerShell: ipconfig | grep IPv4"
Write-Host "   - Mac Terminal: ifconfig | grep inet"
Write-Host "2. Open lib/config/backend_config.dart"
Write-Host "3. Set useWiFi = true"
Write-Host "4. Set wiFiIP = ""YOUR_IP_ADDRESS"" (e.g., 192.168.1.100)"
Write-Host "5. Make sure iPhone is on same WiFi as this computer"
Write-Host "6. Run app with 'flutter run'"
Write-Host ""

Push-Location backend
$backendProcess = Start-Process python -ArgumentList @("-m", "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000", "--reload") -PassThru
$backendPID = $backendProcess.Id
Pop-Location

# Give backend time to boot
Write-Host "Waiting for backend to start..." -ForegroundColor Gray
Start-Sleep -Seconds 6

# 5. Start Flutter
Write-Host "Starting Flutter app..." -ForegroundColor Yellow
flutter run

# Cleanup on exit
Write-Host "Cleaning up background processes..." -ForegroundColor Gray
Stop-Process -Id $backendPID -ErrorAction SilentlyContinue
