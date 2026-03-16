# Main VPC
data "aws_vpc" "this" {
  filter {
    name   = "tag:Name"
    values = ["main"]
  }
}

# We will host airflow-core in the private ipv6-only subnet
data "aws_subnet" "this" {
  vpc_id = data.aws_vpc.this.id

  filter {
    name   = "tag:Name"
    values = ["private"]
  }
}

resource "aws_security_group" "airflow" {
  name        = "airflow"
  description = "Attached to Airflow ECS tasks. Allows all egress; no ingress required for standalone smoke-tests."
  vpc_id      = data.aws_vpc.this.id

  egress {
    description = "All outbound IPv4"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description      = "All outbound IPv6"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = { Name = "airflow" }
}


module "airflow" {
  source = "../../modules/airflow"

  name   = "main"
  region = "us-east-1"

  subnet_ids         = [data.aws_subnet.this.id]
  security_group_ids = [aws_security_group.airflow.id]
}
