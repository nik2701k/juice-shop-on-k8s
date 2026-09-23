module "network" {
  source = "../../modules/network"

  name                = var.project
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
}

module "security_groups" {
  source = "../../modules/security-groups"

  name                = var.project
  vpc_id              = module.network.vpc_id
  private_subnet_cidr = var.private_subnet_cidr
  wg_listen_port      = var.wg_listen_port
  admin_cidrs         = var.admin_cidrs
  evaluator_cidrs     = var.evaluator_cidrs
}

# Next: modules/compute adds both instances, then the private subnet's default
# route to the app VM's ENI (aws_route on module.network.private_route_table_id).
