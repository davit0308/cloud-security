# =============================================================================
# SẢN PHẨM ĐÚC RA TỪ AEGIS PORTAL - DIRECT INJECTION
# DỰ ÁN : AWS INFRASTRUCTURE
# =============================================================================

provider "aws" {
  region = "ap-southeast-1"
}

# ── VPC ───────────────────────────────────────────────────────────────────────
resource "aws_vpc" "aws_hybrid_vpc" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "aegis-vpc"
    Environment = "staging"
    ManagedBy   = "Aegis-Portal-Terraform"
  }
}

# ── SUBNET ────────────────────────────────────────────────────────────────────
resource "aws_subnet" "aws_public_subnet" {
  vpc_id                  = aws_vpc.aws_hybrid_vpc.id
  cidr_block              = "10.10.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name        = "aegis-public-subnet"
    Environment = "staging"
  }
}

# ── INTERNET GATEWAY ──────────────────────────────────────────────────────────
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.aws_hybrid_vpc.id

  tags = {
    Name = "aegis-igw"
  }
}

# ── SECURITY GROUP ────────────────────────────────────────────────────────────
resource "aws_security_group" "app_sg" {
  name        = "aegis-app-sg"
  description = "Security Group for aegis (staging)"
  vpc_id      = aws_vpc.aws_hybrid_vpc.id

  dynamic "ingress" {
    for_each = [80,443,22,8080]
    content {
      description = "Port ${ingress.value} opened via Aegis Portal"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name        = "aegis-app-sg"
    Environment = "staging"
  }
}

# ── EC2 INSTANCE ──────────────────────────────────────────────────────────────
resource "aws_instance" "app_node" {
  ami                    = data.aws_ami.ubuntu_24.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.aws_public_subnet.id
  vpc_security_group_ids = [aws_security_group.app_sg.id]

  ebs_block_device {
    device_name = "/dev/sdb"
    volume_size = 20
    encrypted   = true

    tags = {
      Name = "aegis-data-disk"
    }
  }

  iam_instance_profile = null

  tags = {
    Name        = "aegis-ec2"
    Environment = "staging"
    ManagedBy   = "Aegis-Portal-Terraform"
  }
}

# ── IAM INSTANCE PROFILE ──────────────────────────────────────────────────────
resource "aws_iam_role" "ec2_admin_role" {
  count = 0
  name  = "aegis-ec2-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Environment       = "staging"
    AegisSecurityNote = "AdminRoleAttached-ReviewRequired"
  }
}

resource "aws_iam_role_policy_attachment" "admin_attach" {
  count = 0
  role       = aws_iam_role.ec2_admin_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_instance_profile" "admin_profile" {
  count = 0
  name  = "aegis-admin-profile"
  role  = aws_iam_role.ec2_admin_role[0].name
}

# ── OUTPUTS ───────────────────────────────────────────────────────────────────
output "vpc_id" { value = aws_vpc.aws_hybrid_vpc.id }
output "instance_id" { value = aws_instance.app_node.id }
output "security_group_id" { value = aws_security_group.app_sg.id }
data "aws_ami" "ubuntu_24" {
  most_recent = true
  owners      = ["099720109477"] # ID tài khoản chính thức của Canonical (nhà phát triển Ubuntu)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
