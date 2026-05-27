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

# Strategy 1: Check LocalStack container logs for Lambda output
Write-Host "--- LocalStack Container Logs (last $Tail lines) ---" -ForegroundColor Cyan
$containerLogs = podman logs --tail $Tail localstack-pipeline 2>&1 | Out-String
$lambdaLines = $containerLogs | Select-String -Pattern "(START|END|REPORT|Procesando|[OK]|[ERR]|ERROR)" -SimpleMatch
if ($lambdaLines) {
    $lambdaLines | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Host "  (no Lambda invocation entries found in container logs)" -ForegroundColor DarkGray
}

Write-Host ""

# Strategy 2: Try to fetch CloudWatch log groups
Write-Host "--- CloudWatch Logs ---" -ForegroundColor Cyan
$logGroupName = "/aws/lambda/$FunctionName"
$logGroups = & podman $podmanBase logs describe-log-groups --log-group-name-prefix $logGroupName 2>&1 | Out-String

if ($logGroups -match '"logGroupName"') {
    $streams = & podman $podmanBase logs describe-log-streams --log-group-name $logGroupName --order-by LastEventTime --descending --max-items 3 2>&1 | Out-String
    if ($streams -match '"logStreamName"') {
        $streamNames = @()
        $matches = [regex]::Matches($streams, '"logStreamName": "([^"]+)"')
        foreach ($m in $matches) {
            $streamNames += $m.Groups[1].Value
        }
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
Write-Host "--- Summary ---" -ForegroundColor Cyan
$queueUrl = "http://127.0.0.1:4566/000000000000/cola-pedidos-ecommerce"
$queueCheck = & podman $podmanBase sqs receive-message --queue-url $queueUrl --max-number-of-messages 5 --wait-time-seconds 2 2>&1 | Out-String

if ($queueCheck -match '"Body"') {
    Write-Host "[WARN] There are still messages in the queue (not processed yet)." -ForegroundColor Yellow
} else {
    Write-Host "[OK] Queue is empty -- all messages have been processed." -ForegroundColor Green
}
