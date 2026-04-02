# cloud-infra

AWS cloud infrastructure for the `data-platform` project, managed with Terraform.

## Structure

```
platform/     # Core AWS infrastructure (VPC, subnets, ECS cluster, Tailscale)
services/
  airflow/    # Apache Airflow on ECS with RDS PostgreSQL backend
deployments/  # Python scripts for post-Terraform deployment tasks
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform) >= 1.10
- [uv](https://docs.astral.sh/uv/) (Python package manager)
- [infracost](https://www.infracost.io/) (optional, for cost estimates)
- AWS credentials configured in your environment
- Tailscale OAuth credentials

## Usage

### Deploy

```bash
# Deploy platform infrastructure first
cd platform && terraform init && terraform apply

# Deploy Airflow service
make deploy-airflow
```

### Cost estimates

```bash
make platform-budget
make airflow-budget
```

### Teardown

```bash
make cleanup
```

## Architecture

- **Platform**: A VPC with public/private subnets across two AZs, an ECS cluster using EC2-managed instances, and a Tailscale node for private network access.
- **Airflow**: Runs as ECS tasks backed by an RDS PostgreSQL database. Deployment is handled by a Python script (`deployments/main.py`)
- **State**: Terraform state is stored remotely in S3 with locking enabled.
