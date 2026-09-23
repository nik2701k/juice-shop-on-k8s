variable "name" {
  description = "Name prefix applied to every resource in this module."
  type        = string
}

variable "github_repository" {
  description = "owner/repo allowed to assume the deploy role."
  type        = string
}

variable "app_role_name" {
  description = "App VM's IAM role, granted read access to the manifest bucket."
  type        = string
}
