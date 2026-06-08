# ==============================================================================
# SẢN PHẨM CỦA: IaC Generator
# MỤC TIÊU: Triển khai Hybrid Cloud (AWS + OpenStack)
# TRẠNG THÁI: ⚠️ CHỨA CÁC LỖ HỔNG BẢO MẬT CỐ Ý ĐỂ TEST PIPELINE ⚠️
# ==============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.50"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
}

provider "openstack" {
  auth_url    = "http://your-openstack-keystone-url:5000/v3"
  region      = "RegionOne"
}

# ------------------------------------------------------------------------------
# 2. PUBLIC CLOUD (AWS)
# ------------------------------------------------------------------------------
resource "aws_vpc" "aws_hybrid_vpc" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "AWS-Hybrid-VPC"
    Environment = "Production"
  }
}

resource "aws_subnet" "aws_public_subnet" {
  vpc_id                  = aws_vpc.aws_hybrid_vpc.id
  cidr_block              = "10.10.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "AWS-Public-Subnet"
  }
}

resource "aws_security_group" "aws_web_sg" {
  name        = "aws-web-sg"
  description = "Security Group cho Web Server tren AWS"
  vpc_id      = aws_vpc.aws_hybrid_vpc.id

  # ❌ LỖI CỐ Ý 1: Mở toang cổng SSH (22) cho toàn Internet (0.0.0.0/0). 
  # Checkov sẽ báo lỗi CKV_AWS_24.
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]  # AUTO-FIXED: restrict SSH — replace with actual trusted CIDR
  }

  # ❌ LỖI CỐ Ý 2: Mở toang cổng RDP (3389) cho toàn Internet.
  # Checkov sẽ báo lỗi CKV_AWS_252.
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
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
}

resource "aws_instance" "aws_frontend_node" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.aws_public_subnet.id
  vpc_security_group_ids = [aws_security_group.aws_web_sg.id]

  # ❌ LỖI CỐ Ý 3: Cấp phát Public IP trực tiếp cho máy ảo (Không qua Load Balancer/NAT).
  associate_public_ip_address = true

  tags = {
    Name = "AWS-Frontend-Node"
    Role = "Web"
  }
}

# ------------------------------------------------------------------------------
# 3. PRIVATE CLOUD (OPENSTACK)
# ------------------------------------------------------------------------------
resource "openstack_networking_network_v2" "os_internal_net" {
  name           = "os-internal-network"
  admin_state_up = "true"
}

resource "openstack_networking_subnet_v2" "os_internal_subnet" {
  name       = "os-internal-subnet"
  network_id = openstack_networking_network_v2.os_internal_net.id
  cidr       = "192.168.10.0/24"
  ip_version = 4
}

resource "openstack_compute_secgroup_v2" "os_db_sg" {
  name        = "os-db-sg"
  description = "Security Group cho Database Node tren OpenStack"

  rule {
    from_port   = 3306
    to_port     = 3306
    ip_protocol = "tcp"
    cidr        = "10.10.0.0/16" 
  }

  # ❌ LỖI CỐ Ý 4: Mở cổng SSH (22) Database cho toàn bộ mạng thay vì chỉ cho Bastion Host.
  rule {
    from_port   = 22
    to_port     = 22
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0" 
  }
}

resource "openstack_compute_instance_v2" "os_backend_db" {
  name            = "OS-Backend-DB"
  image_name      = "Ubuntu-22.04"
  flavor_name     = "m1.medium"
  security_groups = [openstack_compute_secgroup_v2.os_db_sg.name]

  network {
    name = openstack_networking_network_v2.os_internal_net.name
  }
}