# -----------------------------------------------------------
# REST API Gateway — exposes /orders POST endpoint
# -----------------------------------------------------------
resource "aws_api_gateway_rest_api" "ecommerce" {
  name        = local.api_name
  description = "E-commerce order ingestion API (EDA pipeline)"

  tags = local.common_tags
}

# Resource: /orders
resource "aws_api_gateway_resource" "orders" {
  rest_api_id = aws_api_gateway_rest_api.ecommerce.id
  parent_id   = aws_api_gateway_rest_api.ecommerce.root_resource_id
  path_part   = "orders"
}

# POST method on /orders
resource "aws_api_gateway_method" "post_orders" {
  rest_api_id   = aws_api_gateway_rest_api.ecommerce.id
  resource_id   = aws_api_gateway_resource.orders.id
  http_method   = "POST"
  authorization = "NONE"
}

# Lambda proxy integration (AWS_PROXY)
resource "aws_api_gateway_integration" "lambda_proxy" {
  rest_api_id             = aws_api_gateway_rest_api.ecommerce.id
  resource_id             = aws_api_gateway_resource.orders.id
  http_method             = aws_api_gateway_method.post_orders.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.proxy.invoke_arn
}

# Deploy to stage "dev"
resource "aws_api_gateway_deployment" "dev" {
  rest_api_id = aws_api_gateway_rest_api.ecommerce.id
  stage_name  = local.api_stage_name

  depends_on = [
    aws_api_gateway_integration.lambda_proxy,
  ]

  # Force re-deployment when the integration or method changes
  triggers = {
    integration_hash = sha1(jsonencode(aws_api_gateway_integration.lambda_proxy))
  }
}
