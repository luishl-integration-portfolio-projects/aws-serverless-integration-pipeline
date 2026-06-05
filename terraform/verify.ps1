<#
.SYNOPSIS
    Checks the processor Lambda execution logs.
.DESCRIPTION
    Inspects Lambda executor containers and CloudWatch Logs for the
    processor Lambda function (procesador-pedidos-lambda).
    Replicates the logic from scripts/lambda/verify_logs.ps1.
.PARAMETER FunctionName
    Lambda function name to inspect. Defaults to procesador-pedidos-lambda.
.PARAMETER Tail
    Number of log lines to show from the main container. Default 50.
.EXAMPLE
    .\verify.ps1
    .\verify.ps1 -FunctionName api-gateway-proxy
#>
param(
    [string]$FunctionName = "procesador-pedidos-lambda",
    [int]$Tail = 50
)

$region = "us-east-1"

$podmanBase = @(
    "run", "--rm", "--network=host"
    "-e", "AWS_ACCESS_KEY_ID=mock"
    "-e", "AWS_SECRET_ACCESS_KEY=mock"
    "-e", "AWS_DEFAULT_REGION=$region"
    "amazon/aws-cli"
    "--endpoint-url=http://127.0.0.1:4566"
)

Write-Host "[SEARCH] Checking Lambda logs for '$FunctionName'..." -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------------
# Strategy 1: Main LocalStack container logs
# ------------------------------------------------------------------
Write-Host "--- LocalStack Container Logs (last $Tail lines) ---" -ForegroundColor Cyan
$containerLogs = podman logs --tail $Tail localstack-pipeline 2>&1 | Out-String
$lambdaLines = $containerLogs | Select-String -Pattern "(START|END|REPORT|Procesando|Error|ERROR)" -SimpleMatch
if ($lambdaLines) {
    $lambdaLines | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Host "  (no Lambda invocation entries found in container logs)" -ForegroundColor DarkGray
}
Write-Host ""

# ------------------------------------------------------------------
# Strategy 2: Lambda executor containers
# ------------------------------------------------------------------
Write-Host "--- Lambda Executor Containers ---" -ForegroundColor Cyan
$executors = podman ps -a --filter "name=$FunctionName" --format "{{.Names}}" 2>$null
if ($executors) {
    foreach ($cname in $executors) {
        $cname = $cname.Trim()
        if (-not $cname) { continue }
        Write-Host "  Container: $cname" -ForegroundColor DarkGray
        $execLogs = podman logs $cname --tail 50 2>&1 | Out-String
        $execLogs -split "`n" | ForEach-Object {
            if ($_.Trim()) { Write-Host "    $_" -ForegroundColor White }
        }
    }
} else {
    Write-Host "  (no Lambda executor containers found)" -ForegroundColor DarkGray
}
Write-Host ""

# ------------------------------------------------------------------
# Strategy 3: CloudWatch Logs
# ------------------------------------------------------------------
Write-Host "--- CloudWatch Logs ---" -ForegroundColor Cyan
$logGroupName = "/aws/lambda/$FunctionName"
$logGroups = & podman $podmanBase logs describe-log-groups --log-group-name-prefix $logGroupName 2>&1 | Out-String

if ($logGroups -match '"logGroupName"') {
    $streams = & podman $podmanBase logs describe-log-streams --log-group-name $logGroupName --order-by LastEventTime --descending --max-items 3 2>&1 | Out-String
    if ($streams -match '"logStreamName"') {
        $streamNames = @()
        $matches = [regex]::Matches($streams, '"logStreamName": "([^"]+)"')
        foreach ($m in $matches) { $streamNames += $m.Groups[1].Value }
        foreach ($streamName in $streamNames) {
            Write-Host "  Stream: $streamName" -ForegroundColor DarkGray
            $events = & podman $podmanBase logs get-log-events --log-group-name $logGroupName --log-stream-name "$streamName" 2>&1 | Out-String
            $eventMessages = [regex]::Matches($events, '"message": "([^"]+)"')
            foreach ($em in $eventMessages) {
                $msg = $em.Groups[1].Value -replace '\\n', "`n  "
                Write-Host "  $msg" -ForegroundColor White
            }
        }
    } else {
        Write-Host "  (no log streams yet)" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  (CloudWatch log group not found. Lambda may not have been invoked yet)" -ForegroundColor DarkGray
}
Write-Host ""

# ------------------------------------------------------------------
# Summary: Queue status
# ------------------------------------------------------------------
Write-Host "--- Summary ---" -ForegroundColor Cyan
$queueUrl = "http://127.0.0.1:4566/000000000000/cola-pedidos-ecommerce"
$queueCheck = & podman $podmanBase sqs receive-message --queue-url $queueUrl --max-number-of-messages 5 --wait-time-seconds 2 2>&1 | Out-String
if ($queueCheck -match '"Body"') {
    Write-Host "[WARN] There are still messages in the queue (not processed yet)." -ForegroundColor Yellow
} else {
    Write-Host "[OK] Queue is empty -- all messages have been consumed." -ForegroundColor Green
}
Write-Host ""
Write-Host "[DONE] Verification complete." -ForegroundColor Green
