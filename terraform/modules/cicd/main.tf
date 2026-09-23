data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  # Derived, not configured: the name embeds the account id, and committing it
  # would put the account id in the repository for no benefit.
  state_bucket = "${var.name}-tfstate-${data.aws_caller_identity.current.account_id}"
}

# Manifests are staged here and pulled down by the node over SSM, so the
# cluster never needs an inbound path from CI.
resource "aws_s3_bucket" "manifests" {
  bucket = "${var.name}-manifests-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "manifests" {
  bucket                  = aws_s3_bucket.manifests.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "manifests" {
  bucket = aws_s3_bucket.manifests.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# GitHub's OIDC issuer. Federating to it means CI holds no AWS access key at
# all: it exchanges a short-lived GitHub token for short-lived AWS credentials.
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Scoped to this repository, and only to its protected `lab` environment.
    # A fork, a pull request from one, or a push to any other branch produces a
    # subject that does not match and cannot assume this role.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:environment:lab"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name                 = "${var.name}-github-deploy"
  description          = "Assumed by GitHub Actions to plan/apply the lab and ship manifests"
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "deploy" {
  # Terraform manages the whole lab, so the infrastructure services are broad.
  # They are still enumerated rather than "*", so a compromised workflow cannot
  # reach unrelated services in the account.
  statement {
    sid = "ManageLabInfrastructure"
    actions = [
      "ec2:*",
      "iam:*",
      "ssm:*",
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey",
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }

  statement {
    sid     = "TerraformState"
    actions = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [
      "arn:aws:s3:::${local.state_bucket}",
      "arn:aws:s3:::${local.state_bucket}/*",
    ]
  }

  statement {
    sid       = "StageManifests"
    actions   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [aws_s3_bucket.manifests.arn, "${aws_s3_bucket.manifests.arn}/*"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "${var.name}-github-deploy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}

# The app VM pulls staged manifests down itself, so CI never talks to the
# cluster directly.
data "aws_iam_policy_document" "node_read_manifests" {
  statement {
    actions   = ["s3:ListBucket", "s3:GetObject"]
    resources = [aws_s3_bucket.manifests.arn, "${aws_s3_bucket.manifests.arn}/*"]
  }
}

resource "aws_iam_role_policy" "node_read_manifests" {
  name   = "${var.name}-read-manifests"
  role   = var.app_role_name
  policy = data.aws_iam_policy_document.node_read_manifests.json
}
