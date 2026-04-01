output "airflow_service" {
  description = "Airflow ECS service name"
  value       = aws_ecs_service.airflow_service.name
}

output "airflow_task_definition_arn" {
  description = "ARN of the Airflow task definition for running one-off tasks"
  value       = aws_ecs_task_definition.airflow_utils.arn
}

output "airflow_db_instance_address" {
  description = "Address of the Airflow metadata database instance"
  value       = aws_db_instance.this.address
}

output "airflow_db_admin_credentials_arn" {
  description = "ARN of the SSM parameter storing the Airflow DB admin credentials"
  value       = aws_ssm_parameter.db_admin_credentials.arn
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
