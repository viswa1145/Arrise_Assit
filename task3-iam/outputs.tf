output "roleA_arn" {
  description = "ARN of roleA (admin except IAM)."
  value       = aws_iam_role.roleA.arn
}

output "roleB_arn" {
  description = "ARN of roleB (jump role into Account B)."
  value       = aws_iam_role.roleB.arn
}

output "roleC_arn" {
  description = "ARN of roleC in Account B."
  value       = aws_iam_role.roleC.arn
}

output "ci_policy_arn" {
  description = "ARN of the least-privilege ci deploy policy."
  value       = aws_iam_policy.ci_deploy.arn
}

output "console_initial_passwords_encrypted" {
  description = "PGP-encrypted initial passwords; decrypt with the matching private key."
  value       = { for u, lp in aws_iam_user_login_profile.console : u => lp.encrypted_password }
}
