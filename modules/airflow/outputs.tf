output "cluster_arn" {
  description = "ARN of the ECS cluster."
  value       = aws_ecs_cluster.airflow.arn
}

output "cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.airflow.name
}

output "execution_role_arn" {
  description = "ARN of the ECS task execution IAM role."
  value       = aws_iam_role.ecs_task_execution.arn
}

output "task_role_arn" {
  description = "ARN of the ECS task IAM role."
  value       = aws_iam_role.ecs_task.arn
}

output "log_group_name" {
  description = "Name of the CloudWatch log group."
  value       = aws_cloudwatch_log_group.airflow.name
}

output "standalone_task_definition_arn" {
  description = "ARN of the Airflow standalone ECS task definition."
  value       = aws_ecs_task_definition.airflow_standalone.arn
}

output "standalone_service_name" {
  description = "Name of the ECS service running the Airflow standalone task."
  value       = aws_ecs_service.airflow_standalone.name
}
