param(
    [switch]$Recreate
)

$containerName = "localstack-pipeline"

function Get-LocalStackHealthUri {
    $candidates = @(
        "http://127.0.0.1:4566",
        "http://localhost:4566",
        "http://[::1]:4566"
    )

    try {
        $wslIpOutput = wsl -- ip -4 addr show eth0 2>$null
        if ($wslIpOutput) {
            $match = [regex]::Match($wslIpOutput, 'inet (\d+\.\d+\.\d+\.\d+)')
            if ($match.Success) {
                $candidates += "http://$($match.Groups[1].Value):4566"
            }
        }
    } catch {}

    foreach ($uri in $candidates) {
        try {
            $null = Invoke-RestMethod -Uri "$uri/_localstack/health" -ErrorAction Stop -TimeoutSec 2
            return $uri
        } catch {
            continue
        }
    }

    return $null
}

function Wait-ForLocalStack {
    Write-Host "[3/5] Waiting for LocalStack..." -ForegroundColor Cyan

    $attempts = 0
    $healthUri = $null
    $ready = $false

    do {
        $attempts++
        Start-Sleep -Seconds 2

        $healthUri = Get-LocalStackHealthUri

        if ($healthUri) {
            try {
                $health = Invoke-RestMethod -Uri "$healthUri/_localstack/health" -ErrorAction Stop

                $sqsReady = $health.services.sqs -in @("available", "running")
                $lambdaReady = $health.services.lambda -in @("available", "running")

                $ready = $sqsReady -and $lambdaReady

                if (-not $ready) {
                    Write-Host "  [..] SQS=$($health.services.sqs) Lambda=$($health.services.lambda) (attempt $attempts)" -ForegroundColor DarkYellow
                }

            } catch {
                $ready = $false
                Write-Host "  [..] Health unreachable (attempt $attempts)" -ForegroundColor DarkYellow
            }
        } else {
            Write-Host "  [..] Waiting for endpoint... (attempt $attempts)" -ForegroundColor DarkYellow
        }

    } while (-not $ready -and $attempts -lt 40)

    if (-not $ready) {
        Write-Host "[ERR] LocalStack not ready in time" -ForegroundColor Red
        exit 1
    }

    Write-Host "  [OK] LocalStack ready via $healthUri" -ForegroundColor Green

    Start-Sleep -Seconds 8
}

# STEP 1: cleanup existing
$existing = podman ps -a --filter "name=$containerName" --format "{{.Names}}" 2>$null

if ($existing) {
    if ($Recreate) {
        Write-Host "[1/5] Removing existing container..." -ForegroundColor Cyan
        podman rm -f $containerName
    } else {
        Write-Host "[1/5] Container already exists." -ForegroundColor Yellow
        $input = Read-Host "Stop and recreate? (y/n)"
        if ($input -eq "y") {
            podman rm -f $containerName
        } else {
            Write-Host "Using existing container..." -ForegroundColor Green
            Wait-ForLocalStack
            return
        }
    }
}

# STEP 2: create custom Podman network + start LocalStack
Write-Host "[1/5] Creating Podman network 'ls-net'..." -ForegroundColor Cyan
podman network create ls-net 2>$null
Write-Host "  -> Network ready." -ForegroundColor DarkGray

Write-Host "[2/5] Starting LocalStack..." -ForegroundColor Cyan
podman run -d `
    --name $containerName `
    --network ls-net `
    -p 4566:4566 `
    -p 4510-4559:4510-4559 `
    -v /var/run/docker.sock:/var/run/docker.sock `
    -e LAMBDA_EXECUTOR=docker `
    -e LAMBDA_DOCKER_NETWORK=ls-net `
    -e DEBUG=1 `
    -e SERVICES=lambda,sqs,logs `
    localstack/localstack:4.0

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERR] Failed to start LocalStack" -ForegroundColor Red
    exit 1
}

# STEP 3: wait ready
Wait-ForLocalStack

Write-Host "[3/5] LocalStack is ready" -ForegroundColor Green
