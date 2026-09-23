data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  # One role per VM rather than one shared role. They carry the same policy
  # today, but the app VM will need to read the Wazuh credentials out of SSM
  # Parameter Store and the Wazuh VM must never be able to.
  roles = {
    app   = "App VM: K3s, WAF, WireGuard, NAT"
    wazuh = "Wazuh VM: manager, indexer, dashboard"
  }
}

# --------------------------------------------------------------------------
# Identities: SSM Session Manager access, no long-lived credentials anywhere
# --------------------------------------------------------------------------

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = local.roles

  name               = "${var.name}-${each.key}"
  description        = each.value
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# The AWS-managed policy for Session Manager. It grants no data-plane access,
# which is why SSH can stay closed entirely.
resource "aws_iam_role_policy_attachment" "ssm" {
  for_each = local.roles

  role       = aws_iam_role.this[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  for_each = local.roles

  name = "${var.name}-${each.key}"
  role = aws_iam_role.this[each.key].name
}

# Created only when a public key is supplied. Left null, the instances have no
# key pair at all and SSM is the sole way in.
resource "aws_key_pair" "this" {
  count = var.ssh_public_key == null ? 0 : 1

  key_name   = var.name
  public_key = var.ssh_public_key
}

# --------------------------------------------------------------------------
# App VM
# --------------------------------------------------------------------------

resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.app_instance_type
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [var.app_security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.this["app"].name
  key_name               = try(aws_key_pair.this[0].key_name, null)

  # Mandatory for a NAT instance: EC2 drops forwarded packets otherwise,
  # because their source address is not this instance's.
  source_dest_check = false

  user_data = templatefile("${path.module}/templates/app-userdata.sh.tftpl", {
    private_subnet_cidr = var.private_subnet_cidr
  })
  user_data_replace_on_change = true

  root_block_device {
    volume_size = var.app_root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  # IMDSv2 only. Unauthenticated metadata access is how a server-side request
  # forgery in the app turns into stolen role credentials, and this lab runs a
  # deliberately vulnerable application.
  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2 # containers reach IMDS through one extra hop
  }

  tags = { Name = "${var.name}-app" }
}

resource "aws_eip" "app" {
  instance = aws_instance.app.id
  domain   = "vpc"

  tags = { Name = "${var.name}-app" }
}

# The piece the network module deliberately left out: the private subnet's way
# off-VPC, through the app VM rather than a paid NAT Gateway.
resource "aws_route" "private_nat" {
  route_table_id         = var.private_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.app.primary_network_interface_id
}

# --------------------------------------------------------------------------
# Wazuh VM
# --------------------------------------------------------------------------

resource "aws_instance" "wazuh" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.wazuh_instance_type
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [var.wazuh_security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.this["wazuh"].name
  key_name               = try(aws_key_pair.this[0].key_name, null)

  user_data = templatefile("${path.module}/templates/wazuh-userdata.sh.tftpl", {
    data_volume_id = aws_ebs_volume.wazuh_data.id
  })
  user_data_replace_on_change = true

  root_block_device {
    volume_size = var.wazuh_root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
  }

  tags = { Name = "${var.name}-wazuh" }

  # Reaching the internet for package and image pulls depends on the NAT route
  # existing first, and nothing else in the graph expresses that.
  depends_on = [aws_route.private_nat]
}

# Wazuh's indices live here, not on the root volume, so that replacing the
# instance re-attaches the data rather than destroying it.
resource "aws_ebs_volume" "wazuh_data" {
  availability_zone = var.availability_zone
  size              = var.wazuh_data_volume_size
  type              = "gp3"
  encrypted         = true

  tags = { Name = "${var.name}-wazuh-data" }

  # "Reruns must preserve data." This makes losing it require editing code,
  # not just running the wrong command.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_volume_attachment" "wazuh_data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.wazuh_data.id
  instance_id = aws_instance.wazuh.id
}
