# Partial backend config: bucket/table names are account-specific, so they
# are NOT hardcoded here (this repo is public). Supply them via:
#   terraform init -backend-config=backend.hcl
# See backend.hcl.example, and bootstrap/ which creates these resources.
terraform {
  backend "s3" {
    encrypt = true
  }
}
