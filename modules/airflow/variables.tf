variable "name" {
  description = "Name prefix for all resources."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "subnet_ids" {
  description = "List of private subnet IDs for the ECS tasks (minimum 2, different AZs)."
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs to attach to the ECS tasks."
  type        = list(string)
  nullable    = true
  default     = null
}

variable "ssm_parameter_prefix" {
  description = "SSM parameter path prefix for Airflow secrets, e.g. /airflow/prod. Must start with /."
  type        = string

  validation {
    condition     = startswith(var.ssm_parameter_prefix, "/")
    error_message = "ssm_parameter_prefix must start with /."
  }

  default = "/airflow"
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days."
  type        = number
  default     = 7
}

variable "airflow_image" {
  description = "Docker image used for the Airflow container."
  type        = string
  default     = "apache/airflow:slim-3.1.8"
}

variable "tailscale_auth_key_ssm_parameter" {
  description = "SSM parameter path for the Tailscale auth key (e.g. /airflow/tailscale-auth-key). Must be stored under ssm_parameter_prefix so the execution role can read it."
  type        = string
  default     = "/airflow/ts-auth-key"
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
