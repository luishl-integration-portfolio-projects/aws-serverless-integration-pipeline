# DynamoDB table for persisting processed orders
resource "aws_dynamodb_table" "orders" {
  name         = local.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id_pedido"

  attribute {
    name = "id_pedido"
    type = "N"
  }

  tags = local.common_tags
}
