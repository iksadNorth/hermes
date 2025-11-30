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
