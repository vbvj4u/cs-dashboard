# Part 4 - ECS cluster backed by one EC2 instance ("EC2 Linux + Networking")

resource "aws_ecs_cluster" "this" {
  # checkov:skip=CKV_AWS_65: Container Insights emits custom CloudWatch metrics that bill beyond the free tier; deliberately left off for this free-tier deployment.
  name = "cluster-${var.name}"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

# ecsInstanceRole ("Create new role" in the wizard)
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_instance" {
  name               = "ecsInstanceRole-${var.name}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ecs_instance" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# awslogs log driver needs the instance role (not a task role, since these
# tasks run in bridge mode without one) to write to the log group.
data "aws_iam_policy_document" "ecs_instance_logs" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.ecs.arn}:*"]
  }
}

resource "aws_iam_role_policy" "ecs_instance_logs" {
  name   = "ecs-instance-logs-${var.name}"
  role   = aws_iam_role.ecs_instance.id
  policy = data.aws_iam_policy_document.ecs_instance_logs.json
}

resource "aws_iam_instance_profile" "ecs_instance" {
  name = "ecsInstanceProfile-${var.name}"
  role = aws_iam_role.ecs_instance.name
}

# ECS-optimised Amazon Linux 2 AMI (the wizard's default)
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

resource "aws_instance" "ecs" {
  ami                    = data.aws_ssm_parameter.ecs_ami.value
  instance_type          = var.ecs_instance_type
  subnet_id              = aws_subnet.public[0].id # public subnet 1a, same AZ as RDS
  vpc_security_group_ids = [aws_security_group.ecs.id]
  iam_instance_profile   = aws_iam_instance_profile.ecs_instance.name
  # key_name omitted => "None - unable to SSH"

  metadata_options {
    http_tokens   = "required" # enforce IMDSv2
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size = 30 # full 30 GiB EBS free tier
    volume_type = "gp2"
  }

  # checkov:skip=CKV_AWS_126: detailed (1-min) monitoring bills beyond the free-tier 5-min metrics; not worth it for a single free-tier instance.
  # checkov:skip=CKV_AWS_135: t2 family predates EBS-optimized/Nitro instances - not a supported attribute for this instance type.
  user_data = <<-EOT
    #!/bin/bash
    echo "ECS_CLUSTER=${aws_ecs_cluster.this.name}" >> /etc/ecs/ecs.config
  EOT

  tags = { Name = "ECS Instance - cluster-${var.name}" }
}

# t2.micro exposes 1024 CPU units / 982 MiB to ECS:
#   phpMyAdmin 224 CPU / 182 MiB  +  Metabase 800 CPU / 800 MiB  = 1024 / 982

# Container logs were previously discarded (no log driver configured).
# CloudWatch Logs has its own free-tier allowance, so this is a zero-cost
# addition at this scale.
resource "aws_cloudwatch_log_group" "ecs" {
  # checkov:skip=CKV_AWS_338: 1-year retention would grow storage past the free-tier allowance at any real log volume; retention is tunable via var.log_retention_days.
  # checkov:skip=CKV_AWS_158: default CloudWatch-managed encryption applies at rest; a customer-managed KMS key adds ~$1/mo for no practical gain here.
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days

  tags = { Name = "${var.name}-ecs-logs" }
}

# Part 5 - phpMyAdmin
resource "aws_ecs_task_definition" "phpmyadmin" {
  # checkov:skip=CKV_AWS_336: stock phpmyadmin:latest image writes PHP session/temp files to its root filesystem; read-only root FS is untested against it and would need a custom image to fix properly.
  family                   = "td-phpmyadmin"
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge" # "<default>" on Linux
  cpu                      = "224"
  memory                   = "182"

  container_definitions = jsonencode([{
    name      = "phpmyadmin"
    image     = "docker.io/phpmyadmin:latest"
    essential = true
    memory    = 182 # hard limit
    portMappings = [{
      hostPort      = 8080
      containerPort = 80
      protocol      = "tcp"
    }]
    environment = [{
      name  = "PMA_HOST"
      value = aws_db_instance.mysql.address
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "phpmyadmin"
      }
    }
  }])
}

# Parts 6 + 7 - Metabase with its app DB persisted on EFS (this is "revision 2")
resource "aws_ecs_task_definition" "metabase" {
  # checkov:skip=CKV_AWS_336: stock metabase/metabase:latest image writes working/temp files to its root filesystem; read-only root FS is untested against it and would need a custom image to fix properly.
  family                   = "td-metabase"
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"
  cpu                      = "800"
  memory                   = "800"

  volume {
    name = "metabase-volume"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.metabase.id
      root_directory     = "/"
      transit_encryption = "ENABLED"
    }
  }

  container_definitions = jsonencode([{
    name      = "metabase"
    image     = "metabase/metabase:latest"
    essential = true
    memory    = 800
    portMappings = [{
      hostPort      = 3000
      containerPort = 3000
      protocol      = "tcp"
    }]
    mountPoints = [{
      sourceVolume  = "metabase-volume"
      containerPath = "/mnt"
      readOnly      = false
    }]
    environment = [{
      name  = "MB_DB_FILE"
      value = "/mnt/metabase.db"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "metabase"
      }
    }
  }])

  depends_on = [aws_efs_mount_target.metabase]
}

# The tutorial uses "Run new task" by hand. Services keep one copy of each running
# and restart them if they die. Fixed host ports on a single instance mean the old
# task must stop before a new one can start, hence min 0 / max 100.
resource "aws_ecs_service" "phpmyadmin" {
  name                               = "phpmyadmin"
  cluster                            = aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.phpmyadmin.arn
  launch_type                        = "EC2"
  desired_count                      = 1
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  depends_on = [aws_instance.ecs]
}

resource "aws_ecs_service" "metabase" {
  name                               = "metabase"
  cluster                            = aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.metabase.arn
  launch_type                        = "EC2"
  desired_count                      = 1
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  depends_on = [aws_instance.ecs]
}
