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
            if ($match.Success) { $candidates += "http://$($match.Groups[1].Value):4566" }
        }
    } catch {}
    foreach ($uri in $candidates) {
        try {
            $null = Invoke-RestMethod -Uri "$uri/_localstack/health" -ErrorAction Stop -TimeoutSec 2
            return $uri
        } catch { continue }
    }
    return $null
}

function Wait-ForLocalStack {
    Write-Host "[2/5] Waiting for LocalStack services to become available..." -ForegroundColor Cyan
    $attempts = 0
    $healthUri = $null
    do {
        $attempts++
        Start-Sleep -Seconds 2
        $healthUri = Get-LocalStackHealthUri
        if ($healthUri) {
            try {
                $health = Invoke-RestMethod -Uri "$healthUri/_localstack/health" -ErrorAction Stop
                $sqsReady   = $health.services.sqs   -in @("available", "running")
                $lambdaReady = $health.services.lambda -in @("available", "running")
                $ready = $sqsReady -and $lambdaReady
                if (-not $ready) {
                    Write-Host "  [..] SQS=$sqsReady Lambda=$lambdaReady (attempt $attempts)" -ForegroundColor DarkYellow
                }
            } catch {
                $ready = $false
                Write-Host "  [..] Health endpoint unreachable (attempt $attempts)" -ForegroundColor DarkYellow
            }
        } else {
            $ready = $false
            Write-Host "  [..] Waiting for LocalStack endpoint... (attempt $attempts)" -ForegroundColor DarkYellow
        }
    } while ((-not $ready) -and $attempts -lt 30)

    if (-not $ready) {
        Write-Host "[ERR] LocalStack did not become ready within 60 seconds." -ForegroundColor Red
        exit 1
    }
    Write-Host "  [OK] All services available (SQS, Lambda) via $healthUri" -ForegroundColor Green
}

# Step 1: Check for previous container
$existing = podman ps --all --filter "name=$containerName" --format "{{.Names}}" 2>$null
if ($existing) {
    $running = podman ps --filter "name=$containerName" --format "{{.Names}}" 2>$null
    if ($running) {
        if ($Recreate) {
            Write-Host "[1/5] Removing existing container '$containerName'..." -ForegroundColor Cyan
            podman rm -f $containerName 2>$null
        } else {
            Write-Host "[1/5] LocalStack container '$containerName' is already running." -ForegroundColor Yellow
            $input = Read-Host "  ? Do you want to stop it and start a new one? (y/n, default: n)"
            if ($input -eq "y") {
                Write-Host "  -> Stopping and removing container..." -ForegroundColor Cyan
                podman rm -f $containerName 2>$null
            } else {
                Write-Host "  -> Using existing container." -ForegroundColor Green
                Wait-ForLocalStack
                return
            }
        }
    } else {
        Write-Host "[1/5] Removing stopped container '$containerName'..." -ForegroundColor Cyan
        podman rm $containerName 2>$null
    }
}

# Step 2: Start container
Write-Host "[1/5] Starting LocalStack container '$containerName'..." -ForegroundColor Cyan
podman run --rm -d --name $containerName -p 4566:4566 -p 4510-4559:4510-4559 -v /var/run/docker.sock:/var/run/docker.sock localstack/localstack:3.0

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERR] Failed to start LocalStack container." -ForegroundColor Red
    exit 1
}

# Step 3: Wait for health
Wait-ForLocalStack

Write-Host "[3/5] LocalStack is ready at http://127.0.0.1:4566" -ForegroundColor Green
