/* 
This ECS cluster will utilize "ECS Managed Instances" to run Airflow "core".

This mode spins up EC2 instances managed by AWS to run ECS tasks. It provides more control over the underlying infrastructure,
allowing for custom instance types and configurations. 

This allows for greater flexibility compared to Fargate and is more cost-effective for workloads that require persistent uptime,
such as Airflow's core components (scheduler, dag-processor, triggerer, etc.).
*/

locals {
  ecs_subnets = [aws_subnet.private_a, aws_subnet.private_b]
}

data "aws_iam_policy_document" "trust_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "trust_policy_instance" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Infrastructure role for ECS managed instances – allows ECS to manage the underlying EC2 hosts.
resource "aws_iam_role" "ecs_infrastructure" {
  name               = "ecs-infrastructure-role"
  assume_role_policy = data.aws_iam_policy_document.trust_policy.json
}

# Instance role and profile for ECS managed instances – attached to the EC2 hosts in the Auto Scaling Group.
# IMPORTANT: This role and profile must be named "ecsInstanceRole" to work with ECS managed instances.
resource "aws_iam_role" "ecs_managed_instance" {
  name               = "ecsInstanceRole"
  assume_role_policy = data.aws_iam_policy_document.trust_policy_instance.json
}

resource "aws_iam_instance_profile" "ecs_managed_instance" {
  name = "ecsInstanceRole"
  role = aws_iam_role.ecs_managed_instance.name
}

resource "aws_iam_role_policy_attachment" "ecs_instance" {
  role       = aws_iam_role.ecs_managed_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECSInstanceRolePolicyForManagedInstances"
}

resource "aws_iam_role_policy_attachment" "ecs_infrastructure" {
  role       = aws_iam_role.ecs_infrastructure.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForManagedInstances"
}


# Cluster for running Airflow "core" components.
resource "aws_ecs_cluster" "this" {
  name = "data-platform-prod"
}

# Security group for ECS managed instances – allow inbound traffic from private subnets
# and outbound traffic to anywhere
resource "aws_security_group" "managed_instances" {
  name        = "managed-instances-sg"
  description = "Security group for ECS managed instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    description      = "Allow inbound traffic from private subnets"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = [for s in local.ecs_subnets : s.cidr_block]
    ipv6_cidr_blocks = [for s in local.ecs_subnets : s.ipv6_cidr_block]
  }

  egress {
    description      = "Allow all outbound traffic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}


# Capacity provider for ECS managed instances – used for Airflow core components that require EC2 hosts.
resource "aws_ecs_capacity_provider" "managed_instances" {
  name    = "managed-instances-provider"
  cluster = aws_ecs_cluster.this.name

  managed_instances_provider {
    infrastructure_role_arn = aws_iam_role.ecs_infrastructure.arn

    instance_launch_template {
      ec2_instance_profile_arn = aws_iam_instance_profile.ecs_managed_instance.arn
      monitoring               = "BASIC"

      storage_configuration {
        storage_size_gib = 20
      }

      instance_requirements {
        cpu_manufacturers = ["amazon-web-services"]

        bare_metal            = "excluded"
        burstable_performance = "included"

        allowed_instance_types = var.ecs_instance_types

        memory_mib {
          min = var.ecs_instance_memory_mib.min
          max = var.ecs_instance_memory_mib.max
        }

        vcpu_count {
          min = var.ecs_instance_vcpu_count.min
          max = var.ecs_instance_vcpu_count.max
        }
      }

      network_configuration {
        subnets         = [for s in local.ecs_subnets : s.id]
        security_groups = [aws_security_group.managed_instances.id]
      }
    }
  }
}

# Wait for capacity provider to be active before associating with cluster
resource "time_sleep" "capacity_provider_active" {
  create_duration = "30s"

  depends_on = [
    aws_ecs_capacity_provider.managed_instances
  ]
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.this.name

  capacity_providers = [
    aws_ecs_capacity_provider.managed_instances.name,
    "FARGATE"
  ]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.managed_instances.name
    weight            = 100
  }

  depends_on = [time_sleep.capacity_provider_active]
}
