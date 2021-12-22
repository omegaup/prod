resource "aws_vpc" "omegaup" {
  cidr_block = "172.31.0.0/16"

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
  name                = "omegaup"
  availability_zone   = "us-east-1e"
  instance_class      = "db.t2.large"
  allocated_storage   = 10
  engine              = "mysql"
  engine_version      = "8.0.23"
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

resource "aws_db_instance" "omegaup_readonly" {
  identifier          = "omegaup-db-readonly"
  name                = "omegaup"
  instance_class      = "db.t3.small"
  replicate_source_db = aws_db_instance.omegaup.id
  availability_zone   = "us-east-1a"
  engine              = "mysql"
  engine_version      = "8.0.27"
}
