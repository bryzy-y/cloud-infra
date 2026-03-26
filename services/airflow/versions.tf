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
      version = "6.37.0"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "1.26.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "postgresql" {
  scheme   = "awspostgres"
  host     = aws_db_instance.this.address
  port     = aws_db_instance.this.port
  username = aws_db_instance.this.username
  password = aws_db_instance.this.password

  superuser = false
}
