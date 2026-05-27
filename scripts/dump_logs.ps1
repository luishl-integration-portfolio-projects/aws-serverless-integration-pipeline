<#
.SYNOPSIS
    Dumps all LocalStack-generated logs to a timestamped file in logs/.
.DESCRIPTION
    Captures the main LocalStack container logs, Lambda executor container logs,
    container list, and SQS/Lambda status. Useful for debugging.
#>

param([string]$OutDir = (Join-Path $PSScriptRoot "..\logs"))

$region   = "us-east-1"
$functionName = "procesador-pedidos-lambda"
$timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$logFile   = Join-Path $OutDir "localstack_dump_$timestamp.log"

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$podmanBase = @(
    "run", "--rm", "--network=host"
    "-e", "AWS_ACCESS_KEY_ID=mock"
    "-e", "AWS_SECRET_ACCESS_KEY=mock"
    "-e", "AWS_DEFAULT_REGION=$region"
    "amazon/aws-cli"
    "--endpoint-url=http://127.0.0.1:4566"
)

function Out-Log {
    param([string]$Section, [string]$Content)
    "`n" + ("=" * 60) + "`n" + "=== $Section" + "`n" + ("=" * 60) + "`n" + $Content + "`n"
}

$lines = @()
$lines += "LocalStack Log Dump"
$lines += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$lines += ""

# 1. Container list
$containers = podman ps -a --format "table {{.Names}} {{.Status}} {{.Image}}" 2>&1 | Out-String
$lines += Out-Log -Section "All Podman Containers" -Content $containers

# 2. Main LocalStack container logs
$mainLogs = podman logs localstack-pipeline --tail 100 2>&1 | Out-String
$lines += Out-Log -Section "Main LocalStack Container Logs (last 100 lines)" -Content $mainLogs

# 3. Lambda executor container logs
$executorContainers = podman ps -a --filter "name=procesador-pedidos-lambda" --format "{{.Names}}" 2>&1
foreach ($cname in $executorContainers) {
    $cname = $cname.Trim()
    if (-not $cname) { continue }
    $execLogs = podman logs $cname --tail 50 2>&1 | Out-String
    $lines += Out-Log -Section "Lambda Executor: $cname" -Content $execLogs
}

# 4. Lambda function state
$lambdaState = & podman $podmanBase lambda get-function --function-name $functionName 2>&1 | Out-String
$lines += Out-Log -Section "Lambda Function State" -Content $lambdaState

# 5. Event source mappings
$mappings = & podman $podmanBase lambda list-event-source-mappings --function-name $functionName 2>&1 | Out-String
$lines += Out-Log -Section "Event Source Mappings" -Content $mappings

# 6. SQS queue status
$queueUrl = "http://127.0.0.1:4566/000000000000/cola-pedidos-ecommerce"
$queueStatus = & podman $podmanBase sqs receive-message --queue-url $queueUrl --max-number-of-messages 5 --wait-time-seconds 2 2>&1 | Out-String
$lines += Out-Log -Section "SQS Queue Status" -Content $queueStatus

$lines -join "`n" | Out-File -FilePath $logFile -Encoding UTF8

Write-Host "[OK] Log dump saved to: $logFile" -ForegroundColor Green
Write-Host "      Total size: $((Get-Item $logFile).Length) bytes" -ForegroundColor DarkGray
