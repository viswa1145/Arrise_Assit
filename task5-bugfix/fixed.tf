# Fixed version. Applied in Account B (111111111111).
# Explanation of both bugs is in ../NOTES.md (Task 5).

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
  region              = "us-east-1"
  allowed_account_ids = ["111111111111"]
}

variable "bucket_name" {
  description = "The single bucket roleC may access."
  type        = string
  default     = "arrise-shared-data-111111111111"
}

data "aws_iam_policy_document" "roleC_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "AWS"
      # FIX 1: roleB is an IAM *role*, so its ARN path is role/, not user/.
      identifiers = ["arn:aws:iam::000000000000:role/roleB"]
    }
  }
}

resource "aws_iam_role" "roleC" {
  name               = "roleC"
  assume_role_policy = data.aws_iam_policy_document.roleC_trust.json
}

resource "aws_iam_role_policy" "roleC_s3" {
  name = "roleC-s3-access"
  role = aws_iam_role.roleC.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "s3:*"
      # FIX 2: scope to the one named bucket — the bucket ARN for bucket-level
      # actions (ListBucket, GetBucketLocation...) and bucket/* for objects.
      Resource = [
        "arn:aws:s3:::${var.bucket_name}",
        "arn:aws:s3:::${var.bucket_name}/*",
      ]
    }]
  })
}
