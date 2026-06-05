output "api_endpoint" {
  description = "API Gateway endpoint for testing (POST /orders)"
  value       = "http://localhost:4566/restapis/${aws_api_gateway_rest_api.ecommerce.id}/${local.api_stage_name}/_user_request_/orders"
}

output "sqs_queue_url" {
  description = "SQS queue URL"
  value       = aws_sqs_queue.orders.url
}

output "sqs_queue_arn" {
  description = "SQS queue ARN"
  value       = aws_sqs_queue.orders.arn
}

output "processor_lambda_arn" {
  description = "Processor Lambda function ARN"
  value       = aws_lambda_function.processor.arn
}

output "proxy_lambda_arn" {
  description = "API Gateway proxy Lambda ARN"
  value       = aws_lambda_function.proxy.arn
}

output "processor_lambda_name" {
  description = "Processor Lambda function name"
  value       = aws_lambda_function.processor.function_name
}

output "proxy_lambda_name" {
  description = "Proxy Lambda function name"
  value       = aws_lambda_function.proxy.function_name
}
