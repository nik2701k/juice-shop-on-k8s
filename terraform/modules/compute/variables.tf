variable "name" {
  description = "Name prefix applied to every resource in this module."
  type        = string
}

variable "public_subnet_id" {
  description = "Subnet for the app VM."
  type        = string
}

variable "private_subnet_id" {
  description = "Subnet for the Wazuh VM."
  type        = string
}

variable "availability_zone" {
  description = <<-EOT
    AZ both instances and the data volume live in. Supplied explicitly rather
    than read back off the instance, which would make the volume depend on the
    instance while the instance's user_data depends on the volume.
  EOT
  type        = string
}

variable "private_subnet_cidr" {
  description = "CIDR the app VM masquerades for when acting as the NAT hop."
  type        = string
}

variable "private_route_table_id" {
  description = "Route table that gets its default route pointed at the app VM ENI."
  type        = string
}

variable "app_security_group_id" {
  description = "Security group for the app VM."
  type        = string
}

variable "wazuh_security_group_id" {
  description = "Security group for the Wazuh VM."
  type        = string
}

variable "app_instance_type" {
  description = "Instance type for the app VM (K3s, WAF, WireGuard, NAT)."
  type        = string
}

variable "wazuh_instance_type" {
  description = "Instance type for the Wazuh VM (manager, indexer, dashboard)."
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
  description = <<-EOT
    Size in GB of the separate EBS volume holding Wazuh's indices. Kept off the
    root volume so a rebuilt instance re-attaches its data instead of losing it.
  EOT
  type        = number
}

variable "vpc_cidr" {
  description = "VPC CIDR, routed to VPN peers so they can reach the private subnet."
  type        = string
}

variable "wg_client_cidr" {
  description = "Address pool handed out to WireGuard peers."
  type        = string
}

variable "wg_listen_port" {
  description = "WireGuard UDP listen port."
  type        = number
}

variable "wg_peer_count" {
  description = <<-EOT
    How many peer keypairs to generate. Each one's client config is published
    to SSM Parameter Store as a SecureString. Two by default: one operator,
    one evaluator.
  EOT
  type        = number
  default     = 2
}

variable "k3s_version" {
  description = <<-EOT
    K3s release to install, pinned rather than tracking latest so a rebuild
    months from now produces the same cluster.
  EOT
  type        = string
}

variable "ssh_public_key" {
  description = <<-EOT
    Optional OpenSSH public key. Leave null (the default) and no key pair is
    created at all, making SSM Session Manager the only access path. Setting it
    is only useful alongside a non-empty admin_cidrs.
  EOT
  type        = string
  default     = null
  sensitive   = false
}
