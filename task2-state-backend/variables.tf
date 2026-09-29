variable "region" {
  description = "Region for the state bucket and lock table."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name, applied as the Project default tag."
  type        = string
  default     = "arrise"
}

variable "state_bucket_name" {
  description = "Globally unique bucket name. Null = arrise-tfstate-<account>-<region>."
  type        = string
  default     = null
}

variable "lock_table_name" {
  description = "DynamoDB table used for state locking."
  type        = string
  default     = "terraform-state-locks"
}

variable "state_version_retention_days" {
  description = "Days to keep non-current state file versions."
  type        = number
  default     = 90

  validation {
    condition     = var.state_version_retention_days >= 30
    error_message = "Keep at least 30 days of state history."
  }
}
