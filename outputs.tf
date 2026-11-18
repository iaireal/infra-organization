output "account_ids" {
  description = "Account ID of each member account, by name."
  value       = local.member_account_ids
}

output "organizational_unit_ids" {
  description = "ID of each organizational unit."
  value       = local.ou_ids
}

output "state_bucket" {
  description = "Bucket that holds Terraform state and lock files."
  value       = aws_s3_bucket.terraform_state.bucket
}
