# Main VPC and networking resources for the platform.
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

# Egress-Only Internet Gateway for IPv6-only private subnets
resource "aws_egress_only_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "main" }
}

# # NAT Gateway (placed in the public subnet for IPv4 egress from private subnets)
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "nat" }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  tags          = { Name = "main" }

  depends_on = [aws_internet_gateway.main]
}


# Subnets
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  availability_zone = "us-east-1a"

  # IPv4
  cidr_block      = "10.0.0.0/24"
  ipv6_cidr_block = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, 0)

  # IPv6 – /64 carved from the VPC /56
  assign_ipv6_address_on_creation = true
  map_public_ip_on_launch         = true

  tags = { Name = "public-1a" }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  availability_zone = "us-east-1a"

  cidr_block      = "10.0.1.0/24"
  ipv6_cidr_block = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, 2)

  assign_ipv6_address_on_creation = true

  tags = { Name = "private-1a" }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  availability_zone = "us-east-1b"

  cidr_block      = "10.0.2.0/24"
  ipv6_cidr_block = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, 3)

  assign_ipv6_address_on_creation = true

  tags = { Name = "private-1b" }
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

  tags = { Name = "rt-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Route Table – Private
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  # IPv4 default -> NAT Gateway
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  # IPv6 default -> Egress-Only IGW (outbound-only)
  route {
    ipv6_cidr_block        = "::/0"
    egress_only_gateway_id = aws_egress_only_internet_gateway.main.id
  }

  tags = { Name = "rt-private" }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}


resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  # Associate with the private route table so only private-subnet traffic
  # uses the endpoint;
  route_table_ids = [aws_route_table.private.id]

  # Subnet is IPv6-only
  ip_address_type = "dualstack"

  tags = { Name = "s3-endpoint" }
}
