data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  az_a = data.aws_availability_zones.available.names[0]
  az_b = data.aws_availability_zones.available.names[1]

  public_subnet_a_cidr  = cidrsubnet(var.env_config.vpc_cidr, 8, 1)
  public_subnet_b_cidr  = cidrsubnet(var.env_config.vpc_cidr, 8, 2)
  private_subnet_a_cidr = cidrsubnet(var.env_config.vpc_cidr, 8, 11)
  private_subnet_b_cidr = cidrsubnet(var.env_config.vpc_cidr, 8, 12)
}

resource "aws_vpc" "main" {
  cidr_block           = var.env_config.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "${var.prefix}-VPC", Project = var.prefix }
}

# ── Internet Gateway ───────────────────────────────────────────────────────────

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.prefix}-IGW", Project = var.prefix }
}

# ── Public Subnets ─────────────────────────────────────────────────────────────

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_a_cidr
  availability_zone       = local.az_a
  map_public_ip_on_launch = true
  tags = { Name = "${var.prefix}-Public-A", Project = var.prefix, Tier = "public" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_b_cidr
  availability_zone       = local.az_b
  map_public_ip_on_launch = true
  tags = { Name = "${var.prefix}-Public-B", Project = var.prefix, Tier = "public" }
}

# ── Private Subnets ────────────────────────────────────────────────────────────

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnet_a_cidr
  availability_zone = local.az_a
  tags = { Name = "${var.prefix}-Private-A", Project = var.prefix, Tier = "private" }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnet_b_cidr
  availability_zone = local.az_b
  tags = { Name = "${var.prefix}-Private-B", Project = var.prefix, Tier = "private" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.prefix}-Public-RT", Project = var.prefix }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# ── NAT Gateway (optional) ────────────────────────────────────────────────────

resource "aws_eip" "nat" {
  count  = var.env_config.enable_nat_gateway ? 1 : 0
  domain = "vpc"
  tags   = { Name = "${var.prefix}-NAT-EIP", Project = var.prefix }
}

resource "aws_nat_gateway" "main" {
  count         = var.env_config.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public_a.id
  tags          = { Name = "${var.prefix}-NAT", Project = var.prefix }
  depends_on    = [aws_internet_gateway.main]
}

# ── Route Tables ───────────────────────────────────────────────────────────────

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.prefix}-Private-RT", Project = var.prefix }

  dynamic "route" {
    for_each = var.env_config.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.main[0].id
    }
  }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}
