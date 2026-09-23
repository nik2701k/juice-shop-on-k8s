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

output "app_public_ip" {
  description = "Elastic IP of the app VM. The WireGuard endpoint."
  value       = module.compute.app_public_ip
}

output "app_instance_id" {
  description = "Instance ID of the app VM, for SSM Session Manager."
  value       = module.compute.app_instance_id
}

output "app_private_ip" {
  description = "Private address of the app VM, reachable over the VPN."
  value       = module.compute.app_private_ip
}

output "wazuh_private_ip" {
  description = "Private address of the Wazuh VM. It has no public address."
  value       = module.compute.wazuh_private_ip
}

output "wazuh_instance_id" {
  description = "Instance ID of the Wazuh VM, for SSM Session Manager."
  value       = module.compute.wazuh_instance_id
}

output "wireguard_client_config_parameters" {
  description = "SSM parameters holding the WireGuard client configs."
  value       = module.compute.wireguard_client_config_parameters
}
