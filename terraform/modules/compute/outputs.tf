output "app_instance_id" {
  description = "Instance ID of the app VM."
  value       = aws_instance.app.id
}

output "app_public_ip" {
  description = "Elastic IP of the app VM. The WireGuard endpoint."
  value       = aws_eip.app.public_ip
}

output "app_private_ip" {
  description = "Private address of the app VM."
  value       = aws_instance.app.private_ip
}

output "wazuh_instance_id" {
  description = "Instance ID of the Wazuh VM."
  value       = aws_instance.wazuh.id
}

output "wazuh_private_ip" {
  description = "Private address of the Wazuh VM. Fixed, and it has no public address."
  value       = local.wazuh_private_ip
}

output "wazuh_data_volume_id" {
  description = "EBS volume holding the Wazuh indices."
  value       = aws_ebs_volume.wazuh_data.id
}

output "wireguard_client_config_parameters" {
  description = <<-EOT
    SSM parameter names holding the WireGuard client configs. Read one with:
      aws ssm get-parameter --with-decryption --name <name> \
        --query Parameter.Value --output text
  EOT
  value       = [for i in range(1, var.wg_peer_count + 1) : "/${var.name}/wireguard/client-${i}"]
}

output "kubeconfig_parameter" {
  description = <<-EOT
    SSM parameter holding the K3s kubeconfig, with its server URL rewritten to
    the app VM's private address so it works over the VPN. Read it with:
      aws ssm get-parameter --with-decryption --name <name> \
        --query Parameter.Value --output text > kubeconfig
  EOT
  value       = "/${var.name}/k3s/kubeconfig"
}

output "app_role_name" {
  description = "App VM IAM role name, so other modules can attach policies to it."
  value       = aws_iam_role.this["app"].name
}
