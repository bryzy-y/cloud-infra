data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  aws_region = data.aws_region.current.id
  account_id = data.aws_caller_identity.current.account_id
}

resource "aws_cloudwatch_log_group" "airflow" {
  name              = "/ecs/airflow"
  retention_in_days = 14
}

resource "aws_ssm_parameter" "tailscale_serve_config" {
  name = var.tailscale_serve_config_ssm_parameter_name
  type = "String"
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
      command    = ["aws ssm get-parameter --name ${var.tailscale_serve_config_ssm_parameter_name} --region ${local.aws_region} --query Parameter.Value --output text > /var/ts-config/serve.json"]

      mountPoints = [{
        sourceVolume  = "ts-serve-config"
        containerPath = "/var/ts-config"
        readOnly      = false
      }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.airflow.name
          awslogs-region        = local.aws_region
          awslogs-stream-prefix = "ts-config-init"
        }
      }
    },
    {
      name      = "tailscale"
      image     = "tailscale/tailscale:stable"
      essential = true

      dependsOn = [{
        containerName = "ts-config-init"
        condition     = "SUCCESS"
      }]

      secrets = [{
        name      = "TS_AUTHKEY"
        valueFrom = "arn:aws:ssm:${local.aws_region}:${local.account_id}:parameter${var.tailscale_auth_key_ssm_parameter_name}"
      }]

      environment = [
        {
          name  = "TS_HOSTNAME"
          value = var.tailscale_hostname
        },
        {
          name  = "TS_USERSPACE"
          value = "false"
        },
        {
          name  = "TS_SERVE_CONFIG"
          value = "/var/ts-config/serve.json"
        }
      ]

      mountPoints = [{
        sourceVolume  = "ts-serve-config"
        containerPath = "/var/ts-config"
        readOnly      = true
      }]

      linuxParameters = {
        capabilities = {
          add = ["NET_ADMIN", "NET_RAW"]
        }
        devices = [{
          hostPath      = "/dev/net/tun"
          containerPath = "/dev/net/tun"
          permissions   = ["read", "write", "mknod"]
        }]
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.airflow.name
          awslogs-region        = local.aws_region
          awslogs-stream-prefix = "tailscale"
        }
      }
    },
    {
      name      = "airflow"
      image     = "apache/airflow:slim-latest"
      essential = true
      command   = ["airflow", "standalone"]

      dependsOn = [{
        containerName = "tailscale"
        condition     = "START"
      }]

      portMappings = [{
        containerPort = 8080
        hostPort      = 8080
        protocol      = "tcp"
      }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.airflow.name
          awslogs-region        = local.aws_region
          awslogs-stream-prefix = "airflow"
        }
      }
    }
  ])
}

locals {
  db_init_psql_base = "psql -h ${var.airflow_db_host} -p ${var.airflow_db_port} -U ${var.airflow_db_admin_username}"

  db_init_psql_commands = [
    "${local.db_init_psql_base} -d postgres -c \"CREATE DATABASE airflow_db;\"",
    "${local.db_init_psql_base} -d postgres -c \"CREATE USER airflow_user WITH PASSWORD 'airflow_pass';\"",
    "${local.db_init_psql_base} -d postgres -c \"GRANT ALL PRIVILEGES ON DATABASE airflow_db TO airflow_user;\"",
    "${local.db_init_psql_base} -d airflow_db -c \"GRANT ALL ON SCHEMA public TO airflow_user;\"",
  ]
}

resource "aws_ecs_task_definition" "db_init" {
  family             = "airflow-db-init"
  task_role_arn      = aws_iam_role.airflow_task.arn
  execution_role_arn = aws_iam_role.execution.arn

  cpu    = "256"
  memory = "512"

  network_mode             = "awsvpc"
  requires_compatibilities = ["MANAGED_INSTANCES"]

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name      = "db-init"
      image     = "alpine/psql:latest"
      essential = true
      entryPoint = [
        "/bin/sh",
        "-c"
      ]
      command = [
        join(" && ", local.db_init_psql_commands)
      ]
      secrets = [
        {
          name      = "PGPASSWORD"
          valueFrom = "arn:aws:ssm:${local.aws_region}:${local.account_id}:parameter${var.airflow_db_admin_password_ssm_parameter_name}"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.airflow.name
          awslogs-region        = local.aws_region
          awslogs-stream-prefix = "db-init"
        }
      }
    }
  ])
}
