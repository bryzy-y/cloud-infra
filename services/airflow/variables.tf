variable "aws_region" {
  description = "AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "vpc_name" {
  description = "VPC name where Airflow will be deployed"
  type        = string
}

variable "cluster" {
  description = "ECS cluster name where Airflow tasks will run"
  type        = string
}

variable "db_admin_user" {
  description = "Admin username of the Airflow metadata database (RDS)"
  type        = string
}

variable "db_admin_password" {
  description = "Admin password of the Airflow metadata database (RDS)"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class for the Airflow metadata database"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_storage_size" {
  description = "Allocated storage size (in GB) for the Airflow metadata database"
  type        = number
  default     = 20
}

variable "airflow_version" {
  description = "Airflow version to deploy (used in the Airflow image tag)."
  type        = string
}

variable "ssm_tailscale_auth_key" {
  description = "SSM parameter name holding the Tailscale auth key for the sidecar"
  type        = string
}
