param(
    [switch]$SkipCleanup,
    [switch]$SkipStart,
    [switch]$SkipTestMessage
)

$scriptRoot  = $PSScriptRoot

Write-Host "============================================" -ForegroundColor Magenta
Write-Host " AWS Serverless Integration Pipeline - Deploy" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta
Write-Host ""

function Step-Header {
    param([int]$Num, [string]$Label)
    Write-Host ("--- Step {0}: {1} ---" -f $Num, $Label) -ForegroundColor Cyan
}

# Step 0: Cleanup old Lambda executors
Step-Header -Num 0 -Label "Cleanup"
if (-not $SkipCleanup) {
    & "$scriptRoot\cleanup_containers.ps1" -All
} else {
    Write-Host "  -> Skipping cleanup (--SkipCleanup)." -ForegroundColor Yellow
}

# Step 1: Start LocalStack
Step-Header -Num 1 -Label "LocalStack"
if (-not $SkipStart) {
    & "$scriptRoot\start_localstack.ps1"
    if ($LASTEXITCODE -ne 0) { Write-Host "[ERR] Aborting." -ForegroundColor Red; exit 1 }
} else {
    Write-Host "  -> Skipping start (--SkipStart). Verifying connectivity..." -ForegroundColor Yellow
    $lsUri = $null; $candidates = @("http://127.0.0.1:4566", "http://localhost:4566", "http://[::1]:4566")
    try { $w = wsl -- ip -4 addr show eth0 2>$null; if ($w) { $m = [regex]::Match($w, 'inet (\d+\.\d+\.\d+\.\d+)'); if ($m.Success) { $candidates += "http://$($m.Groups[1].Value):4566" } } } catch {}
    foreach ($u in $candidates) { try { $null = Invoke-RestMethod -Uri "$u/_localstack/health" -ErrorAction Stop -TimeoutSec 2; $lsUri = $u; break } catch { continue } }
    if ($lsUri) { Write-Host "  [OK] LocalStack is reachable." -ForegroundColor Green }
    else { Write-Host "[ERR] LocalStack is not reachable." -ForegroundColor Red; exit 1 }
}

# Step 2: Create SQS Queue
Step-Header -Num 2 -Label "SQS Queue"
& "$scriptRoot\queues\create_queue.ps1"
if ($LASTEXITCODE -ne 0) { Write-Host "[ERR] Aborting." -ForegroundColor Red; exit 1 }

# Step 3: Create API Gateway REST endpoint
Step-Header -Num 3 -Label "API Gateway"
& "$scriptRoot\api\create_rest_api.ps1"
if ($LASTEXITCODE -ne 0) { Write-Host "[WARN] API Gateway may have failed." -ForegroundColor Yellow }

# Step 4: Package Lambda
Step-Header -Num 4 -Label "Lambda Package"
& "$scriptRoot\lambda\package_lambda.ps1"
if ($LASTEXITCODE -ne 0) { Write-Host "[ERR] Aborting." -ForegroundColor Red; exit 1 }

# Step 5: Deploy Lambda
Step-Header -Num 5 -Label "Lambda Deployment"
& "$scriptRoot\lambda\deploy_lambda.ps1"
if ($LASTEXITCODE -ne 0) { Write-Host "[ERR] Aborting." -ForegroundColor Red; exit 1 }

# Step 6: Create SQS -> Lambda Trigger
Step-Header -Num 6 -Label "SQS -> Lambda Trigger"
& "$scriptRoot\lambda\create_trigger.ps1"
if ($LASTEXITCODE -ne 0) { Write-Host "[ERR] Aborting." -ForegroundColor Red; exit 1 }

# Step 7: Send Test Message
Step-Header -Num 7 -Label "Test Message"
if (-not $SkipTestMessage) {
    & "$scriptRoot\queues\publish_message_to_queue.ps1"
    if ($LASTEXITCODE -ne 0) { Write-Host "[WARN] Test message may have failed." -ForegroundColor Yellow }
} else {
    Write-Host "  -> Skipping test message (--SkipTestMessage)." -ForegroundColor Yellow
}

# Give Lambda a moment to process
Write-Host "  [..] Waiting 3 seconds for Lambda to process..." -ForegroundColor DarkYellow
Start-Sleep -Seconds 3

# Step 8: Verify
Step-Header -Num 8 -Label "Verify"
& "$scriptRoot\lambda\verify_logs.ps1"

Write-Host ""
Write-Host "============================================" -ForegroundColor Magenta
Write-Host "[OK] Deployment complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Magenta
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Cyan
Write-Host "  - Test with Postman:     POST http://127.0.0.1:4566/restapis/<api-id>/dev/_user_request_/orders" -ForegroundColor White
Write-Host "  - Publish more messages: .\scripts\queues\publish_message_to_queue.ps1" -ForegroundColor White
Write-Host "  - Check logs again:      .\scripts\lambda\verify_logs.ps1" -ForegroundColor White
Write-Host "  - Read from queue:       .\scripts\queues\receive_message.ps1" -ForegroundColor White
Write-Host "  - Tear down:             .\scripts\teardown.ps1" -ForegroundColor White
