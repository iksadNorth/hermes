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

  # 인바운드: 모든 트래픽 허용
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all inbound traffic"
  }

  # 아웃바운드: 모든 트래픽 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
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
