$sourcePath = Join-Path $PSScriptRoot "..\..\src\index.py"
$archivePath = Join-Path $PSScriptRoot "..\..\src\funcion_lambda.zip"

if (-not (Test-Path $sourcePath)) {
    Write-Host "[ERR] Source file not found: $sourcePath" -ForegroundColor Red
    exit 1
}

Write-Host "[1/3] Preparing temp folder..." -ForegroundColor Cyan

$tempDir = Join-Path $env:TEMP "lambda_build"
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $tempDir | Out-Null

Copy-Item $sourcePath "$tempDir\index.py"

Write-Host "[2/3] Creating ZIP with correct structure..." -ForegroundColor Cyan

if (Test-Path $archivePath) {
    Remove-Item $archivePath -Force
}

Compress-Archive -Path "$tempDir\index.py" -DestinationPath $archivePath -Force

Write-Host "[3/3] Done: $archivePath" -ForegroundColor Green