locals {
  common_tags = {
    Project = var.project_name
  }

  instances = {
    api = {
      name       = "${var.project_name}-api"
      subnet     = "public"
      private_ip = "10.0.1.10"
    }
    engine = {
      name       = "${var.project_name}-engine"
      subnet     = "private"
      private_ip = "10.0.2.10"
    }
    inference = {
      name       = "${var.project_name}-inference"
      subnet     = "private"
      private_ip = "10.0.2.20"
    }
    caller = {
      name       = "${var.project_name}-caller"
      subnet     = "private"
      private_ip = "10.0.2.30"
    }
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true

  owners = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-igw"
  })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-subnet"
  })
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-subnet"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-nat-eip"
  })
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-nat"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-rt"
  })
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "api" {
  name        = "${var.project_name}-api-sg"
  description = "Public access for the API VM."
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH from the operator machine"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  ingress {
    description = "Public HTTP access for the assignment API"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-api-sg"
  })
}

resource "aws_security_group" "private" {
  name        = "${var.project_name}-private-sg"
  description = "Internal-only access for engine and worker VMs."
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Worker and engine communication inside the VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-sg"
  })
}

resource "aws_security_group_rule" "private_ssh_from_api" {
  type                     = "ingress"
  description              = "SSH from the API VM only"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.private.id
  source_security_group_id = aws_security_group.api.id
}

resource "aws_instance" "vm" {
  for_each = local.instances

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = each.key == "inference" ? var.inference_instance_type : var.instance_type
  key_name                    = var.ssh_key_name
  subnet_id                   = each.value.subnet == "public" ? aws_subnet.public.id : aws_subnet.private.id
  vpc_security_group_ids      = each.value.subnet == "public" ? [aws_security_group.api.id] : [aws_security_group.private.id]
  associate_public_ip_address = each.value.subnet == "public"
  private_ip                  = each.value.private_ip
  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/../deploy/user-data/${each.key}.sh.tftpl", {
    app_dir           = "/opt/iii-quickstart"
    engine_private_ip = local.instances.engine.private_ip
    repo_ref          = var.repo_ref
    repo_url          = var.repo_url
  })

  tags = merge(local.common_tags, {
    Name = each.value.name
    Role = each.key
  })
}
