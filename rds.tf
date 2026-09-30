# Part 3 - RDS MySQL (free tier instance class/storage, private, AZ 1a, no multi-AZ/NAT - unchanged topology)

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db-subnets"
  subnet_ids = aws_subnet.private[*].id # RDS requires subnets in >= 2 AZs
}

# Generated once and stored in SSM - never passed as a variable, never in git,
# never printed by plan/apply.
resource "random_password" "db" {
  length      = 24
  special     = true
  min_upper   = 1
  min_lower   = 1
  min_numeric = 1
  # RDS MySQL disallows '/', '@', '"', and space in the master password.
  override_special = "!#$%^&*()-_=+[]{}<>:?"
}

resource "aws_ssm_parameter" "db_password" {
  name        = "/${var.name}/${var.environment}/rds/master_password"
  description = "RDS MySQL master password for ${var.name} (${var.environment}), managed by Terraform."
  type        = "SecureString"
  value       = random_password.db.result
  key_id      = "alias/aws/ssm" # AWS-managed key, no extra KMS cost

  tags = { Name = "${var.name}-rds-master-password" }
}

resource "aws_db_instance" "mysql" {
  # checkov:skip=CKV_AWS_161: IAM database authentication would require reconfiguring phpMyAdmin/Metabase's DB clients to use auth tokens instead of a password - out of scope for this hardening pass.
  # checkov:skip=CKV_AWS_157: Multi-AZ doubles RDS cost - explicitly kept single-AZ per the free-tier constraint for this deployment.
  # checkov:skip=CKV_AWS_129: log exports (esp. "general") can produce high volume/cost for an active DB - out of scope for this pass.
  # checkov:skip=CKV_AWS_118: enhanced monitoring is a further moving part (new IAM role, CloudWatch metrics) - out of scope for this pass.
  identifier     = "rds-mysql-${var.name}"
  engine         = "mysql"
  engine_version = "8.0" # let AWS pick the current 8.0 minor

  instance_class    = var.db_instance_class
  allocated_storage = 20
  storage_type      = "gp2"
  storage_encrypted = true # AWS-managed key, no extra cost
  # max_allocated_storage omitted => storage autoscaling disabled

  username = var.db_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  availability_zone      = local.azs[0]
  publicly_accessible    = false
  multi_az               = false # would double cost - left unchanged per free-tier constraint

  parameter_group_name = "default.mysql8.0"

  backup_retention_period    = 1 # AWS Free Plan caps automated backup retention at 1 day
  copy_tags_to_snapshot      = true
  auto_minor_version_upgrade = true
  deletion_protection        = var.enable_deletion_protection
  skip_final_snapshot        = false
  final_snapshot_identifier  = "rds-mysql-${var.name}-final-${var.environment}"

  tags = { Name = "rds-mysql-${var.name}" }
}
