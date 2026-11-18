terraform {
  # 1.10 introduced S3 native state locking (use_lockfile).
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # State and its lock file live in the same S3 bucket. The lock is a
  # `<key>.tflock` object written with an S3 conditional write, so no DynamoDB
  # table is needed. The bucket itself is managed in state_bucket.tf.
  #
  # The bucket name contains the AWS account ID, so it is not written here. It
  # is passed at init time: terraform init -backend-config="bucket=<name>".
  # `task init` does this.
  backend "s3" {
    key          = "infra-organization/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"

  # Refuse to run against any account other than the management account.
  allowed_account_ids = [var.management_account_id]

  default_tags {
    tags = {
      Project   = "iaireal"
      ManagedBy = "terraform"
      Repo      = "infra-organization"
    }
  }
}
