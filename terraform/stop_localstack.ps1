<#
.SYNOPSIS
    Stops and removes the LocalStack Podman container.
.DESCRIPTION
    Stops (or force-removes) the 'localstack-pipeline' container.
    Keeps the Podman network 'ls-net' intact for future starts.
.PARAMETER Hard
    If set, force-removes the container (podman rm -f). Otherwise stops it gracefully.
.PARAMETER RemoveNetwork
    If set, also removes the 'ls-net' Podman network.
.EXAMPLE
    .\stop_localstack.ps1
    .\stop_localstack.ps1 -Hard
    .\stop_localstack.ps1 -Hard -RemoveNetwork
#>
param(
    [switch]$Hard,
    [switch]$RemoveNetwork
)

$containerName = "localstack-pipeline"
$networkName   = "ls-net"

Write-Host "--- Stopping LocalStack ---" -ForegroundColor Cyan

# 1. Stop / remove container
$running = podman ps --filter "name=^$containerName$" --format "{{.Names}}" 2>$null

if ($running) {
    if ($Hard) {
        podman rm -f $containerName 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Host "[OK] Container '$containerName' force-removed." -ForegroundColor Green }
        else                     { Write-Host "[WARN] Could not force-remove container." -ForegroundColor Yellow }
    } else {
        podman stop $containerName 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Host "[OK] Container '$containerName' stopped." -ForegroundColor Green }
        else                     { Write-Host "[WARN] Could not stop container." -ForegroundColor Yellow }
    }
} else {
    Write-Host "[OK] Container '$containerName' is not running." -ForegroundColor Green
}

# 2. Optionally remove network
if ($RemoveNetwork) {
    $existingNet = podman network ls --filter "name=^$networkName$" --format "{{.Name}}" 2>$null
    if ($existingNet) {
        podman network rm $networkName 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Host "[OK] Network '$networkName' removed." -ForegroundColor Green }
        else                     { Write-Host "[WARN] Could not remove network '$networkName'." -ForegroundColor Yellow }
    } else {
        Write-Host "[OK] Network '$networkName' does not exist." -ForegroundColor Green
    }
}

Write-Host "[DONE] LocalStack stopped." -ForegroundColor Green
