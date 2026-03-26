/*
*
  Main Roles
*
*/
resource "aws_iam_role" "execution" {
  name               = "ecs-task-execution-role"
  description        = "Role assumed by ECS when executing tasks"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

resource "aws_iam_role" "airflow_task" {
  name               = "airflow-task-role"
  description        = "Role assumed by Airflow ECS tasks"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

/*
*
  IAM Policy Documents 
*
*/

# Some data that we want to grant access to via IAM policies
data "aws_ssm_parameter" "tailscale_auth_key" {
  name = var.ssm_tailscale_auth_key
}

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

data "aws_iam_policy_document" "execution_ssm_parameter_access" {
  statement {
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]

    resources = [
      data.aws_ssm_parameter.tailscale_auth_key.arn,
      aws_ssm_parameter.airflow_db_connection_str.arn,
    ]
  }
}

data "aws_iam_policy_document" "serve_config_access" {
  statement {
    effect  = "Allow"
    actions = ["ssm:GetParameter"]
    resources = [
      aws_ssm_parameter.tailscale_serve_config.arn,
    ]
  }
}

data "aws_iam_policy_document" "tailscale_state_ownership" {
  statement {
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:PutParameter",
      "ssm:DeleteParameter"
    ]
    resources = [
      local.ssm_tailscale_state_arn
    ]
  }
}

/*
*
  IAM Role Policy Attachments 
*
*/
resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow ECS task execution role to read SSM parameters needed for task execution
resource "aws_iam_role_policy" "execution_ssm_parameter_access" {
  name   = "ecs-task-execution-ssm-parameter-access"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_ssm_parameter_access.json
}


# Allow Airflow task to read Tailscale serve config from SSM (used by the Tailscale sidecar)
resource "aws_iam_role_policy" "airflow_tailscale_serve_config_access" {
  name   = "airflow-tailscale-serve-config-access"
  role   = aws_iam_role.airflow_task.id
  policy = data.aws_iam_policy_document.serve_config_access.json
}


# Allow Airflow task to manage Tailscale state in SSM (used by the Tailscale sidecar)
resource "aws_iam_role_policy" "airflow_tailscale_state_ownership" {
  name   = "airflow-tailscale-state-ownership"
  role   = aws_iam_role.airflow_task.id
  policy = data.aws_iam_policy_document.tailscale_state_ownership.json
}



