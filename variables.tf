variable "management_account_id" {
  description = "ID of the management account. Terraform refuses to run against any other account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "management_account_id must be a 12-digit AWS account ID."
  }
}

variable "existing" {
  description = <<-EOT
    IDs of the resources that were created in the console before Terraform and
    are adopted with import blocks: the organization (o-...), its root (r-...)
    and the DenyLeaveAndCloseAccount policy (p-...). Only read on the apply
    that imports them.
  EOT
  type = object({
    organization_id      = string
    root_id              = string
    deny_leave_policy_id = string
  })
}

variable "accounts" {
  description = <<-EOT
    Member accounts to create, keyed by account name. Each account needs an
    email address that no other AWS account uses. `ou` is "security" or
    "workloads".
  EOT
  type = map(object({
    email = string
    ou    = string
  }))

  validation {
    condition     = alltrue([for a in values(var.accounts) : contains(["security", "workloads"], a.ou)])
    error_message = "Each account's ou must be \"security\" or \"workloads\"."
  }

  validation {
    condition     = length(distinct([for a in values(var.accounts) : lower(a.email)])) == length(var.accounts)
    error_message = "Each account must have a different email address."
  }

  validation {
    condition     = alltrue([for a in values(var.accounts) : !endswith(lower(a.email), "@example.com")])
    error_message = "Replace the example.com placeholder emails with real addresses."
  }
}

variable "sso_user_name" {
  description = "IAM Identity Center user name that gets access to every account."
  type        = string
}

variable "admin_permission_set_name" {
  description = "Name of the existing administrator permission set in IAM Identity Center."
  type        = string
}

variable "budget_alert_email" {
  description = "Email address that receives budget alerts."
  type        = string

  validation {
    condition     = !endswith(lower(var.budget_alert_email), "@example.com")
    error_message = "Replace the example.com placeholder email with a real address."
  }
}

variable "monthly_budget_usd" {
  description = "Monthly budget for the whole organization, in US dollars."
  type        = number
  default     = 10
}
