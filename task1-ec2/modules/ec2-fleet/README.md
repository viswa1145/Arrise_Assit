# ec2-fleet

Provisions any number of EC2 instances from a single map variable. Each
instance can have its own instance type, root volume type/size/IOPS and key
pair. Instances marked `protected = true` get `prevent_destroy`, EC2
termination protection, and a root volume that survives termination.

Secure by default: root volumes are always encrypted, only IMDSv2 is allowed
with a hop limit of 1, instances are EBS-optimized, and detailed monitoring is
on.

## Usage

```hcl
module "ec2_fleet" {
  source = "./modules/ec2-fleet"

  environment = "prod"
  owner       = "platform-team"

  instances = {
    web = {
      instance_type = "t3.small"
      volume_type   = "gp3"
      volume_size   = 30
      key_name      = "kp-web"
    }
    db = {
      instance_type = "r5.large"
      volume_type   = "io2"
      volume_size   = 100
      iops          = 5000
      key_name      = "kp-db"
      protected     = true
    }
  }
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `instances` | `map(object)` | required | Instance name → spec (fields below). |
| `environment` | `string` | required | `dev`, `staging` or `prod`. Used for the Environment tag. |
| `owner` | `string` | required | Owner tag. |
| `ami_id` | `string` | `null` | AMI to use. Null = latest Amazon Linux 2023. Pin it for prod. |
| `default_subnet_id` | `string` | `null` | Subnet for instances that don't set their own. |
| `vpc_security_group_ids` | `list(string)` | `[]` | Security groups for every instance. |
| `iam_instance_profile` | `string` | `null` | Instance profile for every instance. |
| `detailed_monitoring` | `bool` | `true` | 1-minute CloudWatch metrics. |
| `ebs_kms_key_id` | `string` | `null` | CMK for root volumes. Null = `aws/ebs`. |
| `extra_tags` | `map(string)` | `{}` | Extra tags on instances and volumes. |

### `instances` fields

| Field | Required | Notes |
|-------|----------|-------|
| `instance_type` | yes | |
| `volume_type` | yes | `gp2`, `gp3`, `io1`, `io2`, `standard` |
| `volume_size` | yes | GiB |
| `iops` | io1/io2 | Optional for gp3 |
| `throughput` | no | gp3 only, MiB/s |
| `key_name` | yes | An existing key pair |
| `subnet_id` | no | Overrides `default_subnet_id` |
| `protected` | no | Default `false` |

## Outputs

| Name | Description |
|------|-------------|
| `instance_ids` | Instance name → instance ID |
| `private_ips` | Instance name → private IP |

## Notes

- **Changing `protected`** moves an instance between two resource blocks,
  which Terraform plans as destroy and create. Add a `moved` block, and to
  unprotect, remove termination protection first.
- **AMI changes are ignored** after creation (`ignore_changes = [ami]`), so a
  new AL2023 release doesn't replace the fleet. Roll AMIs deliberately with
  `terraform apply -replace='module.ec2_fleet.aws_instance.this["web"]'`.
