# The mistakes the guardrails exist to stop, one or more per rule. It is only ever planned,
# never applied: the end-to-end check expects conftest to fail it with the messages listed in
# expected-violations.txt, no more and no fewer.

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

# A second provider without default tags, for the resource that forgets them.
provider "aws" {
  alias  = "untagged"
  region = "eu-west-1"

  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

# PAC001 and PAC002: a website bucket opened to the world three ways.
resource "aws_s3_bucket" "public_site" {
  bucket = "pacg-noncompliant-site"
}

resource "aws_s3_bucket_public_access_block" "public_site" {
  bucket                  = aws_s3_bucket.public_site.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_acl" "public_site" {
  bucket = aws_s3_bucket.public_site.id
  acl    = "public-read"
}

resource "aws_s3_bucket_policy" "public_site" {
  bucket = aws_s3_bucket.public_site.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicRead"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "arn:aws:s3:::pacg-noncompliant-site/*"
    }]
  })
}

# PAC001: a bucket with no public access block at all.
resource "aws_s3_bucket" "uploads" {
  bucket = "pacg-noncompliant-uploads"
}

resource "aws_vpc" "main" {
  cidr_block = "10.43.0.0/16"
}

# PAC003: SSH open to the internet in an inline rule.
resource "aws_security_group" "bastion" {
  name        = "pacg-bastion"
  description = "Bastion host"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# PAC003: RDP open to every IPv6 address in a standalone rule.
resource "aws_security_group_rule" "rdp" {
  type              = "ingress"
  security_group_id = aws_security_group.bastion.id
  description       = "RDP from anywhere"
  protocol          = "tcp"
  from_port         = 3389
  to_port           = 3389
  ipv6_cidr_blocks  = ["::/0"]
}

# PAC003: every protocol and port open to the internet.
resource "aws_vpc_security_group_ingress_rule" "everything" {
  security_group_id = aws_security_group.bastion.id
  description       = "Temporary debugging rule"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# Allowed: HTTPS from the internet is not a sensitive port, so this rule must not be reported.
resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.bastion.id
  description       = "HTTPS from anywhere"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# PAC004 and PAC005: a database reachable from the internet with unencrypted storage.
resource "aws_db_instance" "reporting" {
  identifier                  = "pacg-reporting"
  engine                      = "postgres"
  engine_version              = "17"
  instance_class              = "db.t4g.micro"
  allocated_storage           = 20
  username                    = "reporting"
  manage_master_user_password = true
  storage_encrypted           = false
  publicly_accessible         = true
}

# PAC005 and PAC006: a volume that leaves encryption unset and forgets two required tags.
resource "aws_ebs_volume" "scratch" {
  provider          = aws.untagged
  availability_zone = "eu-west-1a"
  size              = 50
  type              = "gp3"
  tags = {
    owner = "data-team"
  }
}
