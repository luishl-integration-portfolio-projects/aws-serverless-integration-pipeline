<#
.SYNOPSIS
    Sends a test order to the SQS queue via the Podman AWS CLI container.
.DESCRIPTION
    Publishes a JSON order message directly to the SQS queue for testing
    the processor Lambda. Uses a temp file to avoid PowerShell quoting issues.
.PARAMETER Body
    JSON string for the order payload. Defaults to a sample order.
.EXAMPLE
    .\test_message.ps1
    .\test_message.ps1 -Body '{"id_pedido":2001,"cliente":"terraform-test","total":99.99}'
#>
param(
    [string]$Body = '{"id_pedido": 1001, "cliente": "lherna06", "total": 89.95, "productos": ["Widget A", "Gadget B"], "moneda": "EUR"}'
)

$queueUrl = "http://127.0.0.1:4566/000000000000/cola-pedidos-ecommerce"
$region   = "us-east-1"

Write-Host "[1/2] Publishing test message to SQS..." -ForegroundColor Cyan
Write-Host "  -> Queue URL: $queueUrl" -ForegroundColor DarkGray
Write-Host "  -> Body: $Body" -ForegroundColor DarkGray

# Write body to a temp file to avoid JSON quoting issues
$tempDir = Join-Path $env:TEMP "sqs_payload_tf"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$tempFile = Join-Path $tempDir "message_$(Get-Random).json"
$Body | Set-Content -Path $tempFile -Encoding UTF8 -NoNewline

$result = podman run --rm --network=host `
    -e AWS_ACCESS_KEY_ID=mock `
    -e AWS_SECRET_ACCESS_KEY=mock `
    -e AWS_DEFAULT_REGION=$region `
    -v "${tempDir}:/payload" `
    amazon/aws-cli `
    --endpoint-url=http://127.0.0.1:4566 `
    sqs send-message `
    --queue-url $queueUrl `
    --message-body file:///payload/$(Split-Path -Leaf $tempFile) 2>&1

Remove-Item $tempFile -Force

if ($LASTEXITCODE -eq 0 -and $result -match '"MD5OfMessageBody"') {
    $messageId = ($result | Select-String '"MessageId": "([^"]+)"').Matches[0].Groups[1].Value
    Write-Host "[OK] Message sent! MessageId: $messageId" -ForegroundColor Green
} else {
    Write-Host "[WARN] Could not verify message delivery." -ForegroundColor Yellow
    Write-Host $result
}

Write-Host "[2/2] Done." -ForegroundColor Green
Write-Host "  Check processor Lambda logs with: .\verify.ps1" -ForegroundColor Cyan
