# Committed on purpose: these are the shape of the lab, not secrets.
# Operator IPs and anything sensitive go in local.auto.tfvars (gitignored).

project     = "juiceshop-lab"
region      = "us-east-1"
aws_profile = "test1"

# 10.0.0.0/16 is one of the most commonly claimed private ranges: corporate
# VPNs, home routers and Docker bridges all grab it, and a client that already
# has a route for it cannot install the tunnel's. Verified in practice - a
# peer's existing VPN route silently won and VPC traffic never entered the
# tunnel. 10.66/16 is chosen to be unlikely to collide.

# Merged into provider default_tags, so every taggable resource inherits them.
# Owner/CostCenter make the lab findable in Cost Explorer; Repo traces a
# resource back to the code that created it.
tags = {
  Owner      = "nik2701k"
  CostCenter = "security-lab"
  Repo       = "juice-shop-on-k8s"
}

vpc_cidr            = "10.66.0.0/16"
public_subnet_cidr  = "10.66.1.0/24"
private_subnet_cidr = "10.66.11.0/24"

wg_listen_port = 51820
wg_client_cidr = "10.8.0.0/24"
wg_peer_count  = 2

k3s_version   = "v1.31.5+k3s1"
wazuh_version = "v4.14.7"

app_instance_type      = "t3.medium" # 2 vCPU / 4 GiB
wazuh_instance_type    = "t3.large"  # 4 vCPU / 8 GiB, Wazuh's starting recommendation
app_root_volume_size   = 30
wazuh_root_volume_size = 20
wazuh_data_volume_size = 50

github_repository = "nik2701k/juice-shop-on-k8s"
