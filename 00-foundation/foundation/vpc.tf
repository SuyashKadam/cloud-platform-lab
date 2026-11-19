# A VPC with private subnets only: no internet gateway, no NAT gateway, so nothing in it can reach
# the internet or be reached from it. Later modules (private RAG, Lambda) run here and talk to AWS
# services through VPC endpoints instead.

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # Both are required for interface VPC endpoints with private DNS (Module 7).
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "cpl-vpc" }
}

# One private subnet per AZ, e.g. 10.20.0.0/20 and 10.20.16.0/20.
resource "aws_subnet" "private" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index)

  tags = { Name = "cpl-private-${local.azs[count.index]}" }
}

# This route table only has the implicit "local" route (traffic inside the VPC). That's what makes
# the subnets private.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "cpl-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Gateway endpoint for S3: adds a route to S3's prefix list, so private subnets can reach S3 without
# any internet path. Gateway endpoints (S3, DynamoDB) are free; interface endpoints cost per hour.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = { Name = "cpl-s3-gateway-endpoint" }
}

# Locked down by default: no rules at all. AWS creates a default SG that allows all traffic between
# its members; taking it over here removes those rules.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
}
