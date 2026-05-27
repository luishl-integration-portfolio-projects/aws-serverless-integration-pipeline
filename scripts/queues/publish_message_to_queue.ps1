param(
    [string]$Body = '{"id_pedido": 1001, "cliente": "lherna06", "total": 89.95, "productos": ["Widget A", "Gadget B"], "moneda": "EUR"}'
)

$queueUrl = "http://127.0.0.1:4566/000000000000/cola-pedidos-ecommerce"

Write-Host "[1/2] Publishing test message to queue..." -ForegroundColor Cyan
Write-Host "  -> Queue URL: $queueUrl" -ForegroundColor DarkGray
Write-Host "  -> Body: $Body" -ForegroundColor DarkGray

# Write body to a temp file to avoid argument quoting issues with JSON
$tempDir = Join-Path $env:TEMP "sqs_payload"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$tempFile = Join-Path $tempDir "message_$(Get-Random).json"
$Body | Set-Content -Path $tempFile -Encoding UTF8 -NoNewline

$result = podman run --rm --network=host -e AWS_ACCESS_KEY_ID=mock -e AWS_SECRET_ACCESS_KEY=mock -e AWS_DEFAULT_REGION=us-east-1 -v "${tempDir}:/payload" amazon/aws-cli --endpoint-url=http://127.0.0.1:4566 sqs send-message --queue-url $queueUrl --message-body file:///payload/$(Split-Path -Leaf $tempFile) 2>&1

Remove-Item $tempFile -Force

if ($LASTEXITCODE -eq 0 -and $result -match '"MD5OfMessageBody"') {
    $messageId = ($result | Select-String '"MessageId": "([^"]+)"').Matches[0].Groups[1].Value
    Write-Host "[OK] Message sent! MessageId: $messageId" -ForegroundColor Green
} else {
    Write-Host "[WARN] Could not verify message delivery." -ForegroundColor Yellow
    Write-Host $result
}
