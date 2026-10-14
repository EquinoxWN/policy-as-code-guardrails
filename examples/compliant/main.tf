# A small AWS stack that follows every guardrail. It is only ever planned, never applied:
# scripts/tf.sh refuses apply, and the provider runs without real credentials.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"

  # Offline plan: no credential check, no account lookup, no instance metadata.
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true

  default_tags {
    tags = {
      owner       = "platform-team"
      environment = "example"
      cost_center = "cc-1042"
    }
  }
}

# Buckets from a module, one per year: each instance carries its own public access block.
module "archive" {
  source      = "../modules/private_bucket"
  for_each    = toset(["2025", "2026"])
  bucket_name = "pacg-compliant-archive-${each.key}"
}

# A root-level bucket whose only policy statement denies plain-HTTP access to everyone.
resource "aws_s3_bucket" "assets" {
  bucket = "pacg-compliant-assets"
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "assets_tls_only" {
  bucket = aws_s3_bucket.assets.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = ["arn:aws:s3:::pacg-compliant-assets", "arn:aws:s3:::pacg-compliant-assets/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

resource "aws_vpc" "main" {
  cidr_block = "10.42.0.0/16"
}

# HTTPS is the only port open to the internet.
resource "aws_security_group" "web" {
  name        = "pacg-web"
  description = "Public HTTPS entry point"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Responses and outbound calls"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "database" {
  name        = "pacg-database"
  description = "PostgreSQL, reachable from the web tier only"
  vpc_id      = aws_vpc.main.id
}

# SSH only from the private network, PostgreSQL only from the web tier's security group.
resource "aws_vpc_security_group_ingress_rule" "ssh_internal" {
  security_group_id = aws_security_group.web.id
  description       = "SSH from inside the VPC"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = "10.42.0.0/16"
}

resource "aws_security_group_rule" "postgres_from_web" {
  type                     = "ingress"
  security_group_id        = aws_security_group.database.id
  description              = "PostgreSQL from the web tier"
  protocol                 = "tcp"
  from_port                = 5432
  to_port                  = 5432
  source_security_group_id = aws_security_group.web.id
}

resource "aws_db_instance" "app" {
  identifier                  = "pacg-app"
  engine                      = "postgres"
  engine_version              = "17"
  instance_class              = "db.t4g.micro"
  allocated_storage           = 20
  username                    = "app"
  manage_master_user_password = true
  storage_encrypted           = true
  publicly_accessible         = false
  deletion_protection         = true
  vpc_security_group_ids      = [aws_security_group.database.id]
}

resource "aws_rds_cluster" "reports" {
  cluster_identifier          = "pacg-reports"
  engine                      = "aurora-postgresql"
  master_username             = "reports"
  manage_master_user_password = true
  storage_encrypted           = true
  deletion_protection         = true
  vpc_security_group_ids      = [aws_security_group.database.id]
}

resource "aws_rds_cluster_instance" "reports" {
  identifier          = "pacg-reports-1"
  cluster_identifier  = aws_rds_cluster.reports.id
  engine              = aws_rds_cluster.reports.engine
  instance_class      = "db.t4g.medium"
  publicly_accessible = false
}

resource "aws_ebs_volume" "data" {
  availability_zone = "eu-west-1a"
  size              = 20
  type              = "gp3"
  encrypted         = true
}
