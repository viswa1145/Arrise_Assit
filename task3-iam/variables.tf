variable "region" {
  description = "Region for regional resources (S3 bucket, ARNs in the ci policy)."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name, applied as the Project default tag."
  type        = string
  default     = "arrise"
}

variable "account_a_id" {
  description = "Account A ID (identity / CI account)."
  type        = string
  default     = "000000000000"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_a_id))
    error_message = "Must be a 12-digit AWS account ID."
  }
}

variable "account_b_id" {
  description = "Account B ID (data account holding the shared bucket)."
  type        = string
  default     = "111111111111"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_b_id))
    error_message = "Must be a 12-digit AWS account ID."
  }
}

variable "account_a_profile" {
  description = "AWS CLI profile with admin credentials for Account A."
  type        = string
  default     = "account-a"
}

variable "account_b_profile" {
  description = "AWS CLI profile with admin credentials for Account B."
  type        = string
  default     = "account-b"
}

variable "console_users" {
  description = "Members of group2 (console + CLI)."
  type        = list(string)
  default     = ["alice", "bob"]
}

variable "pgp_key" {
  description = <<-EOT
    PGP public key (base64) or "keybase:<user>" used to encrypt the initial
    console passwords, so they never sit in Terraform state in plaintext.
  EOT
  type        = string
}

variable "shared_bucket_name" {
  description = "Account B bucket that roleC gets full access to."
  type        = string
  default     = "arrise-shared-data-111111111111"
}

# ---- Task 4: resources the ci user deploys to (all in Account A) ----------

variable "ci_ecr_repository" {
  description = "ECR repository the ci user may push to."
  type        = string
  default     = "arrise-app"
}

variable "ci_ecs_cluster" {
  description = "ECS cluster containing the service ci deploys."
  type        = string
  default     = "arrise-prod"
}

variable "ci_ecs_service" {
  description = "ECS service ci may update."
  type        = string
  default     = "arrise-app"
}

variable "ci_artifact_bucket" {
  description = "S3 bucket ci may read build artifacts from."
  type        = string
  default     = "arrise-build-artifacts-000000000000"
}

variable "ci_passable_role_names" {
  description = "Task execution role + task role the service's task definition references."
  type        = list(string)
  default     = ["arrise-app-task-execution", "arrise-app-task"]
}
