##############################################################################
# Account A (000000000000)
##############################################################################

locals {
  account_a_root = "arn:aws:iam::${var.account_a_id}:root"
}

# ---------------------------------------------------------------------------
# Account password policy (applies to group2's console passwords)
# ---------------------------------------------------------------------------

resource "aws_iam_account_password_policy" "this" {
  provider                       = aws.account_a
  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  password_reuse_prevention      = 24
  max_password_age               = 90
}

# ---------------------------------------------------------------------------
# Users
# ---------------------------------------------------------------------------

# Programmatic-only: no aws_iam_user_login_profile => no console password,
# so these identities physically cannot sign in to the console. Access keys
# are intentionally NOT created here (a secret key in state is a liability);
# see NOTES.md for why these should not be long-lived IAM users at all.
resource "aws_iam_user" "programmatic" {
  provider = aws.account_a
  for_each = toset(["engine", "ci"])

  name          = each.key
  force_destroy = true
  tags          = { AccessType = "programmatic-only" }
}

resource "aws_iam_user" "console" {
  provider = aws.account_a
  for_each = toset(var.console_users)

  name          = each.key
  force_destroy = true
  tags          = { AccessType = "console-and-cli" }
}

# Console password, encrypted with the admin's PGP key, must be changed on first login.
resource "aws_iam_user_login_profile" "console" {
  provider = aws.account_a
  for_each = aws_iam_user.console

  user                    = each.value.name
  pgp_key                 = var.pgp_key
  password_reset_required = true

  lifecycle {
    ignore_changes = [password_reset_required, password_length, pgp_key]
  }
}

# ---------------------------------------------------------------------------
# group1 — CLI / programmatic only
# ---------------------------------------------------------------------------

resource "aws_iam_group" "group1" {
  provider = aws.account_a
  name     = "group1"
}

# Baseline for machine users: rotate their own access keys, nothing else.
# Workload permissions are attached per user (e.g. ci -> Task 4 policy).
data "aws_iam_policy_document" "group1" {
  statement {
    sid = "RotateOwnAccessKeys"
    actions = [
      "iam:CreateAccessKey",
      "iam:DeleteAccessKey",
      "iam:ListAccessKeys",
      "iam:UpdateAccessKey",
      "iam:GetAccessKeyLastUsed",
    ]
    resources = ["arn:aws:iam::${var.account_a_id}:user/$${aws:username}"]
  }

  # Belt-and-braces: even if someone later adds a login profile to one of
  # these users, they cannot create or change a console password themselves.
  statement {
    sid    = "DenyConsolePasswordManagement"
    effect = "Deny"
    actions = [
      "iam:CreateLoginProfile",
      "iam:UpdateLoginProfile",
      "iam:ChangePassword",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_group_policy" "group1" {
  provider = aws.account_a
  name     = "group1-programmatic-baseline"
  group    = aws_iam_group.group1.name
  policy   = data.aws_iam_policy_document.group1.json
}

# ---------------------------------------------------------------------------
# group2 — full console + CLI
# ---------------------------------------------------------------------------

resource "aws_iam_group" "group2" {
  provider = aws.account_a
  name     = "group2"
}

# Humans get: self-service credential management (password, MFA, access
# keys for CLI) + the ability to assume roleA / roleB — all gated on MFA.
# Real permissions come from the roles, not from the user.
data "aws_iam_policy_document" "group2" {
  statement {
    sid = "ManageOwnCredentials"
    actions = [
      "iam:GetUser",
      "iam:ChangePassword",
      "iam:GetLoginProfile",
      "iam:CreateAccessKey",
      "iam:DeleteAccessKey",
      "iam:ListAccessKeys",
      "iam:UpdateAccessKey",
      "iam:GetAccessKeyLastUsed",
      "iam:ListMFADevices",
      "iam:EnableMFADevice",
      "iam:ResyncMFADevice",
      "iam:DeactivateMFADevice",
    ]
    resources = ["arn:aws:iam::${var.account_a_id}:user/$${aws:username}"]
  }

  statement {
    sid       = "ManageOwnVirtualMFA"
    actions   = ["iam:CreateVirtualMFADevice", "iam:DeleteVirtualMFADevice"]
    resources = ["arn:aws:iam::${var.account_a_id}:mfa/*"]
  }

  statement {
    sid       = "ListForConsole"
    actions   = ["iam:ListVirtualMFADevices", "iam:GetAccountPasswordPolicy"]
    resources = ["*"]
  }

  # No MFA condition here on purpose: `aws sts assume-role --serial-number`
  # is signed with long-term keys, so aws:MultiFactorAuthPresent is absent in
  # this (identity) evaluation. MFA is enforced in roleA/roleB trust policies,
  # which do see the MFA code passed on the AssumeRole call.
  statement {
    sid       = "AssumeWorkRoles"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.roleA.arn, aws_iam_role.roleB.arn]
  }

  # Without MFA, the only things allowed are the calls needed to set up MFA
  # (plus AssumeRole, whose trust policies require MFA anyway — see above).
  statement {
    sid    = "DenyAllExceptMFASetupWithoutMFA"
    effect = "Deny"
    not_actions = [
      "iam:ChangePassword",
      "iam:GetUser",
      "iam:GetLoginProfile",
      "iam:ListMFADevices",
      "iam:ListVirtualMFADevices",
      "iam:CreateVirtualMFADevice",
      "iam:EnableMFADevice",
      "iam:ResyncMFADevice",
      "iam:GetAccountPasswordPolicy",
      "sts:GetSessionToken",
      "sts:AssumeRole",
    ]
    resources = ["*"]

    condition {
      test     = "BoolIfExists"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["false"]
    }
  }
}

resource "aws_iam_group_policy" "group2" {
  provider = aws.account_a
  name     = "group2-console-cli"
  group    = aws_iam_group.group2.name
  policy   = data.aws_iam_policy_document.group2.json
}

# ---------------------------------------------------------------------------
# roleA — admin on everything except IAM
# ---------------------------------------------------------------------------

# Trusting the account root delegates the decision to IAM policies inside
# Account A: only principals whose identity policy allows sts:AssumeRole on
# roleA (group2) can use it — and only with MFA.
data "aws_iam_policy_document" "roleA_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [local.account_a_root]
    }

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

resource "aws_iam_role" "roleA" {
  provider             = aws.account_a
  name                 = "roleA"
  description          = "Administrative access to all AWS services except IAM"
  assume_role_policy   = data.aws_iam_policy_document.roleA_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "roleA_permissions" {
  # roleA is required to be admin on everything except IAM, which inherently
  # means broad actions on Resource "*". This is the one intended exception.
  #checkov:skip=CKV_AWS_355:Admin-except-IAM role by design
  #checkov:skip=CKV_AWS_286:Admin-except-IAM role by design
  #checkov:skip=CKV_AWS_287:Admin-except-IAM role by design
  #checkov:skip=CKV_AWS_288:Admin-except-IAM role by design
  #checkov:skip=CKV_AWS_289:Admin-except-IAM role by design
  #checkov:skip=CKV_AWS_290:Admin-except-IAM role by design
  # Allow everything that is not IAM...
  statement {
    sid         = "AdminExceptIAM"
    effect      = "Allow"
    not_actions = ["iam:*"]
    resources   = ["*"]
  }

  # ...and explicitly deny IAM, so attaching another policy to roleA later
  # (e.g. AdministratorAccess by mistake) still can't grant IAM rights.
  statement {
    sid       = "DenyIAM"
    effect    = "Deny"
    actions   = ["iam:*"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "roleA" {
  provider = aws.account_a
  name     = "admin-except-iam"
  role     = aws_iam_role.roleA.id
  policy   = data.aws_iam_policy_document.roleA_permissions.json
}

# ---------------------------------------------------------------------------
# roleB — can only assume roleC in Account B
# ---------------------------------------------------------------------------

# Unlike roleA, roleB trusts named users rather than the account root.
# roleA has every non-IAM action — including sts:AssumeRole — so with a root
# trust here roleA could chain roleA -> roleB -> roleC into Account B. roleB
# is the gate to another account, so its trust list is explicit.
data "aws_iam_policy_document" "roleB_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [for u in aws_iam_user.console : u.arn]
    }

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

resource "aws_iam_role" "roleB" {
  provider             = aws.account_a
  name                 = "roleB"
  description          = "Jump role whose only permission is assuming roleC in Account B"
  assume_role_policy   = data.aws_iam_policy_document.roleB_trust.json
  max_session_duration = 3600
}

# Kept as a separate resource (not inline on aws_iam_role.roleB) to avoid a
# dependency cycle: roleC's trust policy needs roleB's ARN, and this policy
# needs roleC's ARN.
data "aws_iam_policy_document" "roleB_permissions" {
  statement {
    sid       = "AssumeRoleCOnly"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.roleC.arn]
  }
}

resource "aws_iam_role_policy" "roleB" {
  provider = aws.account_a
  name     = "assume-roleC-only"
  role     = aws_iam_role.roleB.id
  policy   = data.aws_iam_policy_document.roleB_permissions.json
}

# ---------------------------------------------------------------------------
# Task 4 — least-privilege policy for the ci user
# ---------------------------------------------------------------------------

resource "aws_iam_policy" "ci_deploy" {
  provider    = aws.account_a
  name        = "ci-deploy-least-privilege"
  description = "Push to one ECR repo, deploy one ECS service, read one artifact bucket"

  policy = templatefile("${path.module}/../task4-ci-policy/ci-policy.json.tftpl", {
    region          = var.region
    account_id      = var.account_a_id
    ecr_repository  = var.ci_ecr_repository
    ecs_cluster     = var.ci_ecs_cluster
    ecs_service     = var.ci_ecs_service
    artifact_bucket = var.ci_artifact_bucket
    pass_role_arns  = [for r in var.ci_passable_role_names : "arn:aws:iam::${var.account_a_id}:role/${r}"]
  })
}

# Permissions are granted through groups, never attached to users directly,
# so access reviews only have to look at group policies.
resource "aws_iam_group" "ci_deployers" {
  provider = aws.account_a
  name     = "ci-deployers"
}

resource "aws_iam_group_policy_attachment" "ci_deploy" {
  provider   = aws.account_a
  group      = aws_iam_group.ci_deployers.name
  policy_arn = aws_iam_policy.ci_deploy.arn
}

# ---------------------------------------------------------------------------
# Group memberships
# ---------------------------------------------------------------------------

# aws_iam_user_group_membership is non-exclusive per user, so a user can be
# in several groups without two resources fighting over the member list
# (which aws_iam_group_membership does, as it owns a group's full list).
locals {
  user_groups = merge(
    { engine = [aws_iam_group.group1.name] },
    { ci = [aws_iam_group.group1.name, aws_iam_group.ci_deployers.name] },
    { for u in var.console_users : u => [aws_iam_group.group2.name] },
  )
}

resource "aws_iam_user_group_membership" "this" {
  provider = aws.account_a
  for_each = local.user_groups

  user   = merge(aws_iam_user.programmatic, aws_iam_user.console)[each.key].name
  groups = each.value
}
