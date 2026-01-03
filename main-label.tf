# 노드 라벨 및 Taint 추가
resource "null_resource" "label_node" {
  depends_on = [null_resource.join_cluster]

  provisioner "local-exec" {
    command = <<-EOT
      ssh -o StrictHostKeyChecking=no \
        -i "${var.k8s_control_plane_ssh_key}" \
        "${var.k8s_control_plane_ssh_user}@${var.k8s_control_plane_ssh_host}" \
        "kubectl label nodes ${var.node_name} cloud-server=true --overwrite && \
         kubectl taint nodes ${var.node_name} cloud-server=true:NoSchedule --overwrite"
    EOT
  }
}