variable "region" {
  description = "Region for the Terraform state bucket and lock table."
  type        = string
  default     = "ap-southeast-2"
}

variable "name" {
  description = "Name prefix, should match the main project's var.name."
  type        = string
  default     = "cs-dashboard"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.name))
    error_message = "name must be lowercase alphanumeric/hyphens, start with a letter, 2-31 chars (S3 bucket name safe)."
  }
}
