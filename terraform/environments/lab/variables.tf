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

variable "tags" {
  description = <<-EOT
    Extra tags merged into provider default_tags and applied to every taggable
    resource. Ownership and cost-allocation tags belong here, not scattered
    across individual resources.
  EOT
  type        = map(string)
  default     = {}
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

variable "wg_peer_count" {
  description = "How many WireGuard peer configs to generate and publish to SSM."
  type        = number
}

variable "k3s_version" {
  description = "Pinned K3s release, so a rebuild months from now yields the same cluster."
  type        = string
}

variable "wazuh_version" {
  description = "Pinned wazuh-docker tag."
  type        = string
}

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

variable "app_instance_type" {
  description = "Instance type for the app VM."
  type        = string
}

variable "wazuh_instance_type" {
  description = "Instance type for the Wazuh VM."
  type        = string
}

variable "app_root_volume_size" {
  description = "Root volume size in GB for the app VM."
  type        = number
}

variable "wazuh_root_volume_size" {
  description = "Root volume size in GB for the Wazuh VM."
  type        = number
}

variable "wazuh_data_volume_size" {
  description = "Size in GB of the persistent EBS volume holding Wazuh indices."
  type        = number
}

variable "ssh_public_key" {
  description = <<-EOT
    Optional OpenSSH public key. Left null, no key pair exists at all and SSM
    Session Manager is the only way in. Belongs in local.auto.tfvars.
  EOT
  type        = string
  default     = null
}

variable "github_repository" {
  description = "owner/repo allowed to assume the CI deploy role."
  type        = string
}
