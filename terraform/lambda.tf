# -----------------------------------------------------------
# Lambda — Processor (consumes SQS messages)
# -----------------------------------------------------------
data "archive_file" "processor" {
  type        = "zip"
  source_file = "${path.module}/../src/index.py"
  output_path = "${path.module}/../src/funcion_lambda.zip"
}

resource "aws_lambda_function" "processor" {
  filename         = data.archive_file.processor.output_path
  function_name    = local.processor_function_name
  role             = aws_iam_role.lambda_exec.arn
  handler          = local.processor_handler
  runtime          = local.runtime
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size
  source_code_hash = data.archive_file.processor.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.orders.name
    }
  }

  tags = local.common_tags
}

# -----------------------------------------------------------
# Lambda — CRUD (DynamoDB read/write/delete operations)
# -----------------------------------------------------------
data "archive_file" "crud" {
  type        = "zip"
  source_file = "${path.module}/../src/orders_crud.py"
  output_path = "${path.module}/../src/orders_crud.zip"
}

resource "aws_lambda_function" "crud" {
  filename         = data.archive_file.crud.output_path
  function_name    = local.crud_function_name
  role             = aws_iam_role.lambda_exec.arn
  handler          = local.crud_handler
  runtime          = local.runtime
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size
  source_code_hash = data.archive_file.crud.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.orders.name
    }
  }

  tags = local.common_tags
}

# -----------------------------------------------------------
# Lambda — API Gateway proxy (HTTP → SQS adapter)
# -----------------------------------------------------------
data "archive_file" "proxy" {
  type        = "zip"
  source_file = "${path.module}/../src/api_handler.py"
  output_path = "${path.module}/../src/proxy_lambda.zip"
}

resource "aws_lambda_function" "proxy" {
  filename         = data.archive_file.proxy.output_path
  function_name    = local.proxy_function_name
  role             = aws_iam_role.lambda_exec.arn
  handler          = local.proxy_handler
  runtime          = local.runtime
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size
  source_code_hash = data.archive_file.proxy.output_base64sha256

  tags = local.common_tags
}
