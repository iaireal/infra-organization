# Centralized root access for member accounts.
#
# With this on, member accounts are created with no root password, access keys
# or MFA to manage, and the rare task that needs root is done from the
# management account through a short-lived root session.
resource "aws_iam_organizations_features" "this" {
  enabled_features = [
    "RootCredentialsManagement",
    "RootSessions",
  ]

  # Needs trusted access for iam.amazonaws.com on the organization.
  depends_on = [aws_organizations_organization.this]
}
