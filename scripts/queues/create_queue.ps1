<#
.SYNOPSIS
    Creates the SQS queue for e-commerce orders in LocalStack (Podman-safe version)
.DESCRIPTION
    Idempotent queue creation for LocalStack.
    Works reliably with Podman + AWS CLI container.
#>

Write-Host "[1/2] Creating SQS queue 'cola-pedidos-ecommerce'..." -ForegroundColor Cyan

$result = podman run --rm --network=host `
  -e AWS_ACCESS_KEY_ID=mock `
  -e AWS_SECRET_ACCESS_KEY=mock `
  -e AWS_DEFAULT_REGION=us-east-1 `
  amazon/aws-cli `
  --no-cli-pager `
  --endpoint-url=http://127.0.0.1:4566 `
  sqs create-queue `
  --queue-name cola-pedidos-ecommerce 2>&1

# -----------------------------
# SAFE OUTPUT HANDLING
# -----------------------------
$json = $null

try {
    # AWS CLI output sometimes comes as string array → normalize
    $clean = ($result | Out-String).Trim()
    $json = $clean | ConvertFrom-Json
} catch {
    $json = $null
}

# -----------------------------
# RESULT EVALUATION
# -----------------------------
if ($json -and $json.QueueUrl) {
    Write-Host "  [OK] Queue created: $($json.QueueUrl)" -ForegroundColor Green
}
else {
    Write-Host "  [WARN] Queue created but output could not be parsed cleanly." -ForegroundColor Yellow
    Write-Host "  Raw output:"
    Write-Host $result
}

Write-Host "[2/2] Done." -ForegroundColor Green