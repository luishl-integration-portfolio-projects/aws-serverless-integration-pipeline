# Event source mapping: SQS → Lambda processor
# When messages arrive in the queue, this mapping automatically invokes
# the processor Lambda (polling-based trigger).
resource "aws_lambda_event_source_mapping" "sqs_to_processor" {
  event_source_arn = aws_sqs_queue.orders.arn
  function_name    = aws_lambda_function.processor.arn
  enabled          = true
  batch_size       = 10
}

# Permission for API Gateway to invoke the proxy Lambda (POST /orders)
resource "aws_lambda_permission" "api_gateway_invoke_proxy" {
  statement_id  = "AllowAPIGatewayInvokeProxy"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.proxy.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "arn:aws:execute-api:${var.region}:${local.account_id}:${aws_api_gateway_rest_api.ecommerce.id}/*/${aws_api_gateway_method.post_orders.http_method}${aws_api_gateway_resource.orders.path}"
}

# Permission for API Gateway to invoke the CRUD Lambda (GET/PUT/DELETE)
resource "aws_lambda_permission" "api_gateway_invoke_crud" {
  statement_id  = "AllowAPIGatewayInvokeCRUD"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.crud.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "arn:aws:execute-api:${var.region}:${local.account_id}:${aws_api_gateway_rest_api.ecommerce.id}/*/*/*"
}
