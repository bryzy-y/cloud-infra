variable "aws_region" {
  description = "AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "ecs_instance_types" {
  description = "Allowed EC2 instance types for ECS managed instances"
  type        = list(string)
  default     = ["t4g.*"]
}

variable "ecs_instance_memory_mib" {
  description = "Memory (in MiB) for ECS managed instances"
  type = object({
    min = number
    max = number
  })
  default = {
    min = 2048
    max = 16384
  }
}

variable "ecs_instance_vcpu_count" {
  description = "vCPU count for ECS managed instances"
  type = object({
    min = number
    max = number
  })
  default = {
    min = 2
    max = 4
  }
}
