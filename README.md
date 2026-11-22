MARKDOWN
# TUF Cloud-Native Platform — Terraform Staging Foundation
 
## Requirements
- Terraform >= 1.11.0 (for S3 native use_lockfile = true locking)
- AWS CLI v2 using short-lived SSO/OIDC credentials (never hardcode keys)
 
## Safe Offline Validation (Free — Creates Nothing)
  terraform fmt -check
  terraform init -backend=false
  terraform validate
  terraform plan -var="environment=staging" -out=tfplan
 
## Controlled Apply & Cleanup (Instructor Approval Required)
- Estimated sandbox cost: ~$54.78/month if left running 24×7 (~$0.075/hour).
- Apply only with approval: terraform apply tfplan
- Tear down immediately after demo: terraform destroy -var="environment=staging"
