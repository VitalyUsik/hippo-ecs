terraform {
  backend "s3" {}
}

provider "aws" {
  region = var.region
}

resource "aws_vpc" "main" {
  cidr_block            = var.vpc_cidr
  enable_dns_hostnames  = true
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.private_subnet_cidrs, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
}

resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.public_subnet_cidrs, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.environment}-vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id             = aws_vpc.main.id
  service_name       = "com.amazonaws.${var.region}.ecr.dkr"
  subnet_ids         = aws_subnet.private.*.id
  security_group_ids = [aws_security_group.vpc_endpoints.id]
  vpc_endpoint_type  = "Interface"
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id             = aws_vpc.main.id
  service_name       = "com.amazonaws.${var.region}.ecr.api"
  subnet_ids         = aws_subnet.private.*.id
  security_group_ids = [aws_security_group.vpc_endpoints.id]
  vpc_endpoint_type  = "Interface"
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id           = aws_vpc.main.id
  service_name     = "com.amazonaws.${var.region}.s3"
  route_table_ids  = [aws_route_table.private.id]
  vpc_endpoint_type = "Gateway"
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id             = aws_vpc.main.id
  service_name       = "com.amazonaws.${var.region}.secretsmanager"
  subnet_ids         = aws_subnet.private.*.id
  security_group_ids = [aws_security_group.vpc_endpoints.id]
  vpc_endpoint_type  = "Interface"
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_eip" "eip" {}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.eip.id
  subnet_id     = aws_subnet.public[0].id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}