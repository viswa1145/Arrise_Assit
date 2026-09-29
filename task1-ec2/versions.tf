terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 7.0"
    }
  }
}

provider "aws" {
  region = var.region

  # Applied to every taggable resource this provider creates. The
  # assignment-required Name/Environment/Owner tags are set explicitly in the
  # module so they're visible in code and on volumes too.
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Stack     = "task1-ec2"
    }
  }
}
