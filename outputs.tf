output "vpc_id" {
  description = "Created VPC ID."
  value       = aws_vpc.platform.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs for EKS workloads and RDS."
  value       = aws_subnet.private[*].id
}

output "ecr_repository_url" {
  description = "Immutable Amazon ECR repository URL."
  value       = aws_ecr_repository.enrollment_service.repository_url
}

output "enrollment_queue_url" {
  description = "Primary SQS queue URL."
  value       = aws_sqs_queue.enrollment_events.url
}

output "enrollment_dlq_arn" {
  description = "Dead-Letter Queue ARN for monitoring alerts."
  value       = aws_sqs_queue.enrollment_dlq.arn
}

output "rds_endpoint" {
  description = "Private PostgreSQL hostname."
  value       = aws_db_instance.enrollment_db.address
}

output "rds_master_secret_arn" {
  description = "Secrets Manager ARN synced into Kubernetes via ESO."
  value       = try(aws_db_instance.enrollment_db.master_user_secret[0].secret_arn, null)
}
