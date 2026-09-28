# Part 7 - EFS "metabase-volume": One Zone (1a), General Purpose, Bursting,
# encrypted at rest (AWS-managed key, no extra cost), no lifecycle management,
# no automatic backups (AWS Backup for EFS is not free tier)

resource "aws_efs_file_system" "metabase" {
  # checkov:skip=CKV_AWS_184: default AWS-managed key (alias/aws/elasticfilesystem) encrypts at rest for free; a customer-managed KMS key adds ~$1/mo for no practical gain here.
  availability_zone_name = local.azs[0]
  performance_mode       = "generalPurpose"
  throughput_mode        = "bursting"
  encrypted              = true
  # no lifecycle_policy block => lifecycle management off

  tags = { Name = "metabase-volume" }
}

resource "aws_efs_backup_policy" "metabase" {
  file_system_id = aws_efs_file_system.metabase.id

  backup_policy {
    status = "DISABLED" # EFS backups are not free tier
  }
}

resource "aws_efs_mount_target" "metabase" {
  file_system_id  = aws_efs_file_system.metabase.id
  subnet_id       = aws_subnet.public[0].id
  security_groups = [aws_security_group.efs.id]
}
