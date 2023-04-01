resource "aws_vpc" "omegaup" {
  cidr_block                       = "172.31.0.0/16"
  assign_generated_ipv6_cidr_block = true

  tags = {
    Name                                        = "omegaup-vpc"
    "kubernetes.io/cluster/omegaup-eks-cluster" = "shared"
  }
}

resource "aws_security_group" "default" {
  name                   = "default"
  description            = "default VPC security group"
  vpc_id                 = aws_vpc.omegaup.id
  revoke_rules_on_delete = false

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
  }
}

resource "aws_db_instance" "omegaup" {
  identifier          = "omegaup-db"
  db_name             = "omegaup"
  availability_zone   = "us-east-1e"
  instance_class      = "db.t2.large"
  allocated_storage   = 10
  engine              = "mysql"
  engine_version      = "8.0.28"
  deletion_protection = true
  enabled_cloudwatch_logs_exports = [
    "slowquery",
  ]
  backup_retention_period      = 7
  monitoring_interval          = 60
  performance_insights_enabled = true
  publicly_accessible          = true
  skip_final_snapshot          = true
  vpc_security_group_ids = [
    aws_security_group.default.id,
    # TODO: import these too.
    "sg-0f2905143254e07d2",
    "sg-4835ea3b",
  ]

  tags = {
    "workload-type" = "production"
  }

  lifecycle {
    ignore_changes = [
      latest_restorable_time,
    ]
  }
}

resource "aws_db_parameter_group" "omegaup_frontend" {
  name        = "omegaup-frontend"
  description = "The parameter group for the omegaup database"
  family      = "mysql8.0"

  parameter {
    apply_method = "immediate"
    name         = "collation_connection"
    value        = "utf8mb4_unicode_ci"
  }
  parameter {
    apply_method = "immediate"
    name         = "default_collation_for_utf8mb4"
    value        = "utf8mb4_general_ci"
  }
  parameter {
    apply_method = "immediate"
    name         = "slow_query_log"
    value        = "1"
  }
}

resource "aws_db_instance" "omegaup_readonly" {
  identifier          = "omegaup-db-readonly"
  instance_class      = "db.t3.small"
  replicate_source_db = aws_db_instance.omegaup.id
  availability_zone   = "us-east-1a"
  skip_final_snapshot = true
}
