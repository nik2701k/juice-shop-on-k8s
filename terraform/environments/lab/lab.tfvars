# Committed on purpose: these are the shape of the lab, not secrets.
# Operator IPs and anything sensitive go in local.auto.tfvars (gitignored).

project     = "juiceshop-lab"
region      = "us-east-1"
aws_profile = "test1"

# Merged into provider default_tags, so every taggable resource inherits them.
# Owner/CostCenter make the lab findable in Cost Explorer; Repo traces a
# resource back to the code that created it.
tags = {
  Owner      = "nik2701k"
  CostCenter = "security-lab"
  Repo       = "juice-shop-on-k8s"
}

vpc_cidr            = "10.0.0.0/16"
public_subnet_cidr  = "10.0.1.0/24"
private_subnet_cidr = "10.0.11.0/24"

wg_listen_port = 51820
wg_client_cidr = "10.8.0.0/24"

app_instance_type      = "t3.medium" # 2 vCPU / 4 GiB
wazuh_instance_type    = "t3.large"  # 4 vCPU / 8 GiB, Wazuh's starting recommendation
app_root_volume_size   = 30
wazuh_root_volume_size = 20
wazuh_data_volume_size = 50
