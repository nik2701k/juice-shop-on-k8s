terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Partial backend config. bucket/key/region live in backend.hcl, which
  # scripts/bootstrap-state.sh generates and .gitignore excludes:
  #   terraform init -backend-config=backend.hcl
  # use_lockfile gives native S3 state locking, so no DynamoDB table is needed.
  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}
