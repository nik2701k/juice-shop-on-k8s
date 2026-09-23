provider "aws" {
  region = var.region

  # null locally resolves to the default chain; set it in lab.tfvars to pin a
  # named CLI profile. CI leaves it unset and uses OIDC role credentials.
  profile = var.aws_profile

  default_tags {
    tags = {
      Project   = var.project
      Env       = "lab"
      ManagedBy = "terraform"
    }
  }
}
