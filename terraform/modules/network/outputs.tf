output "vpc_id" {
  description = "ID of the lab VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR of the lab VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_id" {
  description = "Subnet for internet-facing instances."
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "Subnet for instances with no public address."
  value       = aws_subnet.private.id
}

output "private_route_table_id" {
  description = "Route table the caller attaches the NAT-instance default route to."
  value       = aws_route_table.private.id
}

output "availability_zone" {
  description = "AZ both subnets live in."
  value       = local.az
}
