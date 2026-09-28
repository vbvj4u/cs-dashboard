output "state_bucket" {
  description = "S3 bucket name - use as `bucket` in ../backend.hcl"
  value       = aws_s3_bucket.terraform_state.bucket
}

output "lock_table" {
  description = "DynamoDB table name - use as `dynamodb_table` in ../backend.hcl"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "region" {
  description = "Region - use as `region` in ../backend.hcl"
  value       = var.region
}
