param(
    [string]$Body = '{"id_pedido": 1001, "cliente": "lherna06", "total": 89.95, "productos": ["Widget A", "Gadget B"], "moneda": "EUR"}'
)

$queueName = "cola-pedidos-ecommerce"
$functionName = "procesador-pedidos-lambda"
$accountId = "000000000000"
$region = "us-east-1"

$queueUrl = "http://127.0.0.1:4566/$accountId/$queueName"

Write-Host "`n[1/5] Sending message to SQS..." -ForegroundColor Cyan
Write-Host "  -> Queue URL: $queueUrl" -ForegroundColor DarkGray
Write-Host "  -> Body: $Body" -ForegroundColor DarkGray

# FIX: no file, no mount, no hacks → direct JSON
$result = podman run --rm --network=host `
    -e AWS_ACCESS_KEY_ID=mock `
    -e AWS_SECRET_ACCESS_KEY=mock `
    -e AWS_DEFAULT_REGION=$region `
    amazon/aws-cli `
    --endpoint-url=http://127.0.0.1:4566 `
    sqs send-message `
    --queue-url $queueUrl `
    --message-body "$Body" 2>&1

if ($result -match '"MessageId"') {
    $messageId = ($result | Select-String '"MessageId": "([^"]+)"').Matches[0].Groups[1].Value
    Write-Host "[OK] Message sent: $messageId" -ForegroundColor Green
} else {
    Write-Host "[ERR] Failed sending message" -ForegroundColor Red
    Write-Host $result
    exit 1
}

# =========================================================
# 🔎 STEP 2: DIAGNÓSTICO AUTOMÁTICO SQS → LAMBDA
# =========================================================

Write-Host "`n[2/5] Checking SQS queue..." -ForegroundColor Cyan

$queueCheck = podman run --rm --network=host `
    -e AWS_ACCESS_KEY_ID=mock `
    -e AWS_SECRET_ACCESS_KEY=mock `
    -e AWS_DEFAULT_REGION=$region `
    amazon/aws-cli `
    --endpoint-url=http://127.0.0.1:4566 `
    sqs get-queue-url --queue-name $queueName 2>&1

if ($queueCheck -notmatch "QueueUrl") {
    Write-Host "[ERR] Queue not found" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Queue exists" -ForegroundColor Green

# =========================================================
Write-Host "`n[3/5] Checking Lambda function..." -ForegroundColor Cyan

$lambdaCheck = podman run --rm --network=host `
    -e AWS_ACCESS_KEY_ID=mock `
    -e AWS_SECRET_ACCESS_KEY=mock `
    -e AWS_DEFAULT_REGION=$region `
    amazon/aws-cli `
    --endpoint-url=http://127.0.0.1:4566 `
    lambda get-function --function-name $functionName 2>&1

if ($lambdaCheck -notmatch "FunctionName") {
    Write-Host "[ERR] Lambda not found" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Lambda exists" -ForegroundColor Green

# =========================================================
Write-Host "`n[4/5] Checking event source mapping..." -ForegroundColor Cyan

$queueArn = "arn:aws:sqs:$region`:$accountId`:$queueName"

$mapping = podman run --rm --network=host `
    -e AWS_ACCESS_KEY_ID=mock `
    -e AWS_SECRET_ACCESS_KEY=mock `
    -e AWS_DEFAULT_REGION=$region `
    amazon/aws-cli `
    --endpoint-url=http://127.0.0.1:4566 `
    lambda list-event-source-mappings `
    --function-name $functionName `
    --event-source-arn $queueArn 2>&1

if ($mapping -match "UUID") {
    $uuid = ($mapping | Select-String '"UUID": "([^"]+)"').Matches[0].Groups[1].Value
    Write-Host "[OK] Mapping active: $uuid" -ForegroundColor Green
} else {
    Write-Host "[WARN] No event source mapping found" -ForegroundColor Yellow
}

# =========================================================
Write-Host "`n[5/5] Checking pending messages..." -ForegroundColor Cyan

$pending = podman run --rm --network=host `
    -e AWS_ACCESS_KEY_ID=mock `
    -e AWS_SECRET_ACCESS_KEY=mock `
    -e AWS_DEFAULT_REGION=$region `
    amazon/aws-cli `
    --endpoint-url=http://127.0.0.1:4566 `
    sqs get-queue-attributes `
    --queue-url $queueUrl `
    --attribute-names ApproximateNumberOfMessages 2>&1

Write-Host "[INFO] Queue state: $pending"

Write-Host "`n✅ DONE. If Lambda is correct, logs should show processing now." -ForegroundColor Green