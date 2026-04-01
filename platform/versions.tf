terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket       = "cloud-terra-state"
    key          = "platform/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.37.0"
    }

    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }

    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.13"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

provider "tailscale" {
  oauth_client_id     = var.tailscale_oauth_id
  oauth_client_secret = var.tailscale_oauth_secret
}
