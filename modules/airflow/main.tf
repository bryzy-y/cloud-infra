data "aws_caller_identity" "current" {}

resource "aws_ecs_cluster" "airflow" {
  name = var.name
  tags = var.tags
}

resource "aws_cloudwatch_log_group" "airflow" {
  name              = "/airflow/${var.name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# ---------------------------------------------------------------------------
# Standalone task definition
# Runs `airflow standalone` -- starts webserver + scheduler in a single
# process backed by SQLite. Intended as a smoke-test to verify the image
# launches correctly; not suitable for production use.
# ---------------------------------------------------------------------------

resource "aws_ecs_task_definition" "airflow_standalone" {
  family                   = "${var.name}-airflow-standalone"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "airflow"
      image     = var.airflow_image
      command   = ["standalone"]
      essential = true

      environment = [
        { name = "AIRFLOW__CORE__LOAD_EXAMPLES", value = "false" }
        # Route all outbound traffic through the Tailscale SOCKS5 proxy.
        # socks5h means DNS is also resolved through the proxy.
      ]

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.airflow.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "standalone"
        }
      }
    },
    {
      name      = "tailscale"
      image     = "tailscale/tailscale:latest"
      essential = true

      environment = [
        # Userspace networking – required on Fargate (no TUN device available).
        { name = "TS_USERSPACE", value = "true" },
        # Ephemeral state – Fargate has no persistent storage between tasks.
        { name = "TS_STATE_DIR", value = "/tmp/tailscale" },
        { name = "TS_HOSTNAME", value = "${var.name}-airflow-standalone" },
      ]

      secrets = [
        {
          name      = "TS_AUTHKEY"
          valueFrom = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${var.tailscale_auth_key_ssm_parameter}"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.airflow.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "tailscale"
        }
      }
    }
  ])

  tags = var.tags
}

resource "aws_ecs_service" "airflow_standalone" {
  name            = "${var.name}-airflow-standalone"
  cluster         = aws_ecs_cluster.airflow.id
  task_definition = aws_ecs_task_definition.airflow_standalone.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  # Allow Terraform to replace the task without waiting for a healthy minimum
  # so a crashed container doesn't block re-deployment.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  tags = var.tags
}
