provider "aws" {
  region = var.region

  # null locally resolves to the default chain; set it in lab.tfvars to pin a
  # named CLI profile. CI leaves it unset and uses OIDC role credentials.
  profile = var.aws_profile

  # default_tags applies to every taggable resource the provider creates, so
  # no individual resource has to remember to tag itself. var.tags is merged
  # last so lab.tfvars can override a baseline value if it ever needs to.
  default_tags {
    tags = merge(
      {
        Project   = var.project
        Env       = "lab"
        ManagedBy = "terraform"
      },
      var.tags,
    )
  }
}
