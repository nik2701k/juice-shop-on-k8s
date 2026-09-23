variable "name" {
  description = "Name prefix applied to every resource in this module."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "public_subnet_cidr" {
  description = "CIDR for the public subnet (internet-facing workloads)."
  type        = string
}

variable "private_subnet_cidr" {
  description = "CIDR for the private subnet. Has no route to the IGW."
  type        = string
}

variable "availability_zone" {
  description = "AZ to place both subnets in. Defaults to the first available."
  type        = string
  default     = null
}
