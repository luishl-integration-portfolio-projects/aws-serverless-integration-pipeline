<#
.SYNOPSIS
    Starts LocalStack in a Podman container for the Terraform-managed EDA pipeline.
.DESCRIPTION
    Creates a dedicated Podman network (ls-net), starts LocalStack 4.x with
    Lambda, SQS, API Gateway, IAM, and CloudWatch Logs enabled, and waits
    for health checks to pass.

    Replicates the logic from scripts/start_localstack.ps1 as a self-contained
    script for the Terraform workflow.
.PARAMETER Recreate
    If set, removes any existing 'localstack-pipeline' container before starting.
    Otherwise prompts interactively.
.PARAMETER Force
    Same as -Recreate but skips the prompt entirely.
.EXAMPLE
    .\start_localstack.ps1 -Force
#>
param(
    [switch]$Recreate,
    [switch]$Force
)

$containerName = "localstack-pipeline"
$networkName   = "ls-net"
$imageTag = "localstack/localstack:4.0"

# Colour helpers
function Write-Step($num, $text) { Write-Host "[$num/$text]" -ForegroundColor Cyan }
function Write-OK($text)         { Write-Host "  [OK] $text" -ForegroundColor Green }
function Write-Warn($text)       { Write-Host "  [!] $text" -ForegroundColor Yellow }
function Write-Err($text)        { Write-Host "[ERR] $text" -ForegroundColor Red; exit 1 }

# Health check: polls LocalStack until SQS and Lambda are available
function Wait-LocalStackReady {
    param([int]$MaxAttempts = 40)

    Write-Step "4" "Waiting for LocalStack to become ready..."

    $attempt = 0
    $ready = $false

    while (-not $ready -and $attempt -lt $MaxAttempts) {
        $attempt++
        Start-Sleep -Seconds 2

        try {
            $health = Invoke-RestMethod -Uri "http://127.0.0.1:4566/_localstack/health" -ErrorAction Stop -TimeoutSec 3

            $sqsReady    = $health.services.sqs    -in @("available", "running")
            $lambdaReady = $health.services.lambda -in @("available", "running")

            if ($sqsReady -and $lambdaReady) {
                $ready = $true
            } else {
                Write-Host "  [..] SQS=$($health.services.sqs) Lambda=$($health.services.lambda) (attempt $attempt)" -ForegroundColor DarkYellow
            }
        } catch {
            Write-Host "  [..] Health endpoint unreachable (attempt $attempt)" -ForegroundColor DarkYellow
        }
    }

    if (-not $ready) { Write-Err "LocalStack did not become ready within $MaxAttempts attempts." }
    Write-OK "LocalStack is ready."
    Start-Sleep -Seconds 5
}

# ------------------------------------------------------------------
# STEP 1 — Handle existing container
# ------------------------------------------------------------------
Write-Step "1" "Checking existing container..."

$existing = podman ps -a --filter "name=^$containerName$" --format "{{.Names}}" 2>$null

if ($existing) {
    $doRemove = $Force -or $Recreate
    if (-not $doRemove) {
        $input = Read-Host "  Container '$containerName' already exists. Stop and recreate? (y/n)"
        $doRemove = $input -eq "y"
    }

    if ($doRemove) {
        Write-Host "  -> Removing existing container..." -ForegroundColor Yellow
        podman rm -f $containerName 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-OK "Container removed." }
        else                     { Write-Err "Failed to remove existing container." }
    } else {
        Write-Host "  -> Using existing container." -ForegroundColor Yellow
        Wait-LocalStackReady
        Write-Step "5" "Done. LocalStack is ready for Terraform."
        return
    }
} else {
    Write-OK "No existing container."
}

# ------------------------------------------------------------------
# STEP 2 — Create Podman network (idempotent)
# ------------------------------------------------------------------
Write-Step "2" "Creating Podman network '$networkName'..."

$existingNet = podman network ls --filter "name=^$networkName$" --format "{{.Name}}" 2>$null
if (-not $existingNet) {
    podman network create $networkName 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-OK "Network '$networkName' created." }
    else                     { Write-Warn "Network creation may have failed (it may already exist)." }
} else {
    Write-OK "Network '$networkName' already exists."
}

# ------------------------------------------------------------------
# STEP 3 — Start LocalStack container
# ------------------------------------------------------------------
Write-Step "3" "Starting LocalStack container '$containerName'..."

podman run -d `
    --name $containerName `
    --network $networkName `
    -p 4566:4566 `
    -p 4510-4559:4510-4559 `
    -v /var/run/docker.sock:/var/run/docker.sock `
    -e LAMBDA_EXECUTOR=docker `
    -e LAMBDA_DOCKER_NETWORK=$networkName `
    -e DEBUG=1 `
    -e SERVICES=lambda,sqs,logs,apigateway,iam `
    $imageTag 2>&1 | Out-Null

if ($LASTEXITCODE -ne 0) { Write-Err "Failed to start LocalStack container." }
Write-OK "Container started."

# ------------------------------------------------------------------
# STEP 4 — Wait for LocalStack health checks
# ------------------------------------------------------------------
Wait-LocalStackReady

Write-Step "5" "Done. LocalStack is ready for Terraform."
