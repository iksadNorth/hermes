# ============================================================================
# 노드 라벨 추가
# ============================================================================
# 이 파일은 Kubernetes 노드에 클라우드 서버 라벨을 추가하는 것을 담당합니다.
# 클라우드 서버임을 나타내는 라벨과 추가 커스텀 라벨을 설정합니다.

# label-node.sh 스크립트 읽기
locals {
  label_node_script = file("${path.module}/scripts/label-node.sh")
  
  # 추가 라벨을 쉼표로 구분된 문자열로 변환
  additional_labels_string = join(",", [
    for key, value in var.additional_labels : "${key}=${value}"
  ])
}

# Kubernetes 노드에 라벨 추가
resource "null_resource" "label_node" {
  depends_on = [null_resource.join_cluster]

  provisioner "local-exec" {
    command = <<-EOT
      export NODE_NAME="${var.node_name}"
      export K8S_CLUSTER_ENDPOINT="${var.k8s_cluster_endpoint}"
      export K8S_CLUSTER_TOKEN="${var.k8s_cluster_token}"
      export K8S_CLUSTER_CA_CERT="${var.k8s_cluster_ca_certificate}"
      export CLOUD_LABEL_KEY="${var.cloud_label_key}"
      export CLOUD_LABEL_VALUE="${var.cloud_label_value}"
      export ADDITIONAL_LABELS="${local.additional_labels_string}"
      ${local.label_node_script}
    EOT
  }

  triggers = {
    node_name   = var.node_name
    instance_id = aws_instance.k8s_node.id
    cloud_label = "${var.cloud_label_key}=${var.cloud_label_value}"
    additional_labels = jsonencode(var.additional_labels)
  }
}

