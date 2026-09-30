# Auto-detects the caller's public IP at plan/apply time so my_ip_cidr never
# has to be set by hand; var.my_ip_cidr still wins when explicitly provided.
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  my_ip_cidr = coalesce(var.my_ip_cidr, "${trimspace(data.http.my_ip.response_body)}/32")
}

# ECS cluster instance SG (Part 4, plus the 8080/3000 "My IP" rules from Parts 5 & 6)
resource "aws_security_group" "ecs" {
  # checkov:skip=CKV_AWS_382: instance sits in a public subnet with no NAT gateway/VPC endpoints (by design, to stay free-tier); full outbound is required to pull images from Docker Hub and reach AWS APIs. Inbound is already restricted to local.my_ip_cidr only.
  name        = "ecs-${var.name}"
  description = "ECS container instance - phpMyAdmin and Metabase"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "phpMyAdmin"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [local.my_ip_cidr]
  }

  ingress {
    description = "Metabase"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [local.my_ip_cidr]
  }

  egress {
    description = "All outbound - pull images from Docker Hub and reach AWS APIs via the IGW (no NAT/VPC endpoints in this free-tier setup)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "ecs-${var.name}" }
}

# RDS SG - the tutorial reuses the VPC default SG and adds MySQL from the ECS SG.
# A dedicated SG is used here so Terraform doesn't have to take over the default SG.
resource "aws_security_group" "rds" {
  name        = "rds-${var.name}"
  description = "MySQL access from the ECS cluster"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "MySQL/Aurora from ECS"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  tags = { Name = "rds-${var.name}" }
}

# Part 7 - efs-project3: NFS from the ECS cluster SG
resource "aws_security_group" "efs" {
  name        = "efs-${var.name}"
  description = "Allow NFS access to ECS Cluster"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "NFS from ECS"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  tags = { Name = "efs-${var.name}" }
}
