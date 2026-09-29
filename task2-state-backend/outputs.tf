output "state_bucket" {
  description = "Name of the S3 bucket holding Terraform state."
  value       = aws_s3_bucket.state.id
}

output "lock_table" {
  description = "Name of the DynamoDB state-lock table."
  value       = aws_dynamodb_table.locks.name
}

output "backend_hcl" {
  description = "Paste into ../task1-ec2/backend.hcl"
  value       = <<-EOT
    bucket         = "${aws_s3_bucket.state.id}"
    region         = "${var.region}"
    dynamodb_table = "${aws_dynamodb_table.locks.name}"
  EOT
}
