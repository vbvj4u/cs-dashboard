# Part 2 - VPC & Subnets (2 AZs, 2 public, 2 private, no NAT, no S3 endpoint)

data "aws_availability_zones" "available" {
  # checkov:skip=CKV_AWS_394: intentionally not pinning AZ names - taking the first 2 available AZs by index keeps this portable across regions/accounts rather than hardcoding e.g. us-east-1a/1b.
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2) # us-east-1a, us-east-1b
}

resource "aws_vpc" "this" {
  # checkov:skip=CKV2_AWS_11: VPC Flow Logs need a CloudWatch Logs/S3 destination and bill per GB ingested - out of scope for this free-tier pass; revisit if this ever carries real traffic.
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true # "ESSENTIAL" per the tutorial - EFS mount by DNS name needs it
  enable_dns_support   = true

  tags = { Name = "${var.name}-vpc" }
}

# Lock down the VPC's default SG (unused by any resource here, but AWS
# creates it automatically and it defaults to allow-all).
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  # no ingress/egress blocks => no rules => all traffic denied

  tags = { Name = "${var.name}-default-sg-locked" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-igw" }
}

resource "aws_subnet" "public" {
  # checkov:skip=CKV_AWS_130: this deployment has no NAT gateway/ALB by design (free-tier constraint) - the ECS instance and EFS mount need a public IP to be reachable at all.
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true # "auto-assign public IPv4 address must be enabled at all costs"

  tags = { Name = "${var.name}-subnet-public${count.index + 1}-${local.azs[count.index]}" }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = { Name = "${var.name}-subnet-private${count.index + 1}-${local.azs[count.index]}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.name}-rtb-public" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private subnets: local routing only (no NAT gateway - it isn't free tier)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-rtb-private" }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
