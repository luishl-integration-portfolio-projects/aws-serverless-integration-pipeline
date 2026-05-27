
$functionName  = "procesador-pedidos-lambda"
$queueName     = "cola-pedidos-ecommerce"
$accountId     = "000000000000"
$region        = "us-east-1"

$queueArn      = "arn:aws:sqs:$region`:$accountId`:$queueName"
$queueUrl      = "http://127.0.0.1:4566/$accountId/$queueName"

# 🔥 FIX: missing comma here
$podmanBase = @(
    "run", "--rm", "--network=host",
    "-e", "AWS_ACCESS_KEY_ID=mock",
    "-e", "AWS_SECRET_ACCESS_KEY=mock",
    "-e", "AWS_DEFAULT_REGION=$region",
    "amazon/aws-cli",
    "--endpoint-url=http://127.0.0.1:4566"
)

# Step 1: Verify queue exists
Write-Host "[1/4] Verifying SQS queue '$queueName' exists..." -ForegroundColor Cyan

$queueCheck = & podman $podmanBase sqs get-queue-url --queue-name $queueName 2>&1 | Out-String

if ($queueCheck -notmatch '"QueueUrl"') {
    Write-Host "[ERR] Queue '$queueName' not found. Create it first." -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Queue found." -ForegroundColor Green

# Step 2: Verify Lambda function exists
Write-Host "[2/4] Verifying Lambda function..." -ForegroundColor Cyan

$fnCheck = & podman $podmanBase lambda get-function --function-name $functionName 2>&1 | Out-String

if ($fnCheck -notmatch '"FunctionName"') {
    Write-Host "[ERR] Lambda function not found. Deploy it first." -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Lambda function found." -ForegroundColor Green

# Step 3: Check mapping
Write-Host "[3/4] Checking existing event source mappings..." -ForegroundColor Cyan

$existingMapping = & podman $podmanBase lambda list-event-source-mappings `
    --function-name $functionName `
    --event-source-arn $queueArn 2>&1 | Out-String

if ($existingMapping -match '"UUID"') {
    $uuid = ($existingMapping | Select-String '"UUID": "([^"]+)"').Matches[0].Groups[1].Value
    Write-Host "[OK] Mapping already exists: $uuid" -ForegroundColor Green
    exit 0
}

# Step 4: Create mapping
Write-Host "[4/4] Creating event source mapping..." -ForegroundColor Cyan

$result = & podman $podmanBase lambda create-event-source-mapping `
    --function-name $functionName `
    --event-source-arn $queueArn `
    --enabled 2>&1 | Out-String

if ($result -match '"UUID"') {
    $uuid = ($result | Select-String '"UUID": "([^"]+)"').Matches[0].Groups[1].Value
    Write-Host "[OK] Event source mapping created: $uuid" -ForegroundColor Green
} else {
    Write-Host "[ERR] Failed to create mapping" -ForegroundColor Red
    Write-Host $result
    exit 1
}