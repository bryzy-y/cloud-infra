resource "random_password" "airflow_user" {
  length  = 12
  special = false

  keepers = {
    "Version" = 1
  }
}

resource "aws_db_subnet_group" "this" {
  name       = "airflow-db-subnet-group"
  subnet_ids = data.aws_subnets.private_subnets.ids
}

resource "aws_security_group" "rds" {
  name        = "airflow-rds-sg"
  description = "Controls access to the Metadata RDS instance."
  vpc_id      = data.aws_vpc.this.id

  ingress {
    description      = "DB port from allowed security groups"
    from_port        = 5432
    to_port          = 5432
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_db_instance" "this" {
  identifier = "airflow-db"

  engine         = "postgres"
  engine_version = "16"

  instance_class    = var.db_instance_class
  allocated_storage = var.db_storage_size

  db_name = local.airflow_db

  username = var.db_admin_user
  password = var.db_admin_password

  # Networking
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  network_type           = "DUAL"
  multi_az               = false

  # Updates
  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false

  # Backups
  deletion_protection     = false
  skip_final_snapshot     = true
  backup_retention_period = 1

  # Metrics
  database_insights_mode       = "standard"
  performance_insights_enabled = false

  # Encryption at rest
  storage_encrypted = false

  # No public endpoint – access only from within the VPC
  publicly_accessible = false
}


resource "aws_ssm_parameter" "airflow_db_connection_str" {
  name        = "/airflow/db-connection-str"
  description = "Database connection string for Airflow to connect to its metadata database"
  type        = "SecureString"
  value       = local.airflow_connetion_str
}

/*
*
  PostgreSQL setup for Airflow metadata database
*
*/
resource "postgresql_role" "airflow_user" {
  name     = local.u_airflow
  password = local.u_airflow_pass
  login    = true

  # Do not drop the role on destroy, as it may still own database objects.
  skip_drop_role = true

  depends_on = [aws_db_instance.this]
}

resource "postgresql_grant" "db_privileges" {
  database    = local.airflow_db
  role        = local.u_airflow
  object_type = "database"
  privileges  = ["ALL"]
}

resource "postgresql_grant" "airflow_user_public_schema" {
  database    = local.airflow_db
  role        = local.u_airflow
  schema      = "public"
  object_type = "schema"
  privileges  = ["ALL"] # ALL on a schema = CREATE + USAGE
}
