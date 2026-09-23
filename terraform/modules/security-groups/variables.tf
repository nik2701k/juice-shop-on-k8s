variable "name" {
  description = "Name prefix applied to every resource in this module."
  type        = string
}

variable "vpc_id" {
  description = "VPC the security groups belong to."
  type        = string
}

variable "private_subnet_cidr" {
  description = <<-EOT
    CIDR of the private subnet. The app VM must accept traffic sourced from it
    because it is that subnet's NAT gateway.
  EOT
  type        = string
}

variable "wg_listen_port" {
  description = "WireGuard UDP listen port, the only port open to the internet."
  type        = number
  default     = 51820
}

variable "admin_cidrs" {
  description = <<-EOT
    CIDRs allowed to SSH to the app VM. Empty (the default) leaves port 22
    closed entirely, with SSM Session Manager as the access path.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.admin_cidrs, "0.0.0.0/0")
    error_message = "Refusing to open SSH to the world. Use SSM, or list a specific /32."
  }
}

variable "evaluator_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach the WAF on 443 without joining the VPN, for an
    evaluator who prefers an IP allowlist. Empty means VPN-only access.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.evaluator_cidrs, "0.0.0.0/0")
    error_message = "The lab must stay restricted to VPN users or a specific allowlist."
  }
}
