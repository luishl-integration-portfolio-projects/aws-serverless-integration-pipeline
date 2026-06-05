output "api_endpoint" {
  description = "API Gateway base endpoint for all operations"
  value       = "http://localhost:4566/restapis/${aws_api_gateway_rest_api.ecommerce.id}/${local.api_stage_name}/_user_request_"
}

output "sqs_queue_url" {
  description = "SQS queue URL"
  value       = aws_sqs_queue.orders.url
}

output "dynamodb_table_name" {
  description = "DynamoDB table storing processed orders"
  value       = aws_dynamodb_table.orders.name
}

output "processor_lambda_arn" {
  description = "Processor Lambda function ARN"
  value       = aws_lambda_function.processor.arn
}

output "proxy_lambda_arn" {
  description = "API Gateway proxy Lambda ARN"
  value       = aws_lambda_function.proxy.arn
}

output "crud_lambda_arn" {
  description = "CRUD Lambda function ARN"
  value       = aws_lambda_function.crud.arn
}
