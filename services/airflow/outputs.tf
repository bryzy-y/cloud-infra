output "airflow_service" {
  description = "Airflow ECS service name"
  value       = aws_ecs_service.airflow_service.name
}

output "db_migrate_task_definition_arn" {
  description = "ARN of the db-migrate ECS task definition"
  value       = aws_ecs_task_definition.db-migrate.arn
}

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = var.cluster
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = data.aws_subnets.private_subnets.ids
}

output "airflow_security_group_id" {
  description = "Security group ID for Airflow tasks"
  value       = aws_security_group.airflow.id
}
