variable "aws_region" {
  description = "AWS region for the staging environment."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short project prefix for resource naming."
  type        = string
  default     = "tuf-student-platform"
}

variable "environment" {
  description = "Deployment environment (dev, staging, or prod)."
  type        = string
  default     = "staging"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "vpc_cidr" {
  description = "IPv4 CIDR range for the platform VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "db_instance_class" {
  description = "RDS PostgreSQL instance size."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "RDS gp3 storage in GiB."
  type        = number
  default     = 20
}

variable "sqs_max_receive_count" {
  description = "Delivery attempts before routing poison messages to the DLQ."
  type        = number
  default     = 5
}
