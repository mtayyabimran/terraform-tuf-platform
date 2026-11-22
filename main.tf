terraform {
  required_version = ">= 1.11.0" # Supports native S3 lockfiles and write-only secrets

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }

  # Uncomment after the instructor provisions the encrypted, versioned S3 state bucket:
  # backend "s3" {
  #   bucket       = "tuf-platform-tfstate-us-east-1"
  #   key          = "staging/enrollment/terraform.tfstate"
  #   region       = "us-east-1"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  azs         = slice(data.aws_availability_zones.available.names, 0, 2)
}

# 1. Multi-AZ VPC, Subnets, Dev NAT Gateway & Free S3 Endpoint (15 resources)
resource "aws_vpc" "platform" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.platform.id
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.platform.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.platform.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = local.azs[count.index]
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.platform.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.platform.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_vpc_endpoint" "s3_gateway" {
  vpc_id            = aws_vpc.platform.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
}

# 2. Immutable Container Registry + Cleanup Policy (2 resources)
resource "aws_ecr_repository" "enrollment_service" {
  name                 = "${local.name_prefix}-enrollment-service"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "enrollment_cleanup" {
  repository = aws_ecr_repository.enrollment_service.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only the latest 15 immutable images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 15
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# 3. Asynchronous Messaging: SQS Queue + Dead-Letter Queue (3 resources)
resource "aws_sqs_queue" "enrollment_dlq" {
  name                      = "${local.name_prefix}-enrollment-events-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "enrollment_events" {
  name                       = "${local.name_prefix}-enrollment-events"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 345600
  sqs_managed_sse_enabled    = true
}

resource "aws_sqs_queue_redrive_policy" "enrollment_redrive" {
  queue_url = aws_sqs_queue.enrollment_events.id
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.enrollment_dlq.arn
    maxReceiveCount     = var.sqs_max_receive_count
  })
}

# 4. Private PostgreSQL 16 RDS + Least-Privilege Security Groups (4 resources)
resource "aws_security_group" "app_tier" {
  name        = "${local.name_prefix}-app-sg"
  description = "Security group for Enrollment microservice pods"
  vpc_id      = aws_vpc.platform.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds_enrollment" {
  name        = "${local.name_prefix}-rds-sg"
  description = "Allow PostgreSQL 5432 strictly from Enrollment pods"
  vpc_id      = aws_vpc.platform.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app_tier.id]
  }
}

resource "aws_db_subnet_group" "enrollment" {
  name       = "${local.name_prefix}-db-subnets"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_db_instance" "enrollment_db" {
  identifier                  = "${local.name_prefix}-enrollment-db"
  engine                      = "postgres"
  engine_version              = "16.4"
  instance_class              = var.db_instance_class
  allocated_storage           = var.db_allocated_storage
  storage_type                = "gp3"
  storage_encrypted           = true
  db_name                     = "enrollment_db"
  username                    = "enrollment_admin"
  manage_master_user_password = true # Password generated & rotated in AWS Secrets Manager
  db_subnet_group_name        = aws_db_subnet_group.enrollment.name
  vpc_security_group_ids      = [aws_security_group.rds_enrollment.id]
  publicly_accessible         = false
  multi_az                    = var.environment == "prod"
  backup_retention_period     = var.environment == "prod" ? 14 : 3
  skip_final_snapshot         = var.environment != "prod"
  deletion_protection         = var.environment == "prod"
}
