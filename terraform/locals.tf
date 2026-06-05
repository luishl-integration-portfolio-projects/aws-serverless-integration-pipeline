locals {
  account_id   = "000000000000"
  region       = var.region

  # Resource names
  queue_name             = "cola-pedidos-ecommerce"
  processor_function_name = "procesador-pedidos-lambda"
  proxy_function_name    = "api-gateway-proxy"
  api_name               = "ecommerce-orders-api"
  api_stage_name         = "dev"

  # Lambda settings
  runtime          = "python3.12"
  processor_handler = "index.lambda_handler"
  proxy_handler    = "api_handler.lambda_handler"
  lambda_role_name = "lambda-exec-role"

  # Derived ARNs
  queue_arn = "arn:aws:sqs:${var.region}:${local.account_id}:${local.queue_name}"

  common_tags = {
    Project   = "aws-serverless-integration-pipeline"
    ManagedBy = "terraform"
    Stack     = "eda-ecommerce"
  }
}
