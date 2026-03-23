variable "vpc_id" {
  description = "VPC ID where Airflow core resources are deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs used by ECS managed instances and service tasks"
  type        = list(string)
}

variable "cluster" {
  description = "Cluster name"
  type        = string
}

variable "tailscale_auth_key_ssm_parameter_name" {
  description = "SSM SecureString parameter name holding the Tailscale auth key for the sidecar (for example: /airflow/ts-auth-key)."
  type        = string
  default     = "/airflow/ts-auth-key"
}

variable "tailscale_hostname" {
  description = "Hostname used by the Tailscale sidecar when joining the tailnet."
  type        = string
  default     = "airflow"
}

variable "tailscale_extra_args" {
  description = "Extra arguments passed to tailscale up via TS_EXTRA_ARGS."
  type        = string
  default     = "--accept-dns=false"
}

variable "tailscale_serve_config_ssm_parameter_name" {
  description = "SSM parameter name used to store the Tailscale serve config JSON (written at apply time, read by the init container at task startup)."
  type        = string
  default     = "/airflow/ts-serve-config"
}

variable "airflow_db_init_task_image" {
  description = "Container image used by the DB bootstrap ECS tasks (for example: alpine/psql)."
  type        = string
  default     = "alpine/psql"
}

variable "airflow_db_host" {
  description = "PostgreSQL endpoint hostname used by the DB init ECS tasks."
  type        = string
  default     = ""
}

variable "airflow_db_port" {
  description = "PostgreSQL endpoint port used by the DB init ECS tasks."
  type        = number
  default     = 5432
}

variable "airflow_db_admin_username" {
  description = "Admin username used to run DB bootstrap SQL statements."
  type        = string
  default     = "rod"
}

variable "airflow_db_admin_password_ssm_parameter_name" {
  description = "SSM SecureString parameter path holding the admin password used by DB init ECS tasks."
  type        = string
  default     = "/airflow/db-password"
}
