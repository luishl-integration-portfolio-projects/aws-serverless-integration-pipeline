param(
    [switch]$Hard
)

$region       = "us-east-1"
$functionName = "procesador-pedidos-lambda"
$queueName    = "cola-pedidos-ecommerce"
$queueArn     = "arn:aws:sqs:$region:000000000000:$queueName"

$podmanBase = @(
    "run", "--rm", "--network=host"
    "-e", "AWS_ACCESS_KEY_ID=mock"
    "-e", "AWS_SECRET_ACCESS_KEY=mock"
    "-e", "AWS_DEFAULT_REGION=$region"
    "amazon/aws-cli"
    "--endpoint-url=http://127.0.0.1:4566"
)

Write-Host "============================================" -ForegroundColor Magenta
Write-Host " AWS Serverless Integration Pipeline - Teardown" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta

# 1. Delete event source mappings
Write-Host ""
Write-Host "[1/4] Removing SQS -> Lambda event source mappings..." -ForegroundColor Cyan
$mappings = & podman $podmanBase lambda list-event-source-mappings --function-name $functionName 2>&1 | Out-String
$uuids = [regex]::Matches($mappings, '"UUID": "([^"]+)"')
if ($uuids.Count -gt 0) {
    foreach ($uuid in $uuids) {
        $uuidVal = $uuid.Groups[1].Value
        Write-Host "  -> Deleting mapping $uuidVal..." -ForegroundColor Yellow
        & podman $podmanBase lambda delete-event-source-mapping --uuid $uuidVal 2>&1 | Out-Null
    }
    Write-Host "[OK] Event source mappings deleted." -ForegroundColor Green
} else {
    Write-Host "  -> No event source mappings found." -ForegroundColor DarkGray
}

# 2. Delete Lambda function
Write-Host "[2/4] Deleting Lambda function '$functionName'..." -ForegroundColor Cyan
$fnCheck = & podman $podmanBase lambda get-function --function-name $functionName 2>&1 | Out-String
if ($fnCheck -match '"FunctionName"') {
    & podman $podmanBase lambda delete-function --function-name $functionName 2>&1 | Out-Null
    Write-Host "[OK] Lambda function deleted." -ForegroundColor Green
} else {
    Write-Host "  -> Lambda function not found." -ForegroundColor DarkGray
}

# 3. Delete SQS queue
Write-Host "[3/4] Deleting SQS queue '$queueName'..." -ForegroundColor Cyan
$queueCheck = & podman $podmanBase sqs get-queue-url --queue-name $queueName 2>&1 | Out-String
if ($queueCheck -match '"QueueUrl"') {
    $queueUrl = "http://127.0.0.1:4566/000000000000/$queueName"
    & podman $podmanBase sqs delete-queue --queue-url $queueUrl 2>&1 | Out-Null
    Write-Host "[OK] SQS queue deleted." -ForegroundColor Green
} else {
    Write-Host "  -> Queue not found." -ForegroundColor DarkGray
}

# 4. Stop LocalStack container
Write-Host "[4/4] Stopping LocalStack container..." -ForegroundColor Cyan
$containerName = "localstack-pipeline"
$running = podman ps --filter "name=$containerName" --format "{{.Names}}" 2>$null
if ($running) {
    if ($Hard) {
        podman rm -f $containerName 2>$null
        Write-Host "[OK] Container '$containerName' force-removed." -ForegroundColor Green
    } else {
        podman stop $containerName 2>$null
        Write-Host "[OK] Container '$containerName' stopped." -ForegroundColor Green
    }
} else {
    Write-Host "  -> Container '$containerName' is not running." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Magenta
Write-Host "[OK] Teardown complete." -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Magenta
