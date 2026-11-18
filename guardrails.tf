# Service control policies (SCPs). They cap what any identity in a member
# account can do, including that account's administrators. They never apply to
# the management account.

# --- Already existed before Terraform: imported -----------------------------

import {
  to = aws_organizations_policy.deny_leave_and_close
  id = var.existing.deny_leave_policy_id
}

import {
  to = aws_organizations_policy_attachment.deny_leave_and_close_root
  id = "${var.existing.root_id}:${var.existing.deny_leave_policy_id}"
}

resource "aws_organizations_policy" "deny_leave_and_close" {
  name        = "DenyLeaveAndCloseAccount"
  description = "Prevents member accounts from leaving the organization and self closure"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Deny"
      Action   = ["organizations:LeaveOrganization", "account:CloseAccount"]
      Resource = "*"
    }]
  })
}

resource "aws_organizations_policy_attachment" "deny_leave_and_close_root" {
  policy_id = aws_organizations_policy.deny_leave_and_close.id
  target_id = local.root_id
}

# --- Region restriction -----------------------------------------------------

# Denies every request outside the allowed regions. Services that are global,
# or that are only reachable through an endpoint in another region, are
# exempt so they keep working.
resource "aws_organizations_policy" "restrict_regions" {
  name        = "RestrictRegions"
  description = "Denies requests outside ${join(", ", local.allowed_regions)}, except for global services"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyOutsideAllowedRegions"
      Effect = "Deny"
      NotAction = [
        "account:*",
        "aws-portal:*",
        "billing:*",
        "budgets:*",
        "ce:*",
        "cloudfront:*",
        "cur:*",
        "freetier:*",
        "globalaccelerator:*",
        "health:*",
        "iam:*",
        "invoicing:*",
        "organizations:*",
        "payments:*",
        "pricing:*",
        "route53:*",
        "route53domains:*",
        "shield:*",
        "sts:*",
        "support:*",
        "supportplans:*",
        "tax:*",
        "trustedadvisor:*",
        "waf:*",
        "wafv2:*",
      ]
      Resource = "*"
      Condition = {
        StringNotEquals = {
          "aws:RequestedRegion" = local.allowed_regions
        }
      }
    }]
  })
}

resource "aws_organizations_policy_attachment" "restrict_regions_root" {
  policy_id = aws_organizations_policy.restrict_regions.id
  target_id = local.root_id
}

# --- Protect the security baseline ------------------------------------------

# Stops anyone inside a member account from switching off audit logging or
# threat detection, or from making S3 buckets public at the account level.
resource "aws_organizations_policy" "protect_security_baseline" {
  name        = "ProtectSecurityBaseline"
  description = "Denies disabling CloudTrail, GuardDuty, Config and the S3 account public access block"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ProtectCloudTrail"
        Effect = "Deny"
        Action = [
          "cloudtrail:DeleteTrail",
          "cloudtrail:StopLogging",
          "cloudtrail:UpdateTrail",
          "cloudtrail:PutEventSelectors",
        ]
        Resource = "*"
      },
      {
        Sid    = "ProtectGuardDuty"
        Effect = "Deny"
        Action = [
          "guardduty:DeleteDetector",
          "guardduty:DisassociateFromAdministratorAccount",
          "guardduty:UpdateDetector",
        ]
        Resource = "*"
      },
      {
        Sid    = "ProtectConfig"
        Effect = "Deny"
        Action = [
          "config:DeleteConfigurationRecorder",
          "config:DeleteDeliveryChannel",
          "config:StopConfigurationRecorder",
        ]
        Resource = "*"
      },
      {
        Sid      = "ProtectS3AccountPublicAccessBlock"
        Effect   = "Deny"
        Action   = ["s3:PutAccountPublicAccessBlock"]
        Resource = "*"
      },
    ]
  })
}

resource "aws_organizations_policy_attachment" "protect_security_baseline_root" {
  policy_id = aws_organizations_policy.protect_security_baseline.id
  target_id = local.root_id
}

# --- S3 Block Public Access for the whole organization ----------------------

# An S3 policy, not a service control policy: instead of denying API calls it
# switches on all four S3 Block Public Access settings in every account it
# applies to, and overrides the account-level setting. No bucket in those
# accounts can be made public, and the accounts cannot turn this off.
#
# The policy type only supports "all" or "none"; the four settings cannot be
# set one by one. Detaching the policy returns each account to the
# account-level setting it had before.
resource "aws_organizations_policy" "s3_block_public_access" {
  name        = "S3BlockPublicAccess"
  description = "Turns on all S3 Block Public Access settings in every account"
  type        = "S3_POLICY"

  content = jsonencode({
    s3_attributes = {
      public_access_block_configuration = {
        "@@assign" = "all"
      }
    }
  })

  # The S3_POLICY type must be enabled on the organization first.
  depends_on = [aws_organizations_organization.this]
}

resource "aws_organizations_policy_attachment" "s3_block_public_access_root" {
  policy_id = aws_organizations_policy.s3_block_public_access.id
  target_id = local.root_id
}
