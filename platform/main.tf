locals {
  common_tags = {
    Environment = "prod"
    Project     = local.project
    ManagedBy   = "terraform"
  }

  project = "data-platform"
}

# Main VPC and networking resources for the platform.
resource "aws_vpc" "main" {
  cidr_block                       = "10.0.0.0/16"
  assign_generated_ipv6_cidr_block = true

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    {
      Name = "${local.project}-main-vpc"
    },
    local.common_tags
  )
}

# Internet Gateways
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = merge(
    {
      Name = "${local.project}-igw"
    },
    local.common_tags
  )
}

# Egress-Only Internet Gateway for IPv6-only private subnets
resource "aws_egress_only_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = merge(
    {
      Name = "${local.project}-egress-only-igw"
    },
    local.common_tags
  )
}

# # NAT Gateway (placed in the public subnet for IPv4 egress from private subnets)
resource "aws_eip" "nat" {
  domain = "vpc"
  tags = merge(
    {
      Name = "${local.project}-nat"
      Tier = "public"
    },
    local.common_tags
  )
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  tags = merge(
    {
      Name = "${local.project}-nat-gateway"
      Tier = "public"
    },
    local.common_tags
  )

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

  tags = merge(
    {
      Name = "${local.project}-public-1a"
      Tier = "public"
      AZ   = "us-east-1a"
    },
    local.common_tags
  )
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  availability_zone = "us-east-1a"

  cidr_block      = "10.0.1.0/24"
  ipv6_cidr_block = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, 2)

  assign_ipv6_address_on_creation = true

  tags = merge(
    {
      Name = "${local.project}-private-1a"
      Tier = "private"
      AZ   = "us-east-1a"
    },
    local.common_tags
  )
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  availability_zone = "us-east-1b"

  cidr_block      = "10.0.2.0/24"
  ipv6_cidr_block = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, 3)

  assign_ipv6_address_on_creation = true

  tags = merge(
    {
      Name = "${local.project}-private-1b"
      Tier = "private"
      AZ   = "us-east-1b"
    },
    local.common_tags
  )
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

  tags = merge(
    {
      Name = "${local.project}-rt-public"
      Tier = "public"
    },
    local.common_tags
  )
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

  tags = merge(
    {
      Name = "${local.project}-rt-private"
      Tier = "private"
    },
    local.common_tags
  )
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

  tags = merge(
    {
      Name = "${local.project}-s3-endpoint"
      Tier = "private"
    },
    local.common_tags
  )
}

locals {
  tailscale_port = 41641
}

# Tailscale direct-connection port (STUN / WireGuard). Allowing inbound
# enables reliable direct peer connections; without this, traffic falls
# back to DERP relay which still works but adds latency.
resource "aws_security_group" "tailscale" {
  name        = "tailscale-sg"
  description = "Tailscale subnet router - allow Tailscale UDP and full outbound"
  vpc_id      = aws_vpc.main.id

  ingress {
    description      = "Tailscale direct connections"
    from_port        = local.tailscale_port
    to_port          = local.tailscale_port
    protocol         = "udp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    description      = "All outbound"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

module "tailscale" {
  source  = "masterpointio/tailscale/aws"
  version = "2.1.0"

  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.public.id] # Ensure subnet router is in a public subnet

  advertise_routes = [
    aws_subnet.public.cidr_block,
    aws_subnet.private_a.cidr_block,
    aws_subnet.private_b.cidr_block,
  ]

  additional_security_group_ids = [aws_security_group.tailscale.id]  # Attach the security group to the subnet router
  tailscaled_extra_flags        = ["--port=${local.tailscale_port}"] # Ensure `tailscaled` listens on the same port as the security group is configured

  instance_type           = "t4g.nano"
  desired_capacity        = 1
  ssh_enabled             = false
  session_logging_enabled = false
  ssm_state_enabled       = true

  name        = "tailscale-subnet-router"
  primary_tag = "router"

  tags = local.common_tags
}

