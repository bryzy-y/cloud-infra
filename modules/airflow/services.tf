resource "aws_security_group" "airflow" {
  name        = "airflow-sg"
  description = "Security group for Airflow ECS cluster"
  vpc_id      = var.vpc_id

  # Allow inbound traffic on port 8080 for Airflow webserver
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic (adjust as needed for tighter security)
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
  desired_count       = 1
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
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.airflow.id]
  }
}
