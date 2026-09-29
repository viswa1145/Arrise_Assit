##############################################################################
# Account B (111111111111)
##############################################################################

resource "aws_s3_bucket" "shared" {
  provider = aws.account_b
  bucket   = var.shared_bucket_name
}

resource "aws_s3_bucket_public_access_block" "shared" {
  provider                = aws.account_b
  bucket                  = aws_s3_bucket.shared.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "shared" {
  provider = aws.account_b
  bucket   = aws_s3_bucket.shared.id
  rule {
    object_ownership = "BucketOwnerEnforced" # disables ACLs
  }
}

resource "aws_s3_bucket_versioning" "shared" {
  provider = aws.account_b
  bucket   = aws_s3_bucket.shared.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "shared" {
  provider = aws.account_b
  bucket   = aws_s3_bucket.shared.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

data "aws_iam_policy_document" "shared_bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.shared.arn, "${aws_s3_bucket.shared.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "shared" {
  provider = aws.account_b
  bucket   = aws_s3_bucket.shared.id
  policy   = data.aws_iam_policy_document.shared_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.shared]
}

# ---------------------------------------------------------------------------
# roleC — full access to one bucket, assumable ONLY by roleB in Account A
# ---------------------------------------------------------------------------

# The principal is roleB's exact role ARN, not Account A's root. Nothing
# else in Account A — not roleA, not an admin user, not a future role — can
# assume roleC, regardless of what their own identity policies say.
data "aws_iam_policy_document" "roleC_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.roleB.arn]
    }
  }
}

resource "aws_iam_role" "roleC" {
  provider             = aws.account_b
  name                 = "roleC"
  description          = "Full access to ${var.shared_bucket_name}; assumable only by roleB in ${var.account_a_id}"
  assume_role_policy   = data.aws_iam_policy_document.roleC_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "roleC_permissions" {
  statement {
    sid     = "FullAccessToSharedBucketOnly"
    effect  = "Allow"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.shared.arn,        # bucket-level: ListBucket, GetBucket*, PutBucket*...
      "${aws_s3_bucket.shared.arn}/*", # object-level: GetObject, PutObject, DeleteObject...
    ]
  }
}

resource "aws_iam_role_policy" "roleC" {
  provider = aws.account_b
  name     = "roleC-s3-access"
  role     = aws_iam_role.roleC.id
  policy   = data.aws_iam_policy_document.roleC_permissions.json
}
