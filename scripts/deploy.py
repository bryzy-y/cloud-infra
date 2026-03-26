#!/usr/bin/env -S uv run

import boto3
import json
import subprocess
import argparse
from typing import Any, Dict


def parse_terraform_output(terraform_dir: str) -> Dict[str, Any]:
    """
    Runs 'terraform output -json' in the given directory and parses the output into a Python dict.
    """
    result = subprocess.run(
        ["terraform", "output", "-json"],
        cwd=terraform_dir,
        capture_output=True,
        text=True,
        check=True
    )
    return json.loads(result.stdout)


class DeploymentError(Exception):
    """Custom exception for deployment errors."""
    pass


def airflow(
    terraform_dir: str
) -> None:
    """
    Launches a db-migrate ECS task, waits for it to finish, then updates the airflow service to 1 active instance.
    """
    tf_output = parse_terraform_output(terraform_dir)

    # Extract necessary values from Terraform output
    service_name = tf_output["airflow_service"]["value"]
    db_migrate_task_def = tf_output["db_migrate_task_definition_arn"]["value"]
    cluster_name = tf_output["cluster_name"]["value"]
    subnet_ids = tf_output["private_subnet_ids"]["value"]
    security_group_ids = [tf_output["airflow_security_group_id"]["value"]]

    ecs = boto3.client("ecs")

    # Start db-migrate task
    response = ecs.run_task(
        cluster=cluster_name,
        taskDefinition=db_migrate_task_def,
        launchType="FARGATE",
        networkConfiguration={
            "awsvpcConfiguration": {
                "subnets": subnet_ids,
                "securityGroups": security_group_ids,
                "assignPublicIp": "ENABLED"
            }
        },
        count=1,
    )
    task_arn = response["tasks"][0]["taskArn"]

    # Wait for task to finish
    waiter = ecs.get_waiter("tasks_stopped")
    waiter.wait(cluster=cluster_name, tasks=[task_arn])

    # Check task exit code for success
    desc = ecs.describe_tasks(cluster=cluster_name, tasks=[task_arn])
    containers = desc["tasks"][0]["containers"]
    exit_code = containers[0].get("exitCode")
    if exit_code != 0:
        reason = containers[0].get("reason", "Unknown")
        raise DeploymentError(f"db-migrate task failed with exit code {exit_code}: {reason}")

    # Update airflow service to 1 desired count
    ecs.update_service(
        cluster=cluster_name,
        service=service_name,
        desiredCount=1
    )


def main():
    """
    Main entry point for the deployment utility.
    """
    parser = argparse.ArgumentParser(description="Deployment utility")
    subparsers = parser.add_subparsers(dest="command", required=True)

    airflow_parser = subparsers.add_parser("airflow", help="Run db-migrate and update airflow service")
    airflow_parser.add_argument("--terraform-dir", required=True, help="Path to airflow terraform directory")

    args = parser.parse_args()

    if args.command == "airflow":
        airflow(terraform_dir=args.terraform_dir)


if __name__ == "__main__":
    main()
