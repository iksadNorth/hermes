# IAM 역할 및 정책 (K8s 클러스터 조인을 위한 권한)
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

# 보안 그룹 (기본 설정, 필요시 수정)
resource "aws_security_group" "k8s_node" {
  count = length(var.security_group_ids) == 0 ? 1 : 0

  name        = "hermes-k8s-node-${var.node_name}"
  description = "Security group for Hermes K8s node ${var.node_name}"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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

# EC2 인스턴스
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

resource "aws_instance" "k8s_node" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = length(var.security_group_ids) > 0 ? var.security_group_ids : [aws_security_group.k8s_node[0].id]
  iam_instance_profile   = aws_iam_instance_profile.k8s_node.name

  user_data = base64encode(templatefile("${path.module}/templates/join-cluster.sh.tpl", {
    k8s_join_command = var.k8s_join_command
    node_name        = var.node_name
    cloud_label_key  = var.cloud_label_key
    cloud_label_value = var.cloud_label_value
  }))

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

# 노드가 클러스터에 조인될 때까지 대기
resource "null_resource" "wait_for_node" {
  depends_on = [aws_instance.k8s_node]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for node ${var.node_name} to join the cluster..."
      timeout=300
      elapsed=0
      while [ $elapsed -lt $timeout ]; do
        if kubectl --server=${var.k8s_cluster_endpoint} \
          --token=${var.k8s_cluster_token} \
          --certificate-authority-data=${var.k8s_cluster_ca_certificate} \
          get nodes ${var.node_name} &>/dev/null; then
          echo "Node ${var.node_name} is ready!"
          exit 0
        fi
        echo "Waiting... ($elapsed/$timeout seconds)"
        sleep 10
        elapsed=$((elapsed + 10))
      done
      echo "Timeout waiting for node to join"
      exit 1
    EOT
  }

  triggers = {
    instance_id = aws_instance.k8s_node.id
  }
}

# Kubernetes 노드에 라벨 추가
resource "null_resource" "label_node" {
  depends_on = [null_resource.wait_for_node]

  provisioner "local-exec" {
    command = <<-EOT
      # 클라우드 서버 라벨 추가
      kubectl --server=${var.k8s_cluster_endpoint} \
        --token=${var.k8s_cluster_token} \
        --certificate-authority-data=${var.k8s_cluster_ca_certificate} \
        label nodes ${var.node_name} ${var.cloud_label_key}=${var.cloud_label_value} --overwrite

      # 추가 라벨 설정
      %{ for key, value in var.additional_labels ~}
      kubectl --server=${var.k8s_cluster_endpoint} \
        --token=${var.k8s_cluster_token} \
        --certificate-authority-data=${var.k8s_cluster_ca_certificate} \
        label nodes ${var.node_name} ${key}=${value} --overwrite
      %{ endfor ~}
    EOT
  }

  triggers = {
    node_name = var.node_name
    instance_id = aws_instance.k8s_node.id
  }
}

