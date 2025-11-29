# ============================================================================
# Kubernetes 클러스터 조인
# ============================================================================
# 이 파일은 EC2 인스턴스가 Kubernetes 클러스터에 조인하는 것을 담당합니다.
# SSH를 통해 원격으로 join-cluster.sh 스크립트를 실행하고,
# 노드가 클러스터에 등록될 때까지 대기합니다.

# 스크립트 파일 읽기
locals {
  join_cluster_script = file("${path.module}/scripts/join-cluster.sh")
  
  # SSH 접속 정보
  ssh_user = "ubuntu"
  ssh_host = aws_instance.k8s_node.public_ip != "" ? aws_instance.k8s_node.public_ip : aws_instance.k8s_node.private_ip
}

# 인스턴스가 SSH 접속 가능할 때까지 대기
resource "null_resource" "wait_for_ssh" {
  depends_on = [aws_instance.k8s_node]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for SSH to be available on ${local.ssh_host}..."
      timeout=300
      elapsed=0
      while [ $elapsed -lt $timeout ]; do
        if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          -i ${var.ssh_private_key_path} \
          ${local.ssh_user}@${local.ssh_host} \
          "echo 'SSH connection successful'" &>/dev/null; then
          echo "SSH is ready!"
          exit 0
        fi
        echo "Waiting for SSH... ($elapsed/$timeout seconds)"
        sleep 5
        elapsed=$((elapsed + 5))
      done
      echo "Timeout waiting for SSH"
      exit 1
    EOT
  }

  triggers = {
    instance_id = aws_instance.k8s_node.id
  }
}

# 클러스터 조인 스크립트를 원격으로 실행
resource "null_resource" "join_cluster" {
  depends_on = [null_resource.wait_for_ssh]

  provisioner "local-exec" {
    command = <<-EOT
      # 스크립트를 임시 파일로 생성
      SCRIPT_FILE=$(mktemp)
      cat > "$SCRIPT_FILE" <<'SCRIPT_EOF'
${local.join_cluster_script}
SCRIPT_EOF
      
      # 스크립트를 원격 서버로 전송하고 실행
      scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -i ${var.ssh_private_key_path} \
        "$SCRIPT_FILE" ${local.ssh_user}@${local.ssh_host}:/tmp/join-cluster.sh
      
      ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -i ${var.ssh_private_key_path} \
        ${local.ssh_user}@${local.ssh_host} \
        "chmod +x /tmp/join-cluster.sh && \
         export NODE_NAME='${var.node_name}' && \
         export K8S_JOIN_COMMAND='${var.k8s_join_command}' && \
         export K8S_CLUSTER_ENDPOINT='${var.k8s_cluster_endpoint}' && \
         export K8S_CLUSTER_TOKEN='${var.k8s_cluster_token}' && \
         export K8S_CLUSTER_CA_CERT='${var.k8s_cluster_ca_certificate}' && \
         export TIMEOUT='300' && \
         /tmp/join-cluster.sh"
      
      rm -f "$SCRIPT_FILE"
    EOT
  }

  triggers = {
    instance_id = aws_instance.k8s_node.id
    join_script = md5(local.join_cluster_script)
  }
}

