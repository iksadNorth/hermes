# AWS EC2 노드 생성
data "http" "current_ip" {
  url = "https://ifconfig.me"
  request_headers = { Accept = "text/plain" }
}

resource "aws_security_group" "k8s_node" {
  name   = "hermes-k8s-node-${var.node_name}"
  vpc_id = aws_vpc.hermes.id

  # SSH 접근 (Terraform 실행 노드만)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.current_ip.response_body)}/32"]
  }

  # 온프레미스에서 클라우드 노드로 접근 (192.168.45.0/24)
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["192.168.45.0/24"]
    description = "온프레미스에서 클라우드 노드로 접근"
  }

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = ["192.168.45.0/24"]
    description = "온프레미스에서 클라우드 노드로 접근"
  }

  # Kubelet API (노드 간 통신)
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    self        = true
  }

  # Kube-proxy health check
  ingress {
    from_port   = 10259
    to_port     = 10259
    protocol    = "tcp"
    self        = true
  }

  # NodePort 서비스 (30000-32767)
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.hermes.cidr_block]
  }

  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "udp"
    cidr_blocks = [aws_vpc.hermes.cidr_block]
  }

  # Pod-to-Pod 통신 (VPC 내부 모든 포트)
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.hermes.cidr_block]
  }

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = [aws_vpc.hermes.cidr_block]
  }

  # 모든 아웃바운드 허용 (API 서버, 이미지 다운로드 등)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hub/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_instance" "k8s_node" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  key_name               = var.key_name
  subnet_id              = var.subnet_id != "" ? var.subnet_id : aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.k8s_node.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    export NODE_NAME="${var.node_name}"
    ${file("${path.module}/scripts/init-node.sh")}
  EOF
  )
}
