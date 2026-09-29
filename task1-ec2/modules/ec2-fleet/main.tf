data "aws_ami" "al2023" {
  count       = var.ami_id == null ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  ami_id = coalesce(var.ami_id, try(data.aws_ami.al2023[0].id, null))

  # prevent_destroy is a static meta-argument: it cannot be driven by a
  # variable or differ between for_each keys. To protect exactly one instance
  # while still driving everything from var.instances, the map is split into
  # two for_each sets that share identical configuration.
  unprotected = { for name, spec in var.instances : name => spec if !spec.protected }
  protected   = { for name, spec in var.instances : name => spec if spec.protected }

  # coalesce() errors when every argument is null, so fall back to null (= default VPC).
  subnet_ids = { for name, spec in var.instances : name => try(coalesce(spec.subnet_id, var.default_subnet_id), null) }

  tags = {
    for name in keys(var.instances) : name => merge(var.extra_tags, {
      Name        = name
      Environment = var.environment
      Owner       = var.owner
    })
  }
}

resource "aws_instance" "this" {
  for_each = local.unprotected

  ami                    = local.ami_id
  instance_type          = each.value.instance_type
  key_name               = each.value.key_name
  subnet_id              = local.subnet_ids[each.key]
  vpc_security_group_ids = length(var.vpc_security_group_ids) > 0 ? var.vpc_security_group_ids : null
  iam_instance_profile   = var.iam_instance_profile
  monitoring             = var.detailed_monitoring
  ebs_optimized          = true

  root_block_device {
    volume_type           = each.value.volume_type
    volume_size           = each.value.volume_size
    iops                  = contains(["io1", "io2", "gp3"], each.value.volume_type) ? each.value.iops : null
    throughput            = each.value.volume_type == "gp3" ? each.value.throughput : null
    encrypted             = true
    kms_key_id            = var.ebs_kms_key_id
    delete_on_termination = true
    tags                  = local.tags[each.key]
  }

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1 # containers on the host can't reach IMDS
  }

  tags = local.tags[each.key]

  lifecycle {
    # The default AMI resolves to the *latest* AL2023 release; without this a
    # routine AMI publish would plan a replacement of every instance. Roll
    # AMIs deliberately (pin var.ami_id, or `terraform apply -replace=...`).
    ignore_changes = [ami]
  }
}

resource "aws_instance" "protected" {
  for_each = local.protected

  ami                    = local.ami_id
  instance_type          = each.value.instance_type
  key_name               = each.value.key_name
  subnet_id              = local.subnet_ids[each.key]
  vpc_security_group_ids = length(var.vpc_security_group_ids) > 0 ? var.vpc_security_group_ids : null
  iam_instance_profile   = var.iam_instance_profile
  monitoring             = var.detailed_monitoring
  ebs_optimized          = true

  # Second layer of protection outside Terraform (console / CLI terminate).
  disable_api_termination = true

  root_block_device {
    volume_type = each.value.volume_type
    volume_size = each.value.volume_size
    iops        = contains(["io1", "io2", "gp3"], each.value.volume_type) ? each.value.iops : null
    throughput  = each.value.volume_type == "gp3" ? each.value.throughput : null
    encrypted   = true
    kms_key_id  = var.ebs_kms_key_id
    # Keep the data volume if the instance is ever terminated out-of-band.
    delete_on_termination = false
    tags                  = local.tags[each.key]
  }

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  tags = local.tags[each.key]

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [ami] # see aws_instance.this
  }
}
