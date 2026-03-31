data "aws_vpc" "this" {
  tags = {
    Name = var.vpc_name
  }
}

data "aws_subnets" "private_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }

  tags = {
    Tier = "Private"
  }
}

data "aws_region" "this" {}
data "aws_caller_identity" "this" {}

data "aws_security_group" "tailscale" {
  name = "tailscale-sg"
}

locals {
  # General
  aws_region = data.aws_region.this.id
  account_id = data.aws_caller_identity.this.account_id

  # Tailscale
  ssm_tailscale_state_arn = format(
    "arn:aws:ssm:%s:%s:parameter/tailscale/%s",
    local.aws_region,
    local.account_id,
    "airflow-state"
  )

  # Airflow DB
  airflow_db = "airflow_db"

  u_airflow      = "airflow_user"
  u_airflow_pass = random_password.airflow_user.result

  airflow_connetion_str = format(
    "postgresql+psycopg2://%s:%s@%s/%s",
    local.u_airflow,
    local.u_airflow_pass,
    aws_db_instance.this.endpoint,
    local.airflow_db
  )
}

/*
*
    ECS Service and related
*
*/

resource "aws_security_group" "airflow" {
  name        = "airflow-sg"
  description = "Security group for Airflow ECS cluster"
  vpc_id      = data.aws_vpc.this.id

  # Allow tailscale router to access Airflow webserver port (8080) in case
  # we need to access the webserver directly (without going through Tailscale sidecar)
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [data.aws_security_group.tailscale.id]
  }

  # Allow all outbound traffic
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_ecs_service" "airflow_service" {
  name                = "airflow-service"
  cluster             = var.cluster
  desired_count       = 0
  scheduling_strategy = "REPLICA"
  task_definition     = aws_ecs_task_definition.airflow.arn

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  enable_ecs_managed_tags            = true

  deployment_configuration {
    strategy = "ROLLING"
  }

  # If a deployment fails, roll back to the last known good state
  # Consider subscribing to EventBridge events for ECS deployment failures to trigger alerts
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    assign_public_ip = false
    subnets          = data.aws_subnets.private_subnets.ids
    security_groups  = [aws_security_group.airflow.id]
  }

  lifecycle {
    ignore_changes = [desired_count, capacity_provider_strategy]
  }
}

resource "aws_cloudwatch_log_group" "airflow" {
  name              = "/ecs/airflow"
  retention_in_days = 3
}

resource "aws_ssm_parameter" "tailscale_serve_config" {
  name        = "/tailscale/airflow-serve-config"
  description = "Tailscale serve config for Airflow (used to expose the Airflow webserver securely without a load balancer)"
  type        = "String"
  value = jsonencode({
    TCP = {
      "443" = {
        HTTPS = true
      }
    }
    Web = {
      "$${TS_CERT_DOMAIN}:443" = {
        Handlers = {
          "/" = {
            Proxy = "http://127.0.0.1:8080"
          }
        }
      }
    }
  })
}

/*
*
    Airflow Task definitions
*
*/

# This task definition is used for running one-off commands on Airflow cluster. It won't be used for the main Airflow service.
resource "aws_ecs_task_definition" "airflow_utils" {
  family             = "airflow-utils"
  task_role_arn      = aws_iam_role.airflow_task.arn
  execution_role_arn = aws_iam_role.execution.arn

  cpu    = "512"
  memory = "1024"

  network_mode             = "awsvpc"
  requires_compatibilities = ["MANAGED_INSTANCES"]

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name      = "airflow-utils"
      image     = "apache/airflow:${var.airflow_version}"
      essential = true
      command   = []

      secrets = [{
        name      = "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN"
        valueFrom = aws_ssm_parameter.airflow_db_connection_str.arn
      }]

      environment = [
        {
          name  = "AIRFLOW__CORE__AUTH_MANAGER"
          value = "airflow.providers.fab.auth_manager.fab_auth_manager.FabAuthManager"
        }
      ]

      mountPoints    = []
      portMappings   = []
      systemControls = []
      volumesFrom    = []

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.airflow.name
          awslogs-region        = local.aws_region
          awslogs-stream-prefix = "tasks"
        }
      }
    }
  ])

}


resource "aws_ecs_task_definition" "airflow" {
  family             = "airflow"
  task_role_arn      = aws_iam_role.airflow_task.arn
  execution_role_arn = aws_iam_role.execution.arn

  cpu    = "1024"
  memory = "2048"

  network_mode             = "awsvpc"
  requires_compatibilities = ["MANAGED_INSTANCES"]

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  volume {
    name = "ts-serve-config"
  }

  container_definitions = jsonencode([
    {
      name       = "ts-config-init"
      image      = "amazon/aws-cli"
      essential  = false
      entryPoint = ["/bin/sh", "-c"]
      command = [
        "aws ssm get-parameter --name ${aws_ssm_parameter.tailscale_serve_config.name} --region ${local.aws_region} --query Parameter.Value --output text > /var/ts-config/serve.json"
      ]

      mountPoints = [{
        sourceVolume  = "ts-serve-config"
        containerPath = "/var/ts-config"
        readOnly      = false
      }]

      environment    = []
      portMappings   = []
      systemControls = []
      volumesFrom    = []

    },

    {
      name      = "airflow"
      image     = "apache/airflow:${var.airflow_version}"
      essential = true
      command = [
        "bash",
        "-c",
        <<-EOC
          airflow api-server --port 8080 & \
          airflow scheduler & \
          airflow dag-processor & \
          airflow triggerer
        EOC
      ]

      secrets = [{
        name      = "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN"
        valueFrom = aws_ssm_parameter.airflow_db_connection_str.arn
      }]

      environment = [
        {
          name  = "AIRFLOW__CORE__AUTH_MANAGER"
          value = "airflow.providers.fab.auth_manager.fab_auth_manager.FabAuthManager"
        }
      ]
      mountPoints = []

      portMappings = [{
        containerPort = 8080
        hostPort      = 8080
        protocol      = "tcp"
      }]

      systemControls = []
      volumesFrom    = []

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8080/api/v2/monitor/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.airflow.name
          awslogs-region        = local.aws_region
          awslogs-stream-prefix = "airflow"
        }
      }
    },

    {
      name      = "tailscale"
      image     = "tailscale/tailscale:stable"
      essential = true

      secrets = [{
        name      = "TS_AUTHKEY"
        valueFrom = data.aws_ssm_parameter.tailscale_auth_key.arn
      }]

      environment = [
        {
          name  = "TS_HOSTNAME"
          value = "airflow"
        },
        {
          name  = "TS_USERSPACE"
          value = "false"
        },
        {
          name  = "TS_SERVE_CONFIG"
          value = "/var/ts-config/serve.json"
        },
        {
          name  = "TS_TAILSCALED_EXTRA_ARGS"
          value = "--state=${local.ssm_tailscale_state_arn}"
        }

      ]

      mountPoints = [{
        sourceVolume  = "ts-serve-config"
        containerPath = "/var/ts-config"
        readOnly      = true
      }]

      linuxParameters = {
        capabilities = {
          add  = ["NET_ADMIN", "NET_RAW"]
          drop = []
        }
        devices = [{
          hostPath      = "/dev/net/tun"
          containerPath = "/dev/net/tun"
          permissions   = ["read", "write", "mknod"]
        }]
      }

      portMappings   = []
      systemControls = []
      volumesFrom    = []

      dependsOn = [
        {
          containerName = "ts-config-init"
          condition     = "SUCCESS"
        },
        {
          containerName = "airflow"
          condition     = "HEALTHY"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.airflow.name
          awslogs-region        = local.aws_region
          awslogs-stream-prefix = "tailscale"
        }
      }
    },
  ])
}
