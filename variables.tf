variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-southeast-2"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "region must look like a valid AWS region, e.g. us-east-1."
  }
}

variable "environment" {
  description = "Deployment environment name, used in tags."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "name" {
  description = "Name/tag prefix for all resources."
  type        = string
  default     = "cs-dashboard"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.name))
    error_message = "name must be lowercase alphanumeric/hyphens, start with a letter, 2-31 chars."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets (one per AZ)."
  type        = list(string)
  default     = ["10.0.0.0/20", "10.0.16.0/20"]

  validation {
    condition     = alltrue([for c in var.public_subnet_cidrs : can(cidrhost(c, 0))])
    error_message = "public_subnet_cidrs must all be valid CIDR blocks."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets (one per AZ)."
  type        = list(string)
  default     = ["10.0.128.0/20", "10.0.144.0/20"]

  validation {
    condition     = alltrue([for c in var.private_subnet_cidrs : can(cidrhost(c, 0))])
    error_message = "private_subnet_cidrs must all be valid CIDR blocks."
  }
}

variable "my_ip_cidr" {
  description = "Your public IP in CIDR form (e.g. 203.0.113.10/32) - the only source allowed to reach phpMyAdmin/Metabase. Leave unset to auto-detect via checkip.amazonaws.com at plan/apply time; set explicitly to override."
  type        = string
  default     = null

  validation {
    condition     = var.my_ip_cidr == null || (can(cidrhost(var.my_ip_cidr, 0)) && endswith(var.my_ip_cidr, "/32"))
    error_message = "my_ip_cidr must be a single host CIDR, e.g. 203.0.113.10/32."
  }
}

variable "ecs_instance_type" {
  description = "Instance type for the ECS container instance."
  type        = string
  default     = "t3.small" # t3.micro (1GiB) can't fit phpMyAdmin + Metabase without Metabase GC-thrashing on startup

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*\\.[a-z0-9]+$", var.ecs_instance_type))
    error_message = "ecs_instance_type must look like a valid EC2 instance type, e.g. t3.micro."
  }
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"

  validation {
    condition     = can(regex("^db\\.[a-z][a-z0-9]*\\.[a-z0-9]+$", var.db_instance_class))
    error_message = "db_instance_class must look like a valid RDS instance class, e.g. db.t3.micro."
  }
}

variable "db_username" {
  description = "Master username for the RDS MySQL instance."
  type        = string
  default     = "admin"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.db_username))
    error_message = "db_username must be a valid MySQL identifier."
  }
}

variable "enable_deletion_protection" {
  description = "Whether to enable RDS deletion protection. Defaults on for production hygiene; set false locally if you need fast destroy/apply iteration."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for ECS container logs."
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653, 0], var.log_retention_days)
    error_message = "log_retention_days must be a value accepted by CloudWatch Logs retention settings."
  }
}
