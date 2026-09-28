# One-time bootstrap: creates the S3 bucket + DynamoDB table that the main
# cs-dashboard Terraform config uses as its remote state backend.
#
# Usage:
#   cd bootstrap
#   terraform init
#   terraform apply
#   terraform output   # use these values in ../backend.hcl

resource "random_id" "state_bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "terraform_state" {
  # checkov:skip=CKV_AWS_144: cross-region replication doubles storage cost for state history that is not needed at this scale.
  # checkov:skip=CKV_AWS_145: SSE-S3 (AES256, set below) already encrypts at rest for free; a customer-managed KMS key adds ~$1/mo for no practical gain on a solo-maintained state bucket.
  # checkov:skip=CKV_AWS_18: access logging needs a second bucket to receive logs - not worth the extra resource for a personal Terraform state bucket.
  # checkov:skip=CKV2_AWS_62: event notifications (needs SNS/SQS/Lambda) are unnecessary complexity for a personal Terraform state bucket.
  bucket = "${var.name}-tfstate-${random_id.state_bucket_suffix.hex}"

  # Guard against `terraform destroy` accidentally deleting state history.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = "${var.name}-tfstate"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "expire-noncurrent-state-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_dynamodb_table" "terraform_locks" {
  # checkov:skip=CKV_AWS_119: default AWS-owned key encrypts at rest for free; a customer-managed KMS key adds ~$1/mo for no practical gain on a tiny lock table.
  name         = "${var.name}-tfstate-locks"
  billing_mode = "PAY_PER_REQUEST" # no capacity to size; within DynamoDB always-free tier for this workload
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true # negligible cost at this table's size (a few KB)
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = "${var.name}-tfstate-locks"
  }
}
