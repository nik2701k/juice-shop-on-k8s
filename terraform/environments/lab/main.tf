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

module "compute" {
  source = "../../modules/compute"

  name                   = var.project
  availability_zone      = module.network.availability_zone
  public_subnet_id       = module.network.public_subnet_id
  private_subnet_id      = module.network.private_subnet_id
  private_subnet_cidr    = var.private_subnet_cidr
  private_route_table_id = module.network.private_route_table_id

  app_security_group_id   = module.security_groups.app_security_group_id
  wazuh_security_group_id = module.security_groups.wazuh_security_group_id

  app_instance_type      = var.app_instance_type
  wazuh_instance_type    = var.wazuh_instance_type
  app_root_volume_size   = var.app_root_volume_size
  wazuh_root_volume_size = var.wazuh_root_volume_size
  wazuh_data_volume_size = var.wazuh_data_volume_size
  ssh_public_key         = var.ssh_public_key
}
