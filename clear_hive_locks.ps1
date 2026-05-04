# Clear Hive Database Locks
# Run this script if you get database lock errors

Write-Host "=== Clearing Hive Database Locks ===" -ForegroundColor Green

# Get the app data directory path (this matches what the Flutter app uses)
$appDataPath = [Environment]::GetFolderPath('MyDocuments')
$hiveDir = Join-Path $appDataPath "navi_data"

Write-Host "Checking Hive directory: $hiveDir" -ForegroundColor Yellow

if (Test-Path $hiveDir) {
    Write-Host "Found Hive directory. Removing lock files..." -ForegroundColor Green

    # Remove all .lock files
    Get-ChildItem -Path $hiveDir -Filter "*.lock" -File | ForEach-Object {
        try {
            Remove-Item $_.FullName -Force
            Write-Host "Deleted: $($_.Name)" -ForegroundColor Green
        } catch {
            Write-Host "Failed to delete $($_.Name): $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host "Lock files cleared successfully!" -ForegroundColor Green
} else {
    Write-Host "Hive directory not found at $hiveDir" -ForegroundColor Yellow
    Write-Host "This might be normal if the app hasn't run yet." -ForegroundColor Yellow
}

Write-Host "=== Done ===" -ForegroundColor Green