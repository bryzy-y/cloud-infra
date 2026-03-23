.PHONY: airflow-budget platform-budget

airflow-budget:
	@infracost breakdown --path services/airflow

platform-budget:
	@infracost breakdown --path platform