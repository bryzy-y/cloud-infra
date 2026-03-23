data "terraform_remote_state" "platform" {
  backend = "s3"

  config = {
    bucket       = "cloud-terra-state"
    key          = "platform/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

locals {
  platform = data.terraform_remote_state.platform.outputs
}

module "airflow" {
  source = "../../modules/airflow"

  cluster            = local.platform.ecs_cluster_name
  vpc_id             = local.platform.vpc_id
  private_subnet_ids = local.platform.private_subnet_ids
}

