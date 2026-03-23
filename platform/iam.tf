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
