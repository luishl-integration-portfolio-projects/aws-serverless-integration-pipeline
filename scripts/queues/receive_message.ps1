<#
.SYNOPSIS
    Reads (polls) messages from the SQS queue without deleting them.
.DESCRIPTION
    Useful for debugging — shows what's currently in the queue.
    Messages remain in the queue after reading (VisibilityTimeout=0).
#>
param(
    [int]$MaxMessages = 5,
    [int]$WaitSeconds = 3
)

$queueUrl = "http://127.0.0.1:4566/000000000000/cola-pedidos-ecommerce"

Write-Host "[1/2] Polling SQS queue 'cola-pedidos-ecommerce'..." -ForegroundColor Cyan

$result = podman run --rm --network=host -e AWS_ACCESS_KEY_ID=mock -e AWS_SECRET_ACCESS_KEY=mock -e AWS_DEFAULT_REGION=us-east-1 amazon/aws-cli --endpoint-url=http://127.0.0.1:4566 sqs receive-message --queue-url $queueUrl --max-number-of-messages $MaxMessages --wait-time-seconds $WaitSeconds 2>&1

if ($result -match '"Body"') {
    $bodies = [regex]::Matches($result, '"Body": "([^"]+)"')
    Write-Host "  📨 Messages in queue: $($bodies.Count)" -ForegroundColor Yellow
    for ($i = 0; $i -lt $bodies.Count; $i++) {
        Write-Host "  [$($i+1)] $($bodies[$i].Groups[1].Value)" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "  [INFO] Messages remain in the queue until Lambda processes them." -ForegroundColor DarkGray
} else {
    Write-Host "  [OK] Queue is empty (or no messages available)." -ForegroundColor Green
    Write-Host "  All pending messages have been consumed." -ForegroundColor DarkGray
}
