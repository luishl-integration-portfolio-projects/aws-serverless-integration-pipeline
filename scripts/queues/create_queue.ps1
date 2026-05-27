<#
.SYNOPSIS
    Creates the SQS queue for e-commerce orders.
.DESCRIPTION
    Creates 'cola-pedidos-ecommerce' queue in LocalStack.
    Idempotent — if the queue already exists, LocalStack returns the existing URL.
#>
Write-Host "[1/2] Creating SQS queue 'cola-pedidos-ecommerce'..." -ForegroundColor Cyan

$result = podman run --rm --network=host -e AWS_ACCESS_KEY_ID=mock -e AWS_SECRET_ACCESS_KEY=mock -e AWS_DEFAULT_REGION=us-east-1 amazon/aws-cli --endpoint-url=http://127.0.0.1:4566 sqs create-queue --queue-name cola-pedidos-ecommerce 2>&1

if ($LASTEXITCODE -eq 0 -and $result -match '"QueueUrl"') {
    $url = ($result | Select-String '"QueueUrl": "([^"]+)"').Matches[0].Groups[1].Value
    Write-Host "  [OK] Queue created: $url" -ForegroundColor Green
} else {
    Write-Host "  [WARN] Could not verify queue creation." -ForegroundColor Yellow
    Write-Host $result
}