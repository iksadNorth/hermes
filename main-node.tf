# SSH 키 자동 생성
resource "tls_private_key" "hermes" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# AWS Key Pair 생성
resource "aws_key_pair" "hermes" {
  key_name   = var.key_name != "" ? var.key_name : "hermes-${var.node_name}"
  public_key = tls_private_key.hermes.public_key_openssh

  tags = {
    Name = "hermes-${var.node_name}"
  }
}

# Private Key를 로컬 파일로 저장
resource "local_file" "private_key" {
  content         = tls_private_key.hermes.private_key_pem
  filename        = "${path.module}/.ssh/hermes-${var.node_name}.pem"
  file_permission = "0600"
}

resource "aws_security_group" "k8s_node" {
  name   = "hermes-k8s-node-${var.node_name}"
  vpc_id = aws_vpc.hermes.id

  # SSH 접근 (개발자 로컬 IP만)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.developer_local_ip]
    description = "SSH access from developer local IP"
  }

  # Kubernetes API 서버 (TCP 6443) - 노드 간 통신
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.hermes.cidr_block]
    description = "Kubernetes API server"
  }

  # Kubelet API (TCP 10250) - 노드 간 통신
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.hermes.cidr_block]
    description = "Kubelet API"
  }

  # Pod 간 통신 (UDP 8472) - Flannel VXLAN
  ingress {
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    cidr_blocks = [aws_vpc.hermes.cidr_block]
    description = "Pod-to-Pod communication (Flannel VXLAN)"
  }

  # 아웃바운드: Kubernetes API 서버 (TCP 6443)
  egress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.hermes.cidr_block]
    description = "Kubernetes API server outbound"
  }

  # 아웃바운드: Kubelet API (TCP 10250)
  egress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.hermes.cidr_block]
    description = "Kubelet API outbound"
  }

  # 아웃바운드: Pod 간 통신 (UDP 8472)
  egress {
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    cidr_blocks = [aws_vpc.hermes.cidr_block]
    description = "Pod-to-Pod communication outbound (Flannel VXLAN)"
  }

  # 아웃바운드: HTTPS (443) - 이미지 다운로드, API 호출 등
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS outbound for image pulls and API calls"
  }

  # 아웃바운드: HTTP (80) - 패키지 다운로드 등
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP outbound for package downloads"
  }

  # 아웃바운드: DNS (UDP 53)
  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "DNS outbound"
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/*/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_instance" "k8s_node" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.hermes.key_name
  subnet_id              = var.subnet_id != "" ? var.subnet_id : aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.k8s_node.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    export NODE_NAME="${var.node_name}"
    export K8S_API_SERVER_DOMAIN="${var.k8s_api_server_domain}"
    export K8S_API_SERVER_IP="${var.k8s_api_server_ip}"
    ${file("${path.module}/scripts/init-node.sh")}
  EOF
  )
}
