data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Single AZ on purpose: HA is explicitly optional for this lab, and a second
  # AZ doubles the subnets and the NAT hop for no assessable benefit.
  az = coalesce(var.availability_zone, data.aws_availability_zones.available.names[0])
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.name }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = var.name }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.public_subnet_cidr
  availability_zone = local.az

  # Public addressing is granted explicitly via an EIP, never implicitly on
  # launch, so a future instance in this subnet cannot become internet-facing
  # by accident.
  map_public_ip_on_launch = false

  tags = { Name = "${var.name}-public" }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = local.az

  tags = { Name = "${var.name}-private" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-public" }
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Deliberately has no default route. The NAT hop is an instance ENI owned by
# the compute layer, so the caller adds that route once the instance exists.
# Until then the private subnet is fail-closed, which is the state we want.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-private" }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# The VPC's default SG is attached to nothing, but AWS ships it with an
# allow-all-from-self rule. Managing it empty keeps CIS/Trivy checks green and
# makes accidental use harmless.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-default-unused" }
}
