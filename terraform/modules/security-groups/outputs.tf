output "app_security_group_id" {
  description = "Security group for the app VM."
  value       = aws_security_group.app.id
}

output "wazuh_security_group_id" {
  description = "Security group for the Wazuh VM."
  value       = aws_security_group.wazuh.id
}
