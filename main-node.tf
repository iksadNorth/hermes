# ============================================================================
# AWS EC2 노드 생성
# ============================================================================
# 이 파일은 AWS EC2 인스턴스 생성만 담당합니다.
# IAM 역할, 보안 그룹, EC2 인스턴스 리소스를 관리합니다.

# IAM 역할 및 정책
data "aws_iam_policy_document" "node_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "k8s_node" {
  name = "hermes-k8s-node-${var.node_name}"

  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json

  tags = merge(
    var.tags,
    {
      Name = "hermes-k8s-node-${var.node_name}"
    }
  )
}

resource "aws_iam_instance_profile" "k8s_node" {
  name = "hermes-k8s-node-${var.node_name}"
  role = aws_iam_role.k8s_node.name
}

# Terraform 실행 노드의 현재 공인 IP 가져오기
data "http" "current_ip" {
  url = "https://ifconfig.me"
  
  request_headers = {
    Accept = "text/plain"
  }
}

# 보안 그룹 (기본 설정, 필요시 수정)
resource "aws_security_group" "k8s_node" {
  count = length(var.security_group_ids) == 0 ? 1 : 0

  name        = "hermes-k8s-node-${var.node_name}"
  description = "Security group for Hermes K8s node ${var.node_name}"

  ingress {
    description = "SSH from Terraform execution node"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr != "" ? var.allowed_ssh_cidr : "${chomp(data.http.current_ip.response_body)}/32"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "hermes-k8s-node-${var.node_name}"
    }
  )
}

# Ubuntu AMI 조회
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hub/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# 초기화 스크립트 읽기 (최소한의 초기화만 수행)
locals {
  init_node_script = file("${path.module}/scripts/init-node.sh")
  user_data_script = <<-EOF
#!/bin/bash
export NODE_NAME="${var.node_name}"
${local.init_node_script}
EOF
}

# EC2 인스턴스
resource "aws_instance" "k8s_node" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = length(var.security_group_ids) > 0 ? var.security_group_ids : [aws_security_group.k8s_node[0].id]
  iam_instance_profile   = aws_iam_instance_profile.k8s_node.name

  user_data = base64encode(local.user_data_script)

  tags = merge(
    var.tags,
    {
      Name        = "hermes-k8s-node-${var.node_name}"
      "kubernetes.io/cluster/${var.node_name}" = "owned"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

