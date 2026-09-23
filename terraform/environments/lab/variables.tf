# No defaults on the infrastructure-shape variables: lab.tfvars is the single
# source of truth for them, so a value can never silently drift between a
# default here and the tfvars file.

variable "project" {
  description = "Name prefix for every resource in the lab."
  type        = string
}

variable "region" {
  description = "AWS region to deploy into."
  type        = string
}

variable "aws_profile" {
  description = <<-EOT
    Local AWS CLI profile to authenticate with. Leave null in CI, where the
    provider picks up OIDC-assumed role credentials from the environment.
  EOT
  type        = string
  default     = null
}

variable "vpc_cidr" {
  description = "CIDR for the lab VPC."
  type        = string
}

variable "public_subnet_cidr" {
  description = "Public subnet: app VM (K3s, WAF, WireGuard, NAT)."
  type        = string
}

variable "private_subnet_cidr" {
  description = "Private subnet: Wazuh VM, no public address."
  type        = string
}

variable "wg_listen_port" {
  description = "WireGuard UDP listen port on the app VM."
  type        = number
}

variable "wg_client_cidr" {
  description = "Address pool handed out to WireGuard peers."
  type        = string
}

# Operator addresses are deliberately not in the committed tfvars. Put them in
# local.auto.tfvars, which is gitignored, so no home IP reaches the repo.

variable "admin_cidrs" {
  description = "CIDRs allowed to SSH to the app VM. Empty keeps port 22 shut; use SSM."
  type        = list(string)
  default     = []
}

variable "evaluator_cidrs" {
  description = "CIDRs allowed to reach the WAF on 443 without the VPN. Empty means VPN-only."
  type        = list(string)
  default     = []
}
