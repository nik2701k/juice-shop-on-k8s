output "vpc_id" {
  description = "ID of the lab VPC."
  value       = module.network.vpc_id
}

output "public_subnet_id" {
  description = "Subnet hosting the app VM."
  value       = module.network.public_subnet_id
}

output "private_subnet_id" {
  description = "Subnet hosting the Wazuh VM."
  value       = module.network.private_subnet_id
}

output "app_security_group_id" {
  description = "Security group for the app VM."
  value       = module.security_groups.app_security_group_id
}

output "wazuh_security_group_id" {
  description = "Security group for the Wazuh VM."
  value       = module.security_groups.wazuh_security_group_id
}
