# NOTES

Answers and design decisions for the DevOps assignment. Code lives in:

| Task | Path |
|------|------|
| 1 — Multi-instance EC2 | [`task1-ec2/`](task1-ec2/) (module in `modules/ec2-fleet/`) |
| 2 — Remote state & locking | [`task2-state-backend/`](task2-state-backend/) + [`task1-ec2/backend.tf`](task1-ec2/backend.tf) |
| 3 — Multi-account IAM | [`task3-iam/`](task3-iam/) |
| 4 — Least-privilege CI policy | [`task4-ci-policy/ci-policy.json.tftpl`](task4-ci-policy/ci-policy.json.tftpl) (attached in `task3-iam/account-a.tf`) |
| 5 — Find and fix the bug | [`task5-bugfix/fixed.tf`](task5-bugfix/fixed.tf) |

---

## Task 1 — Multi-Instance EC2 Provisioning

### How it's driven from one variable

All five instances come from the single `instances` map variable
([`terraform.tfvars`](task1-ec2/terraform.tfvars)). Each entry carries its own
`instance_type`, `volume_type`, `volume_size`, `iops`, and `key_name`. The module
works with any number of instances: add a map entry to add an instance, and
remove one to remove it. Validation only rejects inputs AWS would refuse
anyway: an unsupported root volume type, or io1/io2 without `iops`. The
assignment's specific requirements (5 instances, at least one io1/io2, a
different type, size and key pair for each, one protected instance) are met
by the values in `terraform.tfvars`. The module doesn't enforce them, so it
stays reusable.

| Name | Type | Root volume | Size | Key pair |
|------|------|-------------|------|----------|
| bastion | t3.micro | standard | 20 GiB | kp-bastion |
| web | t3.small | gp2 | 30 GiB | kp-web |
| app | m5.large | gp3 (4000 IOPS / 250 MiB/s) | 40 GiB | kp-app |
| analytics | c5.large | **io1** (3000 IOPS) | 60 GiB | kp-analytics |
| db-primary | r5.large | **io2** (5000 IOPS) | 100 GiB | kp-db |

Every instance (and its root volume) is tagged `Name`, `Environment`, `Owner`.
Outputs: `instance_ids` (name → ID) and `private_ips` (name → private IP).

### Which instance has `prevent_destroy`, and why

**`db-primary`.** It's the only stateful instance in the fleet: it has the
database on a provisioned-IOPS io2 volume. The others (bastion, web, app,
analytics) are stateless or can be rebuilt. If any of them is destroyed by
accident, `terraform apply` brings it back in minutes. If `db-primary` is
destroyed, the data is gone, which is why it is the one to protect.

### Why there are two resource blocks, not one

`prevent_destroy` is a static meta-argument. It can't come from a variable,
and it can't differ between `for_each` keys: putting it on a `for_each`
resource protects *every* instance in that block. To protect exactly one
instance and still drive all five from one variable, the module splits the
map by the `protected` flag into `aws_instance.this` (4 instances) and
`aws_instance.protected` (1 instance). The two blocks have identical
configuration. They are not five hardcoded blocks: both iterate over the same
input.

### Why `prevent_destroy` is not enough on its own

`prevent_destroy` only stops Terraform plans that would destroy the resource.
It does nothing against someone deleting the lifecycle block, running
`terraform state rm`, or terminating the instance in the console. So the
protected instance also gets:

- `disable_api_termination = true`: EC2 termination protection, which blocks
  console and CLI termination.
- `delete_on_termination = false` on the root volume, so the data volume
  survives even if the instance is terminated.
- `ignore_changes = [ami]`: the AMI data source always resolves to the
  *latest* AL2023 image. Without this, a new AMI release would plan a
  replacement (destroy and create), and `prevent_destroy` would fail every
  plan.

---

## Task 2 — Remote State & Locking

### What happens today with local state if two people run `apply` at once

With the default local backend, state is a `terraform.tfstate` file on each
person's laptop.

- **Each person has their own, different view of reality.** Alice applies and
  her state records 5 instances. Bob's state is empty or stale, so his `apply`
  plans to create the 5 instances again. That gives duplicates, or errors on
  unique names such as key pairs and buckets. If both touch existing resources,
  each plan is computed against a stale snapshot, so the applies can undo or
  overwrite each other's changes.
- **There is no mutual exclusion.** The local backend only takes an OS file
  lock on the state file, which protects two runs *on the same machine in the
  same directory*. Two people on two machines get no lock at all.
- **Last writer wins on the state file.** If the file is shared through git or
  a network drive, the two applies each write their own version, and one
  silently overwrites the other. Resources the losing apply created are now
  **orphaned**: they exist in AWS, but no state file tracks them. Nobody will
  destroy or update them, and they keep costing money.

### How the S3 + DynamoDB backend prevents it

1. **One source of truth.** State lives in one S3 object
   (`s3://<bucket>/task1-ec2/terraform.tfstate`). Everyone reads and writes
   the same file, so everyone plans against the same view.
2. **Locking.** Before any operation that can write state (`plan`, `apply`,
   `destroy`, `import`, …), Terraform does a *conditional* `PutItem` into
   the DynamoDB table with `LockID = <bucket>/<key>`. DynamoDB guarantees only
   one conditional write can succeed. The second person gets
   `Error acquiring the state lock`, along with who holds the lock, when it
   was taken and for which operation. Their run waits (with `-lock-timeout`)
   or exits, and nothing is changed. The lock is released when the first run
   finishes.
3. **Consistency check.** The backend also stores an MD5 digest of the state
   in DynamoDB, so a client that reads a stale S3 object detects the mismatch
   instead of acting on old data.
4. **Recovery and protection.** Bucket versioning allows rolling back a bad or
   corrupted state. SSE-KMS, the public-access block and a TLS-only bucket
   policy matter because state contains secrets in plaintext. Both the bucket
   and the lock table have `prevent_destroy`.

Note: Terraform ≥ 1.10 can lock natively in S3 (`use_lockfile = true`), and
DynamoDB locking is now deprecated upstream. I used DynamoDB because the task
asks for it. Moving to native locking is a one-line backend change plus
`terraform init -reconfigure`.

The bootstrap stack itself keeps local state. The bucket has to exist before
anything can store state in it. The stack is applied once and can be migrated
into the bucket afterwards with `terraform init -migrate-state`.

---

## Task 3 — Multi-Account IAM & Cross-Account Access

### What was built

**Account A (000000000000)**

- **group1** (`engine`, `ci`): programmatic only. These users have no
  `aws_iam_user_login_profile`, so they have no console password and cannot
  sign in. The group policy lets each user rotate only their own access keys,
  and explicitly denies creating or changing a login profile. `ci` is also in
  a **`ci-deployers`** group that carries the Task 4 policy. Permissions are
  granted only through groups, never attached to users directly, so access
  reviews only need to read group policies.
- **group2** (`alice`, `bob`): console + CLI. Login profiles are created with
  a PGP-encrypted initial password and forced reset on first login. The group
  policy allows self-managing password, MFA and access keys, and allows
  assuming roleA/roleB. **Everything except MFA setup is denied until MFA is
  present.** I read "full console + CLI access" as *how* they access AWS.
  Their actual permissions come from assuming roleA, not from the user
  itself.
- **roleA**: `Allow NotAction iam:*` + an explicit `Deny iam:*`, so admin on
  everything except IAM. The explicit deny keeps IAM blocked even if someone
  later attaches AdministratorAccess to the role. It is assumable by Account A
  principals that are allowed by their own policy (group2), with MFA.
  - Caveat: with no IAM at all, roleA can't `iam:PassRole` (for example, to
    launch EC2 with an instance profile or create a Lambda) or
    `iam:CreateServiceLinkedRole`. This follows the requirement strictly. In
    practice I'd allow `PassRole` scoped to a role path, plus
    `CreateServiceLinkedRole`.
- **roleB**: the only permission is `sts:AssumeRole` on roleC's ARN. Its trust
  policy lists the group2 users **by ARN, not the account root**. roleA can do
  every non-IAM action, and `sts:AssumeRole` is non-IAM, so a root-trusting
  roleB would let roleA chain `roleA → roleB → roleC` into Account B.

**Account B (111111111111)**

- **roleC**: `s3:*` on the bucket ARN and `bucket/*` only. Its trust policy's
  principal is **roleB's exact ARN**.

Cross-account access needs *both* sides to agree: roleB's identity policy must
allow `sts:AssumeRole` on roleC, **and** roleC's trust policy must name roleB.
Both accounts are managed from one configuration with two aliased providers,
so these are real resource references, and `allowed_account_ids` stops a
misconfigured profile from applying to the wrong account.

### Q: Would you actually give `engine` and `ci` IAM users with access keys in production?

**No.** Long-lived access keys are the most common way AWS accounts get
compromised. They don't expire. They leak into git history, CI logs, `.env`
files and laptop backups. Rotation is manual and usually skipped. And
CloudTrail can only attribute activity to the key, not to the workload that
used it. I'd use short-lived, automatically rotated credentials from roles
instead:

- **`ci`** → **OIDC federation**. If the pipeline is GitHub Actions, GitLab,
  CircleCI or similar, register the provider as an IAM OIDC identity provider
  and create a `ci-deploy` role whose trust policy is conditioned on the token
  claims. For example:
  `token.actions.githubusercontent.com:sub = repo:arrise/app:ref:refs/heads/main`,
  so only the main branch of that repo can deploy. The pipeline stores no
  secret at all, and each job gets credentials valid for about an hour. If CI
  runs inside AWS (CodeBuild, self-hosted runners on EC2/EKS), it uses the
  build role or instance role directly.
- **`engine`** (a workload) → **the compute's role**: EC2 instance profile,
  ECS task role, Lambda execution role, or EKS Pod Identity/IRSA. Credentials
  come from the metadata endpoint and rotate automatically.
- **Workloads outside AWS with no OIDC option** (on-prem) → **IAM Roles
  Anywhere** with X.509 certificates from our PKI.
- **Humans (group2)** → **IAM Identity Center (SSO)** with permission sets,
  backed by the corporate IdP, instead of IAM users. Offboarding happens in
  one place, and MFA is enforced by the IdP.

If keys were truly unavoidable: one key per user, rotated at 90 days or less,
stored in a secrets manager, restricted with `aws:SourceIp`/`aws:SourceVpc`
conditions, and monitored with IAM Access Analyzer and credential reports for
unused keys.

### Q: In roleC's trust policy, why does it matter whether you trust Account A's root vs. roleB's ARN?

Trusting `arn:aws:iam::000000000000:root` does **not** mean "only the root
user". It means *"I delegate the decision to Account A"*. Any principal in
Account A whose own identity policy allows `sts:AssumeRole` on roleC can then
assume it.

- **Account B loses control of who reaches its data.** Any Account A admin can
  grant access to roleC by editing policies in Account A. Account B never sees
  that change, and nothing in B's configuration records it.
- **It would violate this requirement concretely.** roleA has `NotAction iam:*`,
  which includes `sts:AssumeRole`. With a root trust, roleA could assume
  roleC directly. So could any admin user, and any role created in A in the
  future.
- **Blast radius.** A compromise of *any* sufficiently privileged principal in
  A becomes a compromise of B's bucket.

Trusting `arn:aws:iam::000000000000:role/roleB` means only sessions of that
one role can assume roleC, whatever any other Account A policy says. The only
way into roleC is through roleB, so roleB's trust policy becomes the single,
auditable gate.

A useful side effect: when you save a trust policy with a specific role ARN,
IAM stores it internally as the role's unique ID (`AROA…`). If roleB is
deleted and recreated with the same name, the new role is *not* trusted. The
policy shows the stale ID until someone re-saves it. This stops an attacker
from recreating a deleted role name to inherit its trust. Using the account
root with an `aws:PrincipalArn` condition would be name-based and would lose
that property.

---

## Task 4 — Least-Privilege Policy for `ci`

Policy: [`task4-ci-policy/ci-policy.json.tftpl`](task4-ci-policy/ci-policy.json.tftpl).
It is attached to a dedicated `ci-deployers` group whose only member is
`ci`. It isn't on group1, because `engine` doesn't deploy, and it isn't
attached to the user directly, which is a common audit finding.

### What's granted

| Need | Actions | Resource |
|------|---------|----------|
| ECR login | `ecr:GetAuthorizationToken` | `*` (the API has no resource-level support) |
| Push image | `BatchCheckLayerAvailability`, `InitiateLayerUpload`, `UploadLayerPart`, `CompleteLayerUpload`, `PutImage`, `BatchGetImage` | the one repository ARN |
| Register task def | `ecs:RegisterTaskDefinition`, `ecs:DescribeTaskDefinition` | `*` (no resource-level support) |
| Deploy | `ecs:UpdateService`, `ecs:DescribeServices` | the one service ARN (`service/<cluster>/<service>`) |
| Let the task def use its roles | `iam:PassRole` | only the service's execution role and task role, only when `iam:PassedToService = ecs-tasks.amazonaws.com` |
| Read artifacts | `s3:ListBucket` on the bucket, `s3:GetObject` on `bucket/*` | the one bucket |

`BatchGetImage` is read-only on the same repository. Docker/buildx checks for
existing manifests during a push, and AWS lists it in the minimum push
permissions. `DescribeServices` is what `aws ecs wait services-stable` uses to
confirm the rollout.

### What I deliberately left out, and why

- **`iam:PassRole` on `*`.** This is the most important omission. The
  pipeline registers task definitions, and a task definition names an IAM
  role. With unrestricted `PassRole`, `ci` could register a task definition
  that uses an admin role, deploy it, and escalate to admin. Limiting
  `PassRole` to the service's two roles and to the `ecs-tasks` service closes
  that path. It is also why the unscoped `RegisterTaskDefinition` is
  acceptable: a new task definition is harmless unless it can be run with a
  role, and `PassRole` controls which roles it can use.
- **ECR admin and destructive actions**: `CreateRepository`,
  `DeleteRepository`, `BatchDeleteImage`, `SetRepositoryPolicy`,
  `PutLifecyclePolicy`, `PutImageTagMutability`, and access to any other
  repository. The pipeline pushes. It doesn't manage repositories or delete
  images (a compromised pipeline could otherwise wipe rollback images or
  change who can pull).
- **ECS actions beyond updating one service**: `CreateService`,
  `DeleteService`, `RunTask`/`StartTask` (run arbitrary one-off containers
  with the passable roles), `ExecuteCommand` (shell into running prod
  containers), `DeregisterTaskDefinition`, `UpdateCluster`, `ecs:TagResource`,
  and `UpdateService` on any other service or cluster.
- **Any S3 write**: `PutObject`, `DeleteObject`, `PutObjectAcl`, bucket policy
  changes. The requirement is read-only. A pipeline that can overwrite build
  artifacts can poison later builds. `s3:ListAllMyBuckets` and
  `GetObjectVersion` were also left out because nothing needs them.
- **`kms:Decrypt`.** Not needed while the artifact bucket uses SSE-S3. If it
  used SSE-KMS, I'd add `kms:Decrypt` on that one key with a
  `kms:ViaService = s3.<region>.amazonaws.com` condition.
- **CloudWatch Logs, ELB, Auto Scaling, Secrets Manager, and similar.** The
  ECS service already owns those at runtime through its own roles. Deploying
  doesn't require `ci` to touch them.
- **No managed policies** (`AmazonEC2ContainerRegistryPowerUser`,
  `AmazonECS_FullAccess`, …). They apply to every repository and service in
  the account and include the destructive actions above.

Further hardening, if the CI runner has fixed egress IPs or runs in a known
VPC: add an `aws:SourceIp` / `aws:SourceVpc` condition. Better still, replace
the user with an OIDC-federated role as described in Task 3.

---

## Task 5 — Find and Fix the Bug

Fixed file: [`task5-bugfix/fixed.tf`](task5-bugfix/fixed.tf). The original is
kept in [`original-broken.tf.txt`](task5-bugfix/original-broken.tf.txt).

### Bug 1: trust policy, wrong principal type (`user/roleB` → `role/roleB`)

```hcl
identifiers = ["arn:aws:iam::000000000000:user/roleB"]   # broken
identifiers = ["arn:aws:iam::000000000000:role/roleB"]   # fixed
```

An IAM ARN includes the *type* of the principal, not just its name. roleB is a
**role**, so its ARN is `...:role/roleB`. `...:user/roleB` refers to an IAM
*user* called "roleB", which is a different identity, and here it doesn't
exist.

IAM validates principals when a trust policy is saved. When Terraform calls
`CreateRole` for roleC, AWS rejects it with
`MalformedPolicyDocument: Invalid principal in policy`, so the `apply` fails
and roleC is never created. Even if a user named `roleB` did exist, the
policy would save but trust that user and not the role. When roleB tried
`sts:AssumeRole`, its session ARN
(`arn:aws:sts::000000000000:assumed-role/roleB/...`) would not match the
principal, and it would get `AccessDenied`.

### Bug 2: permissions policy, `s3:*` on `Resource = "*"`

```hcl
Resource = "*"                                        # broken
Resource = [
  "arn:aws:s3:::<bucket>",                            # fixed
  "arn:aws:s3:::<bucket>/*",
]
```

This bug doesn't make the apply fail. It is a security bug, and it breaks the
requirement that roleC has access to **a single named bucket**. `"*"` gives
roleC full control (read, write, delete, change bucket policy, delete bucket)
over **every bucket in Account B**. It also covers any bucket in another
account whose bucket policy trusts Account B. Anyone who can reach roleB gets
all of that.

The fix needs **both** ARNs, because S3 actions apply to two different
resource types:

- `arn:aws:s3:::bucket` for bucket-level actions (`ListBucket`,
  `GetBucketLocation`, `PutBucketPolicy`, …)
- `arn:aws:s3:::bucket/*` for object-level actions (`GetObject`, `PutObject`,
  `DeleteObject`, …)

With only the first ARN, you can list the bucket but not read objects. With
only the second, you can read objects but `aws s3 ls` returns AccessDenied.

### Also needed for this to work end to end (not a bug in the snippet)

The snippet only covers Account B's side. For cross-account `AssumeRole`,
**roleB's identity policy in Account A must also allow `sts:AssumeRole` on
roleC's ARN**. Both the trust policy and the caller's permissions have to
allow the call. That half is in
[`task3-iam/account-a.tf`](task3-iam/account-a.tf) (`aws_iam_role_policy.roleB`).
