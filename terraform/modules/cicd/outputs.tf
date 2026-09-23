output "deploy_role_arn" {
  description = "Role ARN for the GitHub Actions deploy job."
  value       = aws_iam_role.deploy.arn
}

output "manifest_bucket" {
  description = "Bucket manifests are staged in before the node pulls them."
  value       = aws_s3_bucket.manifests.id
}
