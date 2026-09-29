# DevOps Assignment — Terraform / AWS

Written answers and design reasoning are in **[NOTES.md](NOTES.md)**.

```
.
├── NOTES.md                     # answers to all questions (Tasks 1–5)
├── .github/workflows/           # CI: fmt, validate, tflint, checkov on every PR
├── .pre-commit-config.yaml      # same checks locally, before each commit
├── .tflint.hcl / .checkov.yaml  # lint + security-scan config
├── task1-ec2/                   # Task 1 root config (+ Task 2 backend.tf)
│   ├── modules/ec2-fleet/       #   reusable module: N instances from one map variable
│   ├── terraform.tfvars         #   the 5 instance specs
│   ├── backend.tf               #   S3 backend + DynamoDB locking (Task 2)
│   └── backend.hcl.example
├── task2-state-backend/         # Task 2 bootstrap: state bucket + lock table
├── task3-iam/                   # Task 3: Account A + Account B IAM (two aliased providers)
├── task4-ci-policy/             # Task 4: least-privilege ci policy (JSON template)
└── task5-bugfix/                # Task 5: original snippet + fixed.tf
```

## Run order

Prerequisites: Terraform ≥ 1.5, and AWS CLI profiles for the target accounts.

```bash
# 1. Bootstrap remote state (local state, run once)
cd task2-state-backend
terraform init && terraform apply
terraform output -raw backend_hcl > ../task1-ec2/backend.hcl

# 2. EC2 fleet on the S3 backend (key pairs in terraform.tfvars must exist)
cd ../task1-ec2
terraform init -backend-config=backend.hcl
terraform apply
terraform output instance_ids
terraform output private_ips

# 3. IAM across both accounts (also attaches the Task 4 ci policy)
cd ../task3-iam
cp terraform.tfvars.example terraform.tfvars   # set profiles + pgp_key
terraform init && terraform apply
```

Task 5 is a standalone fix. `cd task5-bugfix && terraform init && terraform validate`
checks it. Task 3 already contains the same roleC, built correctly, so don't
apply both to the same account.

## Best practices applied

| Area | What's in place |
|------|-----------------|
| **Versions** | Root configs pin Terraform `>= 1.5, < 2.0` and the AWS provider `>= 5.0, < 7.0`. The reusable module sets minimums only. Commit `.terraform.lock.hcl`. |
| **State** | Remote S3 state: encrypted, versioned (90-day history), TLS only, public access blocked. DynamoDB locking with deletion protection and point-in-time recovery. |
| **Secrets** | No access keys in Terraform. Console passwords are PGP-encrypted. State, `backend.hcl` and secret tfvars are git-ignored. Pre-commit blocks committed private keys and AWS credentials. |
| **Tagging** | Provider `default_tags` (Project, ManagedBy, Stack) plus the required Name/Environment/Owner tags. |
| **EC2** | Encrypted root volumes (optional CMK), IMDSv2 only with hop limit 1, EBS-optimized, detailed monitoring, termination protection on stateful hosts, no surprise AMI replacements. |
| **IAM** | Least privilege. Permissions only through groups or roles. MFA enforced for humans. Cross-account trust by exact role ARN. Strict password policy. `allowed_account_ids` stops applies to the wrong account. |
| **Code quality** | Every variable and output is typed and documented, with input validation. `for_each` over maps, not `count`. Lint, format and security checks run in pre-commit and CI. |

## Local checks

```bash
pip install pre-commit && pre-commit install
pre-commit run --all-files
```

## Protected instance

`db-primary` has `prevent_destroy`, EC2 termination protection, and a root
volume that survives termination. To decommission it on purpose: remove the
`lifecycle` guard in a reviewed change, set `disable_api_termination = false`,
and apply before destroying.
