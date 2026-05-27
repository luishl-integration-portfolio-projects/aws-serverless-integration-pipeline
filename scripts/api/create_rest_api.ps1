$region    = "us-east-1"
$queueName = "cola-pedidos-ecommerce"
$accountId = "000000000000"
$apiName   = "ecommerce-orders-api"
$stageName = "dev"
$proxyFn   = "api-gateway-proxy"
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$handlerSrc  = Join-Path $projectRoot "src\api_handler.py"

$podmanBase = @(
    "run", "--rm", "--network=host"
    "-e", "AWS_ACCESS_KEY_ID=mock"
    "-e", "AWS_SECRET_ACCESS_KEY=mock"
    "-e", "AWS_DEFAULT_REGION=$region"
)
$podmanImage = @("amazon/aws-cli", "--endpoint-url=http://127.0.0.1:4566")

function Invoke-AwsCli { & podman ($podmanBase + $podmanImage) $args 2>&1 }
function Invoke-AwsCliWithMount {
    param([string]$Mount)
    & podman ($podmanBase + @("-v", $Mount) + $podmanImage) $args 2>&1
}

# -----------------------------------------------------------
# Step 1: Package and deploy the proxy Lambda
# -----------------------------------------------------------
Write-Host "[1/7] Packaging proxy Lambda..." -ForegroundColor Cyan
$tmpZip = Join-Path $env:TEMP "api_proxy.zip"
if (Test-Path $tmpZip) { Remove-Item $tmpZip -Force }
Compress-Archive -Path $handlerSrc -DestinationPath $tmpZip -Force
Write-Host "  [OK] Package created." -ForegroundColor Green

Write-Host "[2/7] Deploying proxy Lambda '$proxyFn'..." -ForegroundColor Cyan
$tmpDir = $env:TEMP
$tmpMount = "${tmpDir}:/lambda-pkg"
$fnResult = Invoke-AwsCliWithMount -Mount $tmpMount lambda create-function `
    --function-name $proxyFn `
    --runtime python3.12 `
    --role "arn:aws:iam::${accountId}:role/lambda-ex" `
    --handler api_handler.lambda_handler `
    --zip-file fileb:///lambda-pkg/api_proxy.zip 2>&1 | Out-String

if ($fnResult -match '"FunctionArn"') {
    Write-Host "  [OK] Proxy Lambda created." -ForegroundColor Green
} elseif ($fnResult -match "ResourceConflictException") {
    Write-Host "  -> Proxy Lambda already exists. Updating code..." -ForegroundColor Yellow
    Invoke-AwsCliWithMount -Mount $tmpMount lambda update-function-code `
        --function-name $proxyFn --zip-file fileb:///lambda-pkg/api_proxy.zip | Out-Null
}

# Wait for proxy Lambda to become Active
Write-Host "  -> Waiting for proxy Lambda to become Active..." -ForegroundColor Cyan
Invoke-AwsCli lambda wait function-active-v2 --function-name $proxyFn | Out-Null
$proxyArn = "arn:aws:lambda:${region}:${accountId}:function:${proxyFn}"
Write-Host "  [OK] Proxy Lambda active: $proxyArn" -ForegroundColor Green

Remove-Item $tmpZip -Force

# -----------------------------------------------------------
# Step 3: Grant API Gateway permission to invoke the proxy Lambda
# -----------------------------------------------------------
Write-Host "[3/7] Granting API Gateway invoke permission..." -ForegroundColor Cyan
$sourceArn = "arn:aws:execute-api:${region}:${accountId}:*"
Invoke-AwsCli lambda add-permission `
    --function-name $proxyFn `
    --statement-id api-gateway-invoke `
    --action lambda:InvokeFunction `
    --principal apigateway.amazonaws.com `
    --source-arn $sourceArn 2>&1 | Out-Null
Write-Host "  [OK] Permission granted." -ForegroundColor Green

# -----------------------------------------------------------
# Step 4: Create REST API
# -----------------------------------------------------------
Write-Host "[4/7] Creating REST API '$apiName'..." -ForegroundColor Cyan
$apiResult = Invoke-AwsCli apigateway create-rest-api --name $apiName | Out-String
if ($apiResult -notmatch '"id"') {
    Write-Host "[ERR] Failed to create API." -ForegroundColor Red
    Write-Host $apiResult
    exit 1
}
$apiId = ($apiResult | Select-String '"id": "([^"]+)"').Matches[0].Groups[1].Value
Write-Host "  [OK] API ID: $apiId" -ForegroundColor Green

# -----------------------------------------------------------
# Step 5: Get root resource and create /orders
# -----------------------------------------------------------
Write-Host "[5/7] Creating resource '/orders'..." -ForegroundColor Cyan
$resourcesResult = Invoke-AwsCli apigateway get-resources --rest-api-id $apiId | Out-String
$rootId = ($resourcesResult | Select-String '"id": "([^"]+)"').Matches[0].Groups[1].Value

$resourceResult = Invoke-AwsCli apigateway create-resource --rest-api-id $apiId --parent-id $rootId --path-part orders | Out-String
$resourceId = ($resourceResult | Select-String '"id": "([^"]+)"').Matches[0].Groups[1].Value
Write-Host "  [OK] Resource ID: $resourceId" -ForegroundColor Green

# -----------------------------------------------------------
# Step 6: POST method + Lambda proxy integration
# -----------------------------------------------------------
Write-Host "[6/7] Configuring POST method with Lambda proxy..." -ForegroundColor Cyan

# Create POST method
Invoke-AwsCli apigateway put-method `
    --rest-api-id $apiId --resource-id $resourceId `
    --http-method POST --authorization-type NONE | Out-Null

# Lambda proxy integration
$lambdaUri = "arn:aws:apigateway:${region}:lambda:path/2015-03-31/functions/${proxyArn}/invocations"
Invoke-AwsCli apigateway put-integration `
    --rest-api-id $apiId --resource-id $resourceId `
    --http-method POST --type AWS_PROXY `
    --integration-http-method POST `
    --uri $lambdaUri | Out-Null

Write-Host "  [OK] Lambda proxy integration configured." -ForegroundColor Green

# -----------------------------------------------------------
# Step 7: Deploy
# -----------------------------------------------------------
Write-Host "[7/7] Deploying API to stage '$stageName'..." -ForegroundColor Cyan
Invoke-AwsCli apigateway create-deployment --rest-api-id $apiId --stage-name $stageName | Out-Null
Write-Host "  [OK] API deployed." -ForegroundColor Green

Write-Host ""
Write-Host "============================================" -ForegroundColor Magenta
Write-Host "[OK] API Gateway ready!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Magenta
Write-Host ""
Write-Host "  Endpoint URL: http://127.0.0.1:4566/restapis/$apiId/$stageName/_user_request_/orders" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Test with Postman:" -ForegroundColor White
Write-Host "    POST http://127.0.0.1:4566/restapis/$apiId/$stageName/_user_request_/orders" -ForegroundColor White
Write-Host "    Content-Type: application/json" -ForegroundColor White
Write-Host "    Body: {\"id_pedido\": 2001, \"cliente\": \"postman-test\", \"total\": 45.50}" -ForegroundColor White
