# 노드 라벨 추가
resource "null_resource" "label_node" {
  depends_on = [null_resource.join_cluster]

  provisioner "local-exec" {
    command = <<-EOT
      # 임시 CA 인증서 파일 생성
      echo '${var.k8s_cluster_ca_certificate}' | base64 -d > /tmp/k8s-ca.crt
      
      # kubectl로 라벨 추가
      kubectl label nodes ${var.node_name} cloud-server=true --overwrite
      
      # 임시 파일 정리
      rm -f /tmp/k8s-ca.crt
    EOT
  }
}
