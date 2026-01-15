provider "aws" {
  region = var.aws_region
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "tls_private_key" "ssh" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "this" {
  key_name   = "${var.name_prefix}-key"
  public_key = tls_private_key.ssh.public_key_openssh
}

locals {
  # Expand ~ to home directory (Terraform doesn't expand ~ automatically)
  # Replace ~ with home_dir if provided, otherwise use /tmp as fallback
  ssh_key_dir_expanded = var.home_dir != "" ? replace(var.ssh_key_dir, "~", var.home_dir) : var.ssh_key_dir
}

resource "local_file" "private_key" {
  filename        = "${local.ssh_key_dir_expanded}/${var.name_prefix}-key.pem"
  content         = tls_private_key.ssh.private_key_openssh
  file_permission = "0600"
}

resource "aws_security_group" "this" {
  name        = "${var.name_prefix}-sg"
  description = "Allow SSH + RDP"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  ingress {
    description = "RDP (xRDP)"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-sg"
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

locals {
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    dev_username         = var.dev_username
    rdp_password         = var.rdp_password
    git_version          = var.git_version
    python_version       = var.python_version
    node_version         = var.node_version
    npm_version          = var.npm_version
    docker_version_prefix= var.docker_version_prefix
    awscli_version       = var.awscli_version
    psql_major           = var.psql_major
    cursor_channel       = var.cursor_channel
  })
}

resource "aws_instance" "this" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type           = var.instance_type
  subnet_id               = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids  = [aws_security_group.this.id]
  key_name                = aws_key_pair.this.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size = var.root_volume_gb
    volume_type = "gp3"
  }

  user_data = local.user_data

  dynamic "instance_market_options" {
    for_each = var.use_spot ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        instance_interruption_behavior = "stop"
        spot_instance_type             = "persistent"
        max_price                      = var.spot_max_price != "" ? var.spot_max_price : null
      }
    }
  }

  tags = {
    Name = "${var.name_prefix}-vm"
  }
}
