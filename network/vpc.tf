resource "aws_vpc" "main" {
  cidr_block                       = "10.0.0.0/16"
  assign_generated_ipv6_cidr_block = true

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "main" }
}

# Internet Gateways
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "main" }
}

resource "aws_egress_only_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "main" }
}


# Subnets
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  availability_zone = "us-east-1a"

  # IPv4
  cidr_block = "10.0.0.0/24"

  # IPv6 – /64 carved from the VPC /56
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, 0)
  assign_ipv6_address_on_creation = true

  map_public_ip_on_launch = true

  tags = { Name = "public" }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  availability_zone = "us-east-1a"

  # IPv6-only – no IPv4 CIDR assigned
  ipv6_native                                    = true
  ipv6_cidr_block                                = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, 1)
  assign_ipv6_address_on_creation                = true
  enable_resource_name_dns_aaaa_record_on_launch = true

  tags = { Name = "private" }
}

# Route Table – Public
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  # IPv4 default → IGW
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  # IPv6 default → IGW
  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.main.id
  }

  tags = { Name = "public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Route Table – Private
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  # IPv6 default → Egress-Only IGW (outbound-only, no cost)
  route {
    ipv6_cidr_block        = "::/0"
    egress_only_gateway_id = aws_egress_only_internet_gateway.main.id
  }

  tags = { Name = "private" }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}


# S3 Gateway Endpoint for IPv6-only private subnet
data "aws_region" "current" {}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"

  # Associate with the private route table so only private-subnet traffic
  # uses the endpoint; no data-transfer charges over the public internet.
  route_table_ids = [aws_route_table.private.id]

  # Subnet is IPv6-only
  ip_address_type = "ipv6"

  tags = { Name = "s3-private" }
}
