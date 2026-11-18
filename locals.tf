locals {
  # Must match the name computed in Taskfile.yml.
  state_bucket_name = "iaireal-terraform-state-${var.management_account_id}"

  # The only region the project uses. The region guardrail denies all others.
  allowed_regions = ["us-east-1"]
}
