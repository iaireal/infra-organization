# The organization already exists (it was created in the console), so it is
# imported instead of created.
import {
  to = aws_organizations_organization.this
  id = var.existing.organization_id
}

resource "aws_organizations_organization" "this" {
  feature_set = "ALL"

  enabled_policy_types = ["SERVICE_CONTROL_POLICY"]

  # Services allowed to act across the organization. Removing an entry turns
  # that service's organization integration off.
  aws_service_access_principals = [
    "sso.amazonaws.com", # IAM Identity Center (already enabled before import)
    "iam.amazonaws.com", # centralized root access, see root_access.tf
  ]

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  root_id = aws_organizations_organization.this.roots[0].id
}

# ---------------------------------------------------------------------------
# Organizational units
#
#   Root
#   ├── (management account: billing, Identity Center, this Terraform only)
#   ├── Security    log archive and security tooling accounts
#   └── Workloads   accounts that run the application
# ---------------------------------------------------------------------------

resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = local.root_id
}

resource "aws_organizations_organizational_unit" "workloads" {
  name      = "Workloads"
  parent_id = local.root_id
}

locals {
  ou_ids = {
    security  = aws_organizations_organizational_unit.security.id
    workloads = aws_organizations_organizational_unit.workloads.id
  }
}

# ---------------------------------------------------------------------------
# Member accounts
# ---------------------------------------------------------------------------

resource "aws_organizations_account" "this" {
  for_each = var.accounts

  name      = each.key
  email     = each.value.email
  parent_id = local.ou_ids[each.value.ou]

  # Role the management account can assume in the new account.
  role_name = "OrganizationAccountAccessRole"

  # Removing an account from this configuration must never close it silently.
  close_on_deletion = false

  lifecycle {
    prevent_destroy = true
    # role_name cannot be read back from AWS, so it would show as a change.
    ignore_changes = [role_name]
  }

  # New accounts are created without root user credentials once centralized
  # root access is on.
  depends_on = [aws_iam_organizations_features.this]
}
