<#
.SYNOPSIS
    Downloads the latest Terraform portable binary for Windows.
.DESCRIPTION
    Fetches the latest stable Terraform release from GitHub, extracts
    terraform.exe to terraform/tools/. No system install needed.
.PARAMETER Version
    Specific version to download (e.g. "1.9.8"). Defaults to latest.
.EXAMPLE
    .\download_terraform.ps1
    .\download_terraform.ps1 -Version "1.9.8"
#>
param(
    [string]$Version = ""
)

$toolsDir = Join-Path $PSScriptRoot "tools"
$zipPath  = Join-Path $toolsDir "terraform.zip"
$exePath  = Join-Path $toolsDir "terraform.exe"

New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null

# -----------------------------------------------------------
# Determine version
# -----------------------------------------------------------
if (-not $Version) {
    Write-Host "[1/3] Querying latest Terraform version from GitHub..." -ForegroundColor Cyan
    try {
        $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/hashicorp/terraform/releases/latest" -TimeoutSec 15
        $Version = $releases.tag_name -replace '^v', ''
        Write-Host "  -> Latest version: $Version" -ForegroundColor DarkGray
    } catch {
        Write-Host "[ERR] Could not fetch latest version from GitHub." -ForegroundColor Red
        Write-Host "  Fallback: use -Version parameter, e.g. -Version 1.9.8" -ForegroundColor Yellow
        exit 1
    }
}

# -----------------------------------------------------------
# Download
# -----------------------------------------------------------
$url = "https://releases.hashicorp.com/terraform/${Version}/terraform_${Version}_windows_amd64.zip"

Write-Host "[2/3] Downloading Terraform $Version..." -ForegroundColor Cyan
Write-Host "  -> $url" -ForegroundColor DarkGray

try {
    Invoke-WebRequest -Uri $url -OutFile $zipPath -TimeoutSec 120
    Write-Host "  [OK] Downloaded to $zipPath" -ForegroundColor Green
} catch {
    Write-Host "[ERR] Download failed: $_" -ForegroundColor Red
    exit 1
}

# -----------------------------------------------------------
# Extract
# -----------------------------------------------------------
Write-Host "[3/3] Extracting terraform.exe..." -ForegroundColor Cyan

try {
    # Using .NET's ZipFile for broader compatibility
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    $entry = $archive.Entries | Where-Object { $_.Name -eq "terraform.exe" }
    if (-not $entry) {
        Write-Host "[ERR] terraform.exe not found in archive." -ForegroundColor Red
        $archive.Dispose()
        exit 1
    }
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $exePath, $true)
    $archive.Dispose()
    Write-Host "  [OK] Extracted to $exePath" -ForegroundColor Green
} catch {
    Write-Host "[ERR] Extraction failed: $_" -ForegroundColor Red
    exit 1
}

# Cleanup
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

Write-Host "  [OK] Cleaned up zip." -ForegroundColor Green
Write-Host ""
Write-Host "[DONE] Terraform $Version is ready." -ForegroundColor Green
Write-Host "  Path: $exePath" -ForegroundColor Cyan
Write-Host "  Run:  .\terraform\apply.ps1 -AutoApprove" -ForegroundColor Cyan
