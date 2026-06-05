<#
.SYNOPSIS
    Deploys the EDA pipeline infrastructure with Terraform.
.DESCRIPTION
    1. Verifies LocalStack is reachable (prompts to start if not)
    2. Runs terraform init (if needed)
    3. Runs terraform apply
    4. Prints the API endpoint for testing
.PARAMETER AutoApprove
    If set, passes -auto-approve to terraform apply (skips interactive confirmation).
.PARAMETER SkipInit
    If set, skips terraform init (useful for subsequent applies).
.EXAMPLE
    .\apply.ps1
    .\apply.ps1 -AutoApprove
    .\apply.ps1 -AutoApprove -SkipInit
#>
param(
    [switch]$AutoApprove,
    [switch]$SkipInit
)

$scriptDir = $PSScriptRoot

# Load portable terraform resolver
. "$scriptDir\lib\Get-Terraform.ps1"

function Write-Header($text) {
    Write-Host "============================================" -ForegroundColor Magenta
    Write-Host " $text" -ForegroundColor Magenta
    Write-Host "============================================" -ForegroundColor Magenta
}

Write-Header "Terraform - EDA Pipeline Deploy"

Write-Host "[1/4] Checking LocalStack..." -ForegroundColor Cyan

$lsReachable = $false
$endpoints = @(
    "http://127.0.0.1:4566",
    "http://localhost:4566",
    "http://[::1]:4566"
)

try {
    $wslIp = wsl -- ip -4 addr show eth0 2>$null
    if ($wslIp) {
        $m = [regex]::Match($wslIp, 'inet (\d+\.\d+\.\d+\.\d+)')
        if ($m.Success) { $endpoints += "http://$($m.Groups[1].Value):4566" }
    }
} catch {}

foreach ($uri in $endpoints) {
    try {
        $null = Invoke-RestMethod -Uri "$uri/_localstack/health" -ErrorAction Stop -TimeoutSec 3
        $lsReachable = $true
        Write-Host "  [OK] LocalStack reachable at $uri" -ForegroundColor Green
        break
    } catch { continue }
}

if (-not $lsReachable) {
    Write-Host "  [!] LocalStack is not running." -ForegroundColor Yellow
    $input = Read-Host "  Start LocalStack now? (y/n)"
    if ($input -eq "y") {
        & "$scriptDir\start_localstack.ps1" -Force
    } else {
        Write-Host "[ERR] LocalStack is required. Exiting." -ForegroundColor Red
        exit 1
    }
}

Write-Host "[2/4] Initializing Terraform..." -ForegroundColor Cyan
Push-Location $scriptDir

if (-not $SkipInit) {
    & (Get-Terraform) init
    if (-not $?) {
        Write-Host "[ERR] terraform init failed. Is Terraform installed and in PATH?" -ForegroundColor Red
        Pop-Location; exit 1
    }
    Write-Host "  [OK] Terraform initialized." -ForegroundColor Green
} else {
    Write-Host "  [..] Skipped (-SkipInit)." -ForegroundColor DarkYellow
}

Write-Host "[3/4] Applying Terraform configuration..." -ForegroundColor Cyan

$applyArgs = @("apply")
if ($AutoApprove) { $applyArgs += "-auto-approve" }

& (Get-Terraform) $applyArgs
if (-not $?) {
    Write-Host "[ERR] terraform apply failed." -ForegroundColor Red
    Pop-Location; exit 1
}
Write-Host "  [OK] Infrastructure deployed." -ForegroundColor Green

Write-Host "[4/4] Deployment summary:" -ForegroundColor Cyan
$outputs = & (Get-Terraform) output
if ($?) {
    Write-Host $outputs -ForegroundColor White
}

Pop-Location

# Extract base endpoint for the Postman summary
$baseEndpoint = "http://localhost:4566"
$apiId = ""
$jsonOutput = $outputs | Out-String
$match = [regex]::Match($jsonOutput, 'api_endpoint\s*=\s*"([^"]+)"')
if ($match.Success) {
    $baseEndpoint = $match.Groups[1].Value
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Magenta
Write-Host "[OK] Pipeline desplegado via Terraform!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Magenta
Write-Host ""
Write-Host '  Postman / curl endpoints:' -ForegroundColor Cyan
Write-Host '  ---------------------------------------------------------' -ForegroundColor DarkGray
Write-Host '  CREATE (async - via SQS)' -ForegroundColor White
Write-Host "    POST   $baseEndpoint/orders" -ForegroundColor Green
Write-Host '    Body:  {"id_pedido":1, "cliente":"Juan", "total":99.90}' -ForegroundColor DarkGray
Write-Host ''
Write-Host '  LIST' -ForegroundColor White
Write-Host "    GET    $baseEndpoint/orders" -ForegroundColor Green
Write-Host ''
Write-Host '  READ' -ForegroundColor White
Write-Host "    GET    $baseEndpoint/orders/1" -ForegroundColor Green
Write-Host ''
Write-Host '  UPDATE' -ForegroundColor White
Write-Host "    PUT    $baseEndpoint/orders/1" -ForegroundColor Green
Write-Host '    Body:  {"cliente":"Juan Updated", "total":150.00, "estado":"completado"}' -ForegroundColor DarkGray
Write-Host ''
Write-Host '  DELETE' -ForegroundColor White
Write-Host "    DELETE $baseEndpoint/orders/1" -ForegroundColor Green
Write-Host '  ---------------------------------------------------------' -ForegroundColor DarkGray
Write-Host ''
Write-Host '  Quick test:        .\test_message.ps1' -ForegroundColor White
Write-Host '  Check logs:        .\verify.ps1' -ForegroundColor White
