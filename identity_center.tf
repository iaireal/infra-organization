# IAM Identity Center: who can sign in to which account, and with what access.
# The Identity Center instance, the user and the administrator permission set
# were created in the console and are only looked up here.

data "aws_ssoadmin_instances" "this" {}

locals {
  sso_instance_arn  = data.aws_ssoadmin_instances.this.arns[0]
  identity_store_id = data.aws_ssoadmin_instances.this.identity_store_ids[0]
}

data "aws_identitystore_user" "owner" {
  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = var.sso_user_name
    }
  }
}

data "aws_ssoadmin_permission_set" "admin" {
  instance_arn = local.sso_instance_arn
  name         = var.admin_permission_set_name
}

# Read-only access, for inspecting an account with no risk of changing it.
resource "aws_ssoadmin_permission_set" "read_only" {
  instance_arn     = local.sso_instance_arn
  name             = "ReadOnlyAccess"
  description      = "Read-only access to all services"
  session_duration = "PT8H"
}

resource "aws_ssoadmin_managed_policy_attachment" "read_only" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.read_only.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

locals {
  member_account_ids = { for name, account in aws_organizations_account.this : name => account.id }

  # Read-only is granted on every account, the management account included.
  read_only_account_ids = merge(local.member_account_ids, { management = var.management_account_id })
}

# Administrator on each member account. The management account already has
# this assignment, made in the console.
resource "aws_ssoadmin_account_assignment" "admin" {
  for_each = local.member_account_ids

  instance_arn       = local.sso_instance_arn
  permission_set_arn = data.aws_ssoadmin_permission_set.admin.arn

  principal_id   = data.aws_identitystore_user.owner.user_id
  principal_type = "USER"

  target_id   = each.value
  target_type = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "read_only" {
  for_each = local.read_only_account_ids

  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.read_only.arn

  principal_id   = data.aws_identitystore_user.owner.user_id
  principal_type = "USER"

  target_id   = each.value
  target_type = "AWS_ACCOUNT"

  depends_on = [aws_ssoadmin_managed_policy_attachment.read_only]
}
