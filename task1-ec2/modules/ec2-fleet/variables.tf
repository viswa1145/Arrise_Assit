variable "instances" {
  description = <<-EOT
    Map of instance name => instance spec. Every instance in the fleet is
    driven from this single variable.

    Any number of instances is supported. protected = true gives an instance
    lifecycle.prevent_destroy and EC2 API termination protection; any number
    of instances (including none) may set it.
  EOT

  type = map(object({
    instance_type = string
    volume_type   = string           # gp2 | gp3 | io1 | io2 | standard
    volume_size   = number           # GiB
    iops          = optional(number) # required for io1/io2, optional for gp3
    throughput    = optional(number) # gp3 only (MiB/s)
    key_name      = string           # name of an existing EC2 key pair
    subnet_id     = optional(string) # overrides var.default_subnet_id
    protected     = optional(bool, false)
  }))

  validation {
    condition = alltrue([
      for i in values(var.instances) : contains(["gp2", "gp3", "io1", "io2", "standard"], i.volume_type)
    ])
    error_message = "volume_type must be one of gp2, gp3, io1, io2, standard (st1/sc1 cannot be root volumes)."
  }

  validation {
    condition = alltrue([
      for i in values(var.instances) : !contains(["io1", "io2"], i.volume_type) || i.iops != null
    ])
    error_message = "iops must be set for io1/io2 volumes."
  }
}

variable "ami_id" {
  description = "AMI to launch. Defaults to the latest Amazon Linux 2023 x86_64 AMI when null."
  type        = string
  default     = null
}

variable "default_subnet_id" {
  description = "Subnet used for instances that don't set subnet_id. Null = default VPC subnet."
  type        = string
  default     = null
}

variable "vpc_security_group_ids" {
  description = "Security groups attached to every instance."
  type        = list(string)
  default     = []
}

variable "iam_instance_profile" {
  description = "Instance profile attached to every instance (use roles, not baked-in keys). Null = none."
  type        = string
  default     = null
}

variable "detailed_monitoring" {
  description = "Enable 1-minute CloudWatch detailed monitoring."
  type        = bool
  default     = true
}

variable "ebs_kms_key_id" {
  description = "Customer-managed KMS key ARN for root volumes. Null = the account's default aws/ebs key."
  type        = string
  default     = null
}

variable "environment" {
  description = "Value for the Environment tag."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of dev, staging, prod."
  }
}

variable "owner" {
  description = "Value for the Owner tag (team or on-call alias)."
  type        = string

  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "owner must not be empty."
  }
}

variable "extra_tags" {
  description = "Additional tags merged onto every instance."
  type        = map(string)
  default     = {}
}
