output "ecs_cluster_name" {
  description = "Data platform ECS cluster"
  value       = aws_ecs_cluster.this.name
}

output "vpc_id" {
  description = "VPC ID for the data platform"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs for the data platform"
  value       = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

output "public_subnet_ids" {
  description = "Public subnet IDs for the data platform"
  value       = [aws_subnet.public.id]
}
