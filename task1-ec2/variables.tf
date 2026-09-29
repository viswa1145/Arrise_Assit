variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name, applied as the Project default tag."
  type        = string
  default     = "arrise"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)."
  type        = string
}

variable "owner" {
  description = "Owning team, applied as the Owner tag."
  type        = string
}

variable "ami_id" {
  description = "Optional AMI override. Null = latest Amazon Linux 2023. Pin this in prod."
  type        = string
  default     = null
}

variable "default_subnet_id" {
  description = "Subnet for instances that don't set their own subnet_id. Null = default VPC."
  type        = string
  default     = null
}

variable "vpc_security_group_ids" {
  description = "Security groups attached to every instance."
  type        = list(string)
  default     = []
}

variable "iam_instance_profile" {
  description = "Instance profile attached to every instance. Null = none."
  type        = string
  default     = null
}

variable "ebs_kms_key_id" {
  description = "Customer-managed KMS key ARN for root volumes. Null = aws/ebs default key."
  type        = string
  default     = null
}

# Same schema as the module input, so type errors are reported here at the
# root rather than as a conversion error inside the module.
variable "instances" {
  description = "Instance name => spec. See modules/ec2-fleet/README.md."
  type = map(object({
    instance_type = string
    volume_type   = string
    volume_size   = number
    iops          = optional(number)
    throughput    = optional(number)
    key_name      = string
    subnet_id     = optional(string)
    protected     = optional(bool, false)
  }))
}
