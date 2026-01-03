output "instance_id" {
  value = aws_instance.k8s_node.id
}

output "node_name" {
  value = var.node_name
}

output "vpc_id" {
  value = aws_vpc.hermes.id
}

output "vpc_cidr" {
  value = aws_vpc.hermes.cidr_block
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "ssh_private_key_path" {
  description = "생성된 SSH private key 파일 경로"
  value       = local_file.private_key.filename
  sensitive   = false
}

output "ssh_key_name" {
  description = "AWS Key Pair 이름"
  value       = aws_key_pair.hermes.key_name
}

output "k8s_join_command" {
  description = "Kubernetes 클러스터 조인 명령어 (자동 생성 또는 terraform.tfvars에서 가져옴)"
  value       = local.k8s_join_command
  sensitive   = true
}
