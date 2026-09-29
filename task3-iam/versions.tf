terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 7.0"
    }
  }
}

# One configuration manages both accounts so the cross-account references
# (roleC trusting roleB's ARN, roleB allowed to assume roleC's ARN) are real
# resource references instead of hand-typed strings.
#
# allowed_account_ids makes Terraform refuse to run if a profile points at
# the wrong account — cheap insurance in multi-account setups.

# Default (unaliased) provider — used only by aws_iam_policy_document data
# sources, which make no API calls but still need a configured provider.
provider "aws" {
  region              = var.region
  profile             = var.account_a_profile
  allowed_account_ids = [var.account_a_id]

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Stack     = "task3-iam"
    }
  }
}

provider "aws" {
  alias               = "account_a"
  region              = var.region
  profile             = var.account_a_profile
  allowed_account_ids = [var.account_a_id]

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Stack     = "task3-iam"
    }
  }
}

provider "aws" {
  alias               = "account_b"
  region              = var.region
  profile             = var.account_b_profile
  allowed_account_ids = [var.account_b_id]

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Stack     = "task3-iam"
    }
  }
}
