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
  description = "Private address of the Wazuh VM. It has no public address."
  value       = aws_instance.wazuh.private_ip
}

output "wazuh_data_volume_id" {
  description = "EBS volume holding the Wazuh indices."
  value       = aws_ebs_volume.wazuh_data.id
}
