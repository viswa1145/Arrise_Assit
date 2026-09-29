module "ec2_fleet" {
  source = "./modules/ec2-fleet"

  instances              = var.instances
  ami_id                 = var.ami_id
  default_subnet_id      = var.default_subnet_id
  vpc_security_group_ids = var.vpc_security_group_ids
  iam_instance_profile   = var.iam_instance_profile
  ebs_kms_key_id         = var.ebs_kms_key_id
  environment            = var.environment
  owner                  = var.owner
}
