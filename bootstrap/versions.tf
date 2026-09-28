terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }

  # Intentionally local state: this config creates the remote state
  # backend itself, so it can't depend on that backend existing yet.
  # Run this once per AWS account, keep the resulting
  # terraform.tfstate somewhere safe, and treat it as rarely-touched.
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.name
      ManagedBy = "Terraform"
      Component = "bootstrap"
    }
  }
}
