output "instance_id" {
  description = "생성된 EC2 인스턴스 ID"
  value       = aws_instance.k8s_node.id
}

output "instance_private_ip" {
  description = "EC2 인스턴스의 Private IP 주소"
  value       = aws_instance.k8s_node.private_ip
}

output "instance_public_ip" {
  description = "EC2 인스턴스의 Public IP 주소 (있는 경우)"
  value       = aws_instance.k8s_node.public_ip
}

output "node_name" {
  description = "Kubernetes 노드 이름"
  value       = var.node_name
}

output "node_labels" {
  description = "노드에 설정된 라벨"
  value = merge(
    {
      (var.cloud_label_key) = var.cloud_label_value
    },
    var.additional_labels
  )
}

