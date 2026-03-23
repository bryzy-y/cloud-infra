######################### ECS Task Role and Execution Role #########################

data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "ecs-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

resource "aws_iam_role" "airflow_task" {
  name               = "airflow-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}


data "aws_iam_policy_document" "execution_ssm_parameter_access" {
  statement {
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]

    resources = [
      "arn:aws:ssm:${local.aws_region}:${local.account_id}:parameter${var.tailscale_auth_key_ssm_parameter_name}",
      "arn:aws:ssm:${local.aws_region}:${local.account_id}:parameter${var.airflow_db_admin_password_ssm_parameter_name}",
    ]
  }
}

data "aws_iam_policy_document" "task_serve_config_ssm_access" {
  statement {
    effect  = "Allow"
    actions = ["ssm:GetParameter"]
    resources = [
      "arn:aws:ssm:${local.aws_region}:${local.account_id}:parameter${var.tailscale_serve_config_ssm_parameter_name}",
    ]
  }
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "execution_ssm_parameter_access" {
  name   = "ecs-task-execution-ssm-parameter-access"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_ssm_parameter_access.json
}

resource "aws_iam_role_policy" "task_serve_config_ssm_access" {
  name   = "airflow-core-task-serve-config-ssm-access"
  role   = aws_iam_role.airflow_task.id
  policy = data.aws_iam_policy_document.task_serve_config_ssm_access.json
}



