resource "aws_sqs_queue" "orders" {
  name                       = local.queue_name
  visibility_timeout_seconds = 30
  max_message_size           = 262144  # 256 KB
  message_retention_seconds  = 345600  # 4 days

  tags = local.common_tags
}
