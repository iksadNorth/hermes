variable "aws_region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "node_name" {
  description = "K8s 노드 이름"
  type        = string
}

variable "instance_type" {
  description = "EC2 인스턴스 타입"
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "AWS EC2 Key Pair 이름"
  type        = string
}

variable "subnet_id" {
  description = "EC2 인스턴스를 배치할 서브넷 ID"
  type        = string
}

variable "security_group_ids" {
  description = "EC2 인스턴스에 적용할 보안 그룹 ID 목록"
  type        = list(string)
  default     = []
}

variable "k8s_cluster_endpoint" {
  description = "Kubernetes 클러스터 API 서버 엔드포인트"
  type        = string
}

variable "k8s_cluster_ca_certificate" {
  description = "Kubernetes 클러스터 CA 인증서 (base64 인코딩)"
  type        = string
  sensitive   = true
}

variable "k8s_cluster_token" {
  description = "Kubernetes 클러스터 인증 토큰"
  type        = string
  sensitive   = true
}

variable "k8s_join_command" {
  description = "Kubernetes 클러스터 조인 명령어 (kubeadm join 또는 EKS bootstrap 스크립트)"
  type        = string
  sensitive   = true
}

variable "cloud_label_key" {
  description = "클라우드 서버를 나타내는 라벨 키"
  type        = string
  default     = "cloud-server"
}

variable "cloud_label_value" {
  description = "클라우드 서버를 나타내는 라벨 값"
  type        = string
  default     = "true"
}

variable "additional_labels" {
  description = "추가로 설정할 노드 라벨 (key-value 맵)"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "EC2 인스턴스에 추가할 태그"
  type        = map(string)
  default     = {}
}

