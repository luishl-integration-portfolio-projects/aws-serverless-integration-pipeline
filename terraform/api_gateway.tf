# -----------------------------------------------------------
# REST API Gateway — exposes /orders POST + GET/PUT/DELETE CRUD
# -----------------------------------------------------------
resource "aws_api_gateway_rest_api" "ecommerce" {
  name        = local.api_name
  description = "E-commerce order ingestion API (EDA pipeline + CRUD)"

  tags = local.common_tags
}

# Resource: /orders
resource "aws_api_gateway_resource" "orders" {
  rest_api_id = aws_api_gateway_rest_api.ecommerce.id
  parent_id   = aws_api_gateway_rest_api.ecommerce.root_resource_id
  path_part   = "orders"
}

# ── POST /orders (async ingestion via SQS — proxy Lambda) ─────────
resource "aws_api_gateway_method" "post_orders" {
  rest_api_id   = aws_api_gateway_rest_api.ecommerce.id
  resource_id   = aws_api_gateway_resource.orders.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_proxy" {
  rest_api_id             = aws_api_gateway_rest_api.ecommerce.id
  resource_id             = aws_api_gateway_resource.orders.id
  http_method             = aws_api_gateway_method.post_orders.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.proxy.invoke_arn
}

# ── GET /orders (list all — CRUD Lambda) ─────────────────────────
resource "aws_api_gateway_method" "list_orders" {
  rest_api_id   = aws_api_gateway_rest_api.ecommerce.id
  resource_id   = aws_api_gateway_resource.orders.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "list_orders" {
  rest_api_id             = aws_api_gateway_rest_api.ecommerce.id
  resource_id             = aws_api_gateway_resource.orders.id
  http_method             = aws_api_gateway_method.list_orders.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.crud.invoke_arn
}

# ── Resource: /orders/{id} ───────────────────────────────────────
resource "aws_api_gateway_resource" "orders_id" {
  rest_api_id = aws_api_gateway_rest_api.ecommerce.id
  parent_id   = aws_api_gateway_resource.orders.id
  path_part   = "{id}"
}

# ── GET /orders/{id} (get one — CRUD Lambda) ─────────────────────
resource "aws_api_gateway_method" "get_order" {
  rest_api_id   = aws_api_gateway_rest_api.ecommerce.id
  resource_id   = aws_api_gateway_resource.orders_id.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_order" {
  rest_api_id             = aws_api_gateway_rest_api.ecommerce.id
  resource_id             = aws_api_gateway_resource.orders_id.id
  http_method             = aws_api_gateway_method.get_order.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.crud.invoke_arn
}

# ── PUT /orders/{id} (update — CRUD Lambda) ──────────────────────
resource "aws_api_gateway_method" "update_order" {
  rest_api_id   = aws_api_gateway_rest_api.ecommerce.id
  resource_id   = aws_api_gateway_resource.orders_id.id
  http_method   = "PUT"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "update_order" {
  rest_api_id             = aws_api_gateway_rest_api.ecommerce.id
  resource_id             = aws_api_gateway_resource.orders_id.id
  http_method             = aws_api_gateway_method.update_order.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.crud.invoke_arn
}

# ── DELETE /orders/{id} (delete — CRUD Lambda) ───────────────────
resource "aws_api_gateway_method" "delete_order" {
  rest_api_id   = aws_api_gateway_rest_api.ecommerce.id
  resource_id   = aws_api_gateway_resource.orders_id.id
  http_method   = "DELETE"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "delete_order" {
  rest_api_id             = aws_api_gateway_rest_api.ecommerce.id
  resource_id             = aws_api_gateway_resource.orders_id.id
  http_method             = aws_api_gateway_method.delete_order.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.crud.invoke_arn
}

# ── Deploy to stage "dev" ────────────────────────────────────────
resource "aws_api_gateway_deployment" "dev" {
  rest_api_id = aws_api_gateway_rest_api.ecommerce.id

  depends_on = [
    aws_api_gateway_integration.lambda_proxy,
    aws_api_gateway_integration.list_orders,
    aws_api_gateway_integration.get_order,
    aws_api_gateway_integration.update_order,
    aws_api_gateway_integration.delete_order,
  ]

  # Force re-deployment when any integration changes
  triggers = {
    hash = sha1(jsonencode({
      proxy  = aws_api_gateway_integration.lambda_proxy
      list   = aws_api_gateway_integration.list_orders
      get    = aws_api_gateway_integration.get_order
      update = aws_api_gateway_integration.update_order
      delete = aws_api_gateway_integration.delete_order
    }))
  }
}

resource "aws_api_gateway_stage" "dev" {
  rest_api_id   = aws_api_gateway_rest_api.ecommerce.id
  deployment_id = aws_api_gateway_deployment.dev.id
  stage_name    = local.api_stage_name
}
