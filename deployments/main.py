import boto3
import json
import subprocess
import argparse
from typing import Any, Dict, TYPE_CHECKING
from dataclasses import dataclass
import logging

if TYPE_CHECKING:
    from mypy_boto3_ecs import ECSClient, TasksStoppedWaiter

logger = logging.getLogger("deploy.airflow")


def parse_terraform_output(terraform_dir: str) -> Dict[str, Any]:
    """
    Runs 'terraform output -json' in the given directory and parses the output into a Python dict.
    """
    result = subprocess.run(
        ["terraform", "output", "-json"],
        cwd=terraform_dir,
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(result.stdout)


class DeploymentError(Exception):
    """Custom exception for deployment errors."""

    pass


@dataclass
class AirflowContext:
    """
    Context information needed for Airflow deployment tasks.
    """

    service_name: str
    task_definition_arn: str
    cluster_name: str
    subnet_ids: list[str]
    security_group_ids: list[str]

    @classmethod
    def from_terraform_output(cls, tf_output: Dict[str, Any]) -> "AirflowContext":
        return cls(
            service_name=tf_output["airflow_service"]["value"],
            task_definition_arn=tf_output["airflow_task_definition_arn"]["value"],
            cluster_name=tf_output["cluster_name"]["value"],
            subnet_ids=tf_output["private_subnet_ids"]["value"],
            security_group_ids=[tf_output["airflow_security_group_id"]["value"]],
        )


def wait_for_success(
    ecs: "ECSClient", waiter: "TasksStoppedWaiter", cluster_name: str, task_arn: str
) -> None:
    """
    Waits for the given ECS task to stop and checks if it succeeded. Raises DeploymentError if the task failed.
    """

    waiter.wait(cluster=cluster_name, tasks=[task_arn])

    # Check task exit code
    desc = ecs.describe_tasks(cluster=cluster_name, tasks=[task_arn])
    containers = desc["tasks"][0]["containers"]
    exit_code = containers[0].get("exitCode")

    if exit_code != 0:
        reason = containers[0].get("reason", "Unknown")
        raise DeploymentError(
            f"Task {task_arn} failed with exit code {exit_code}: {reason}"
        )


def db_migrate(
    ctx: AirflowContext, ecs: "ECSClient", waiter: "TasksStoppedWaiter"
) -> None:
    """Starts a one-off ECS task to run 'airflow db migrate' and waits for it to complete successfully."""

    response = ecs.run_task(
        cluster=ctx.cluster_name,
        taskDefinition=ctx.task_definition_arn,
        overrides={
            "containerOverrides": [
                {
                    "name": "airflow-utils",
                    "command": [
                        "bash",
                        "-c",
                        "airflow db migrate",
                    ],
                }
            ]
        },
        networkConfiguration={
            "awsvpcConfiguration": {
                "subnets": ctx.subnet_ids,
                "securityGroups": ctx.security_group_ids,
                "assignPublicIp": "DISABLED",
            }
        },
        count=1,
        tags=[{"key": "task", "value": "db-migrate"}],
    )
    task_arn = response["tasks"][0]["taskArn"]
    logger.info(f"Started db-migrate task: {task_arn}")

    # Wait for task to finish
    wait_for_success(ecs, waiter, ctx.cluster_name, task_arn)
    logger.info("db-migrate task completed successfully.")


def create_admin_user(
    ctx: AirflowContext, ecs: "ECSClient", waiter: "TasksStoppedWaiter"
) -> None:
    """Starts a one-off ECS task to create an Airflow admin user and waits for it to complete successfully."""

    response = ecs.run_task(
        cluster=ctx.cluster_name,
        taskDefinition=ctx.task_definition_arn,
        overrides={
            "containerOverrides": [
                {
                    "name": "airflow-utils",
                    "command": [
                        "bash",
                        "-c",
                        "airflow users create -u admin -p admin -r Admin -e admin@example.com -f Admin -l Admin",
                    ],
                }
            ]
        },
        networkConfiguration={
            "awsvpcConfiguration": {
                "subnets": ctx.subnet_ids,
                "securityGroups": ctx.security_group_ids,
                "assignPublicIp": "DISABLED",
            }
        },
        count=1,
        tags=[{"key": "task", "value": "create-admin-user"}],
    )
    task_arn = response["tasks"][0]["taskArn"]
    logger.info(f"Started create-admin-user task: {task_arn}")

    wait_for_success(ecs, waiter, ctx.cluster_name, task_arn)
    logger.info("create-admin-user task completed successfully.")


def deploy_airflow(terraform_dir: str) -> None:
    """
    Deployment pipeline for Airflow service.
    """

    logger.info(f"Parsing Terraform output from: {terraform_dir}")
    tf_output = parse_terraform_output(terraform_dir)

    # Create reusable context and AWS clients
    ctx = AirflowContext.from_terraform_output(tf_output)
    ecs = boto3.client("ecs")
    waiter = ecs.get_waiter("tasks_stopped")

    # Start db-migrate task
    logger.info(f"Launching db-migrate task in ECS cluster '{ctx.cluster_name}'...")
    db_migrate(ctx, ecs, waiter)

    # Start create-admin-user task
    logger.info(
        f"Launching create-admin-user task in ECS cluster '{ctx.cluster_name}'..."
    )
    create_admin_user(ctx, ecs, waiter)

    # Update airflow service to 1 desired count
    logger.info(
        f"Updating Airflow service '{ctx.service_name}' to 1 desired instance..."
    )
    ecs.update_service(
        cluster=ctx.cluster_name, service=ctx.service_name, desiredCount=1
    )
    logger.info("Airflow service update complete.")


def main():
    """
    Main entry point for the deployment utility.
    """

    logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")
    parser = argparse.ArgumentParser(description="Deployment utility")
    subparsers = parser.add_subparsers(dest="command", required=True)

    airflow_parser = subparsers.add_parser(
        "airflow", help="Run airflow deployment tasks"
    )
    airflow_parser.add_argument(
        "--task",
        choices=["deploy"],
        default="deploy",
        help="Airflow task to run",
    )
    airflow_parser.add_argument(
        "--terraform-dir", required=True, help="Path to airflow terraform directory"
    )

    args = parser.parse_args()

    if args.command == "airflow":
        match args.task:
            case "deploy":
                deploy_airflow(terraform_dir=args.terraform_dir)
            case _:
                parser.exit(1, f"Unknown Airflow task: {args.task}")


if __name__ == "__main__":
    main()
