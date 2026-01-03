# Kubernetes 클러스터 조인
locals {
  ssh_host = aws_instance.k8s_node.public_ip != "" ? aws_instance.k8s_node.public_ip : aws_instance.k8s_node.private_ip
}

resource "null_resource" "wait_for_ssh" {
  depends_on = [aws_instance.k8s_node]

  provisioner "local-exec" {
    command = <<-EOT
      for i in {1..60}; do
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
          -i ${local_file.private_key.filename} \
          ubuntu@${local.ssh_host} "echo ok" && exit 0
        sleep 5
      done
      exit 1
    EOT
  }
}

resource "null_resource" "join_cluster" {
  depends_on = [null_resource.wait_for_ssh]

  provisioner "local-exec" {
    command = <<-EOT
      scp -o StrictHostKeyChecking=no -i ${local_file.private_key.filename} \
        ${path.module}/scripts/join-cluster.sh ubuntu@${local.ssh_host}:/tmp/
      
      ssh -o StrictHostKeyChecking=no -i ${local_file.private_key.filename} \
        ubuntu@${local.ssh_host} \
        "chmod +x /tmp/join-cluster.sh && \
         NODE_NAME='${var.node_name}' \
         K8S_JOIN_COMMAND='${local.k8s_join_command}' \
         K8S_CLUSTER_ENDPOINT='${var.k8s_cluster_endpoint}' \
         K8S_CLUSTER_TOKEN='${var.k8s_cluster_token != "" ? var.k8s_cluster_token : ""}' \
         K8S_CLUSTER_CA_CERT='${var.k8s_cluster_ca_certificate}' \
         K8S_API_SERVER_DOMAIN='${var.k8s_api_server_domain}' \
         K8S_API_SERVER_IP='${var.k8s_api_server_ip}' \
         /tmp/join-cluster.sh"
    EOT
  }
}
