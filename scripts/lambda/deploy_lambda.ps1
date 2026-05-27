
$projectRoot  = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$archivePath  = Join-Path $projectRoot "src\funcion_lambda.zip"
$functionName = "procesador-pedidos-lambda"
$region       = "us-east-1"

if (-not (Test-Path $archivePath)) {
    Write-Host "[ERR] Lambda package not found at $archivePath" -ForegroundColor Red
    Write-Host "   Run .\scripts\lambda\package_lambda.ps1 first." -ForegroundColor Yellow
    exit 1
}

# 🔥 FIX: comma missing here
$podmanBase = @(
    "run", "--rm", "--network=host",
    "-e", "AWS_ACCESS_KEY_ID=mock",
    "-e", "AWS_SECRET_ACCESS_KEY=mock",
    "-e", "AWS_DEFAULT_REGION=$region",
    "-v", "$($projectRoot)\src:/workspace",
    "amazon/aws-cli",
    "--endpoint-url=http://127.0.0.1:4566"
)

# Check LocalStack is reachable (works with WSL2 on Windows)
$lsUri = $null
$candidates = @("http://127.0.0.1:4566", "http://localhost:4566", "http://[::1]:4566")

try {
    $wslIp = wsl -- ip -4 addr show eth0 2>$null
    if ($wslIp) {
        $m = [regex]::Match($wslIp, 'inet (\d+\.\d+\.\d+\.\d+)')
        if ($m.Success) {
            $candidates += "http://$($m.Groups[1].Value):4566"
        }
    }
} catch {}

foreach ($uri in $candidates) {
    try {
        $null = Invoke-RestMethod -Uri "$uri/_localstack/health" -ErrorAction Stop -TimeoutSec 2
        $lsUri = $uri
        break
    } catch { continue }
}

if (-not $lsUri) {
    Write-Host "[ERR] LocalStack is not reachable. Start it first with start_localstack.ps1" -ForegroundColor Red
    exit 1
}

# Check if function exists
Write-Host "[1/3] Checking if Lambda function '$functionName' already exists..." -ForegroundColor Cyan

$getResult = & podman $podmanBase lambda get-function --function-name $functionName 2>&1 | Out-String
$exists = $getResult -match '"FunctionName"'

if ($exists) {
    Write-Host "  -> Function exists. Updating code in-place..." -ForegroundColor Yellow

    $output = & podman $podmanBase lambda update-function-code `
        --function-name $functionName `
        --zip-file fileb:///workspace/funcion_lambda.zip 2>&1 | Out-String

    $exitCode = $LASTEXITCODE
} else {
    Write-Host "  -> Function does not exist. Creating new function..." -ForegroundColor Cyan

    $output = & podman $podmanBase lambda create-function `
        --function-name $functionName `
        --runtime python3.12 `
        --role arn:aws:iam::000000000000:role/lambda-ex `
        --handler index.lambda_handler `
        --zip-file fileb:///workspace/funcion_lambda.zip 2>&1 | Out-String

    $exitCode = $LASTEXITCODE
}

Write-Host "[2/3] Deploying Lambda code..." -ForegroundColor Cyan

if ($exitCode -eq 0 -and ($output -match '"FunctionArn"' -or $output -match '"LastModified"')) {

    $arn = "N/A"
    $m = [regex]::Match($output, '"FunctionArn": "([^"]+)"')
    if ($m.Success) { $arn = $m.Groups[1].Value }

    Write-Host "[OK] Lambda function '$functionName' registered." -ForegroundColor Green
    Write-Host "     ARN: $arn" -ForegroundColor DarkGray

    Write-Host "[3/3] Waiting for function to become Active..." -ForegroundColor Cyan

    & podman $podmanBase lambda wait function-active-v2 --function-name $functionName 2>&1 | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Function is now Active -- ready to receive events." -ForegroundColor Green
    } else {
        Write-Host "[WARN] Function may still be in Pending state. Proceeding anyway..." -ForegroundColor Yellow
    }

} else {
    Write-Host "[ERR] Failed to deploy Lambda function. Exit code: $exitCode" -ForegroundColor Red
    Write-Host $output
    exit 1
}