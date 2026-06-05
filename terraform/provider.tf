provider "aws" {
  region                      = var.region
  access_key                  = "AKID"
  secret_key                  = "SECRET"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  s3_use_path_style           = true

  endpoints {
    apigateway = var.localstack_endpoint
    cloudwatch = var.localstack_endpoint
    dynamodb   = var.localstack_endpoint
    iam        = var.localstack_endpoint
    lambda     = var.localstack_endpoint
    logs       = var.localstack_endpoint
    sqs        = var.localstack_endpoint
  }
}
