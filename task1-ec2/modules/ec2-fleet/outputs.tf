locals {
  all_instances = merge(aws_instance.this, aws_instance.protected)
}

output "instance_ids" {
  description = "Map of instance name => instance ID."
  value       = { for name, inst in local.all_instances : name => inst.id }
}

output "private_ips" {
  description = "Map of instance name => private IP."
  value       = { for name, inst in local.all_instances : name => inst.private_ip }
}
