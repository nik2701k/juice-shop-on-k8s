locals {
  # Every Wazuh listener is reachable only from the app VM. VPN clients get
  # here via the app VM's masquerade, so their traffic arrives with the app
  # VM's private address and matches the same rule.
  wazuh_ports = {
    agent_events = { port = 1514, description = "Wazuh agent event stream" }
    agent_enroll = { port = 1515, description = "Wazuh agent enrollment" }
    manager_api  = { port = 55000, description = "Wazuh manager REST API" }
    indexer_api  = { port = 9200, description = "Wazuh Indexer API, queried by the verifier" }
    dashboard    = { port = 443, description = "Wazuh dashboard UI over the VPN" }
  }
}

# --------------------------------------------------------------------------
# App VM: K3s + ModSecurity WAF + WireGuard endpoint + NAT for the private subnet
# --------------------------------------------------------------------------

resource "aws_security_group" "app" {
  name        = "${var.name}-app"
  description = "App VM: VPN endpoint, WAF ingress, NAT for the private subnet"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-app" }

  lifecycle {
    create_before_destroy = true
  }
}

# The only port this lab exposes to the internet. Everything else rides the tunnel.
resource "aws_vpc_security_group_ingress_rule" "app_wireguard" {
  security_group_id = aws_security_group.app.id
  description       = "WireGuard tunnel"
  ip_protocol       = "udp"
  from_port         = var.wg_listen_port
  to_port           = var.wg_listen_port
  cidr_ipv4         = "0.0.0.0/0"
}

# Return path for the private subnet: the Wazuh VM sends its egress to this
# ENI, so the packets arrive as ingress and must be permitted.
resource "aws_vpc_security_group_ingress_rule" "app_nat_from_private" {
  security_group_id = aws_security_group.app.id
  description       = "NAT traffic forwarded from the private subnet"
  ip_protocol       = "-1"
  cidr_ipv4         = var.private_subnet_cidr
}

resource "aws_vpc_security_group_ingress_rule" "app_ssh" {
  for_each = toset(var.admin_cidrs)

  security_group_id = aws_security_group.app.id
  description       = "SSH break-glass from an operator address"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = each.value
}

# Allowlist path for an evaluator who does not want to import a WireGuard
# peer. HTTPS only, so the WAF is never bypassed by a plaintext request.
resource "aws_vpc_security_group_ingress_rule" "app_evaluator_https" {
  for_each = toset(var.evaluator_cidrs)

  security_group_id = aws_security_group.app.id
  description       = "WAF ingress for an allowlisted evaluator"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  description       = "Package pulls, container images, SSM, and NAT forwarding"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# --------------------------------------------------------------------------
# Wazuh VM: manager + indexer + dashboard, private subnet, no public address
# --------------------------------------------------------------------------

resource "aws_security_group" "wazuh" {
  name        = "${var.name}-wazuh"
  description = "Wazuh VM: reachable only from the app VM security group"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-wazuh" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "wazuh" {
  for_each = local.wazuh_ports

  security_group_id            = aws_security_group.wazuh.id
  description                  = each.value.description
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  referenced_security_group_id = aws_security_group.app.id
}

resource "aws_vpc_security_group_egress_rule" "wazuh_all" {
  security_group_id = aws_security_group.wazuh.id
  description       = "Container image pulls and SSM, via the app VM NAT hop"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
