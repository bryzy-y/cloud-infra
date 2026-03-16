terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket       = "cloud-terra-state"
    key          = "services/airflow/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
