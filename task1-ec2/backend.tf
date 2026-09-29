# Task 2 — remote state in S3 with DynamoDB state locking.
#
# Backend blocks cannot reference variables, so the environment-specific
# values live in backend.hcl (see backend.hcl.example) and are supplied with:
#
#   terraform init -backend-config=backend.hcl
#
# The bucket and lock table are created by ../task2-state-backend.
terraform {
  backend "s3" {
    key     = "task1-ec2/terraform.tfstate"
    encrypt = true
  }
}
