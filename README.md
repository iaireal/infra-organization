# infra-organization

Terraform that sets up the AWS organization for iaireal: the accounts, who can sign in to
them, the limits on what can be done inside them, a spending alert, and the S3 bucket
where Terraform keeps its state.

It is the first infrastructure repository to apply, because every other one deploys into
an account that this one creates.

- **Runs against:** the organization's management account
- **Region:** `us-east-1`
- **Status:** applied
- **Private values:** none in this repository, see [Private values](#private-values)

## Contents

1. [Why an organization with several accounts](#why-an-organization-with-several-accounts)
2. [What this repository creates](#what-this-repository-creates)
3. [Private values](#private-values)
4. [File by file](#file-by-file)
5. [State and locking](#state-and-locking)
6. [First-time setup](#first-time-setup)
7. [Everyday use](#everyday-use)
8. [Common changes](#common-changes)
9. [Things that can hurt](#things-that-can-hurt)
10. [Not covered yet](#not-covered-yet)

## Why an organization with several accounts

An AWS account is the strongest wall AWS offers. Nothing in one account can reach another
unless access is granted on purpose. An **organization** groups accounts under one bill and
lets rules be applied to all of them from one place.

iaireal stores private financial data, so the layout keeps three things apart:

- **The management account** owns the organization and pays the bill. It is the most
  powerful account, and the organization's guardrails do not apply to it. It therefore
  runs nothing except billing, sign-in (IAM Identity Center) and this Terraform.
- **Security accounts** hold audit logs and security tooling. A mistake or a break-in in
  the application account cannot erase the logs, because they live elsewhere.
- **Workload accounts** run the application. Production and development are separate, so
  an experiment in development cannot touch real user data.

## What this repository creates

```
Organization
│
├── management account                    billing, Identity Center, this Terraform
│     ├── S3 bucket: Terraform state and locks
│     ├── Budget: monthly spend alert for the whole organization
│     └── Identity Center: permission sets and account access
│
├── Security (organizational unit)
│     ├── iaireal-log-archive             audit logs
│     └── iaireal-security                security tooling
│
└── Workloads (organizational unit)
      ├── iaireal-prod                    the live application
      └── iaireal-dev                     development and testing

Guardrails attached at the root, applying to every member account:
  DenyLeaveAndCloseAccount · RestrictRegions · ProtectSecurityBaseline

Applying to every account, the management account included:
  S3BlockPublicAccess
```

The list of member accounts is not in the code. It comes from the private inputs file, so
starting with fewer accounts and adding the rest later is a one-line change.

### Terms used here

| Term | Meaning |
| ---- | ------- |
| Management account | The account that created the organization. Pays the bill and controls everything. |
| Member account | Any other account in the organization. |
| Organizational unit (OU) | A folder of accounts. Rules attached to it apply to every account inside. |
| Service control policy (SCP) | A rule that caps what anyone in a member account can do, administrators included. It never grants access; it only removes it. |
| IAM Identity Center | The single sign-in for all accounts. This is what `aws sso login` uses. |
| Permission set | A named level of access in Identity Center, such as administrator or read-only. |
| Trusted access | Permission for an AWS service to act across the whole organization. |

## Private values

This repository is public, so it contains no account IDs, organization IDs, email
addresses or credentials. Everything private is supplied when Terraform runs:

| Value | Where it comes from |
| ----- | ------------------- |
| Account emails, alert email, management account ID, IDs of the adopted resources | A tfvars file kept outside this repository, passed with `-var-file` |
| State bucket name (it contains the account ID) | Computed by `Taskfile.yml` from the signed-in account and passed to `terraform init` |
| AWS credentials | The `management` AWS CLI profile, through `aws sso login` |

There is no default location for the inputs file. Its path must be given every time:
`task plan VAR_FILE=/path/to/file.tfvars`.
`terraform.tfvars.example` shows the format with placeholder values, and `.gitignore`
blocks every other `*.tfvars` file.

Terraform state holds these values too. It stays in the private S3 bucket and is never
committed.

## File by file

### `versions.tf`

Pins Terraform (1.10 or later) and the AWS provider (6.x), and configures the S3 backend
without a bucket name, which is passed at init time.
The provider has `allowed_account_ids` set to `management_account_id`, so Terraform refuses
to run if the signed-in profile points at any other account. Every resource gets the tags
`Project`, `ManagedBy` and `Repo`.

### `locals.tf`

The state bucket name, built from the management account ID, and the list of allowed
regions.

### `variables.tf`

The inputs, which are set in the private inputs file:

| Variable | Purpose | Default |
| -------- | ------- | ------- |
| `management_account_id` | The management account; Terraform refuses to run against any other | none |
| `existing` | IDs of the organization, its root and the policy that existed before Terraform, used by the `import` blocks | none |
| `accounts` | Member accounts to create: name, email and OU (`security` or `workloads`) | none |
| `sso_user_name` | Identity Center user who gets access to every account | none |
| `admin_permission_set_name` | Existing administrator permission set | none |
| `budget_alert_email` | Where budget alerts are sent | none |
| `monthly_budget_usd` | Monthly budget for the whole organization | `10` |

Terraform rejects the input if two accounts share an email, if an OU name is unknown, or
if a placeholder `example.com` address is left in.

### `state_bucket.tf`

The bucket that stores Terraform state, described under
[State and locking](#state-and-locking). It also turns on the account-wide S3 public
access block for the management account, so no bucket there can ever be made public.

### `organization.tf`

- **The organization.** It already existed, so an `import` block adopts it instead of
  creating it. The only change is enabling trusted access for IAM, which centralized root
  access needs.
- **Two organizational units,** Security and Workloads.
- **The member accounts,** one per entry in `var.accounts`. Each is created with the
  `OrganizationAccountAccessRole` role, which lets an administrator of the management
  account get into the new account even if Identity Center is unavailable.

Accounts have `prevent_destroy` and `close_on_deletion = false`: Terraform will neither
delete nor close an account.

### `root_access.tf`

Turns on centralized root access. Every AWS account has a root user that can do anything
and cannot be restricted. With this feature, member accounts are created with **no root
password, access keys or MFA at all**, so there is nothing to steal. The rare task that
truly needs root is done from the management account through a short-lived session.

The management account's own root user is not affected. It keeps its password and MFA.

### `guardrails.tf`

Three service control policies, all attached at the organization root:

| Policy | Effect |
| ------ | ------ |
| `DenyLeaveAndCloseAccount` | A member account cannot leave the organization or close itself. Already existed; imported. |
| `RestrictRegions` | Denies every request outside `us-east-1`. Global services (IAM, Organizations, billing, Route 53, CloudFront, support and similar) are exempt so they keep working. |
| `ProtectSecurityBaseline` | Denies stopping or deleting CloudTrail, GuardDuty and AWS Config, and denies changing the S3 account public access block. |

None of these apply to the management account. AWS never applies service control policies
there.

One more guardrail is a different kind of policy, an **S3 policy**:

| Policy | Effect |
| ------ | ------ |
| `S3BlockPublicAccess` | Switches on all four S3 Block Public Access settings in every account, the management account included, and overrides the account-level setting. No bucket can be made public. |

### `identity_center.tf`

The Identity Center instance, the user and the administrator permission set were created
in the console; this file only looks them up. It adds:

- a `ReadOnlyAccess` permission set (AWS managed `ReadOnlyAccess` policy, 8-hour session);
- **administrator** access for the owner on each member account;
- **read-only** access for the owner on every account, the management account included.

After applying, the sign-in portal shows each account with the roles available on it.

### `budget.tf`

One monthly cost budget. Because the management account pays the consolidated bill, the
budget covers all accounts. It emails `budget_alert_email` when actual spend passes 80% of
the limit, and when the month is forecast to end above it. A budget only alerts; it does
not stop spending.

### `outputs.tf`

Prints the member account IDs, the organizational unit IDs and the state bucket name after
an apply. Other repositories need the account IDs.

### `Taskfile.yml`

Wraps the commands, with `AWS_PROFILE=management` and `AWS_REGION=us-east-1` already set.
It computes the state bucket name and passes the private inputs file to Terraform.

| Task | What it does |
| ---- | ------------ |
| `task bootstrap` | Creates the empty state bucket if it does not exist |
| `task init` | Runs `bootstrap`, then `terraform init` with the bucket name |
| `task fmt` | Formats the files |
| `task validate` | Checks formatting and validates the configuration |
| `task plan VAR_FILE=<path>` | Shows what would change and saves it to `tfplan` |
| `task apply` | Applies the saved `tfplan`, then deletes it |

## State and locking

Terraform records what it has created in a **state** file. Two runs at the same time would
corrupt it, so Terraform takes a **lock** first.

- **Where the state is:** the bucket `iaireal-terraform-state-<management-account-id>`,
  under the key `infra-organization/terraform.tfstate`
- **How locking works:** `use_lockfile = true` makes Terraform write a
  `terraform.tfstate.tflock` object beside the state, using an S3 conditional write that
  fails if the object already exists. The lock is removed when the run ends. No DynamoDB
  table is involved.
- **How the bucket is protected:** versioning (a broken state can be rolled back),
  encryption at rest, all public access blocked, HTTPS required, old versions kept for 90
  days, and `prevent_destroy` so Terraform cannot delete it.

**The bootstrap problem.** Terraform needs the bucket before it can run, so it cannot be
the thing that creates it. `task bootstrap` creates an empty, private, versioned bucket
with the AWS CLI. On the first apply, the `import` block in `state_bucket.tf` puts that
bucket under Terraform's control and adds the remaining settings.

**Other repositories** can keep their state in the same bucket under their own key,
`<repo-name>/terraform.tfstate`.

**If a lock is left behind** after a crashed run, Terraform prints a lock ID. Check that no
other run is in progress, then release it with `terraform force-unlock <lock-id>`.

## First-time setup

Requires Terraform 1.10 or later, the AWS CLI and [Task](https://taskfile.dev).

1. Sign in: `aws sso login --profile management`
2. Create the private inputs file outside this repository and fill in the real values:
   ```bash
   cp terraform.tfvars.example /path/to/private/infra-organization.tfvars
   ```
   Every account needs an email address that no AWS account has ever used. Many mail
   providers support plus-addressing, which gives one inbox many addresses:
   `you+iaireal-prod@your-domain` is delivered to `you@your-domain`.
3. Create the state bucket and initialize: `task init`
4. Review the plan: `task plan VAR_FILE=/path/to/private/infra-organization.tfvars`.
   Expect 4 imports (the state bucket, the organization, the
   existing policy and its attachment) and no destroys.
5. Apply it: `task apply`
6. Sign in again so the new accounts and roles appear:
   `aws sso login --profile management`

Account creation takes a few minutes per account. AWS sends a welcome email to each
account's address.

## Everyday use

```bash
task plan VAR_FILE=/path/to/file.tfvars   # always review before applying
task apply                                # applies exactly what was reviewed
```

`task apply` refuses to run without a saved plan, so nothing is ever applied unseen.

## Common changes

**Add an account.** Add an entry to `accounts` in the private inputs file, then plan and apply.
The guardrails and sign-in access are applied to it automatically.

**Allow another region.** Add it to `allowed_regions` in `locals.tf`.

**Change the budget.** Set `monthly_budget_usd` in the private inputs file.

**Add a guardrail.** Add an `aws_organizations_policy` and an
`aws_organizations_policy_attachment` to `guardrails.tf`. Attach it to one organizational
unit first if it could block real work. AWS allows at most five policies attached to any
one root, unit or account, and the root already has four (the AWS default `FullAWSAccess`
plus the three above), so attach further ones to a unit. A policy can be at most 5,120
characters.

**Give another person access.** Create the user in Identity Center, then add assignments
in `identity_center.tf`. For more than two people, switch to groups.

## Things that can hurt

- **Accounts are close to permanent.** Closing an account takes 90 days, and its email
  address can never be used for another AWS account. Decide the list carefully.
- **Removing an account from the inputs file does not remove it.** `prevent_destroy`
  stops the plan. This is on purpose.
- **A wrong guardrail can lock everyone out of the member accounts,** administrators
  included. The management account is never affected, so it is always the way back in.
- **Do not remove an entry from `aws_service_access_principals`** without meaning to.
  Removing `sso.amazonaws.com` would disable sign-in across the organization.
- **Never commit a `*.tfvars` file, a state file or a saved plan.** They hold private
  values. `.gitignore` blocks them; do not force-add them.
- **Do not delete the state bucket or its contents.** Without state, Terraform no longer
  knows what it manages.
- **Keep workloads out of the management account.** Guardrails do not apply there.

## Not covered yet

These need the log archive and security accounts to exist, so they come in a later step:

- an organization-wide CloudTrail trail delivering to the log archive account;
- IAM Access Analyzer, GuardDuty and Security Hub, administered from the security account;
- alternate contacts (billing, operations, security) on each account.
