<#
.SYNOPSIS
    Destroys all Terraform-managed infrastructure.
.DESCRIPTION
    1. Runs terraform destroy to remove all AWS resources
    2. Optionally stops the LocalStack container
.PARAMETER AutoApprove
    If set, passes -auto-approve (skips interactive confirmation).
.PARAMETER AlsoStopLocalStack
    If set, also stops the LocalStack container after destroying infrastructure.
.PARAMETER HardStopLocalStack
    If set with -AlsoStopLocalStack, force-removes the container instead of graceful stop.
.EXAMPLE
    .\destroy.ps1
    .\destroy.ps1 -AutoApprove
    .\destroy.ps1 -AutoApprove -AlsoStopLocalStack
    .\destroy.ps1 -AutoApprove -AlsoStopLocalStack -HardStopLocalStack
#>
param(
    [switch]$AutoApprove,
    [switch]$AlsoStopLocalStack,
    [switch]$HardStopLocalStack
)

$scriptDir = $PSScriptRoot

# Load portable terraform resolver
. "$scriptDir\lib\Get-Terraform.ps1"

Write-Host "============================================" -ForegroundColor Magenta
Write-Host " Terraform — Destroy Infrastructure" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta

# Step 1: terraform destroy
Write-Host "[1/2] Destroying Terraform-managed resources..." -ForegroundColor Cyan

Push-Location $scriptDir

$destroyArgs = @("destroy")
if ($AutoApprove) { $destroyArgs += "-auto-approve" }

& (Get-Terraform) $destroyArgs
if (-not $?) {
    Write-Host "[WARN] terraform destroy reported errors. Check output above." -ForegroundColor Yellow
} else {
    Write-Host "  [OK] All resources destroyed." -ForegroundColor Green
}

Pop-Location

# Step 2: Optionally stop LocalStack
if ($AlsoStopLocalStack) {
    Write-Host "[2/2] Stopping LocalStack..." -ForegroundColor Cyan
    $stopArgs = @()
    if ($HardStopLocalStack) { $stopArgs += "-Hard" }
    & "$scriptDir\stop_localstack.ps1" @stopArgs
} else {
    Write-Host "[2/2] Skipped (LocalStack kept running)." -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "[DONE] Teardown complete." -ForegroundColor Green
