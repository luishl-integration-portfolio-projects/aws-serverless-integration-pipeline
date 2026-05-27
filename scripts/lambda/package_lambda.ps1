$sourcePath  = Join-Path $PSScriptRoot "..\..\src\index.py"
$archivePath = Join-Path $PSScriptRoot "..\..\src\funcion_lambda.zip"

if (-not (Test-Path $sourcePath)) {
    Write-Host "[ERR] Source file not found: $sourcePath" -ForegroundColor Red
    exit 1
}

Write-Host "[1/3] Packaging Lambda code..." -ForegroundColor Cyan
Compress-Archive -Path $sourcePath -DestinationPath $archivePath -Force

if ($LASTEXITCODE -eq 0 -or (Test-Path $archivePath)) {
    Write-Host "  [OK] Lambda package created: $archivePath" -ForegroundColor Green
} else {
    Write-Host "[ERR] Failed to create Lambda package." -ForegroundColor Red
    exit 1
}
