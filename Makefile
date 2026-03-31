.PHONY: airflow-budget platform-budget deploy-airflow

airflow-budget:
	@infracost breakdown --path services/airflow

platform-budget:
	@infracost breakdown --path platform

deploy-airflow:
	@cd services/airflow && terraform apply -auto-approve
	@cd deployments && uv run main.py airflow --task deploy --terraform-dir ../services/airflow/