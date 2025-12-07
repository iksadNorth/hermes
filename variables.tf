variable "node_name" {
  description = "K8s 노드 이름"
  type        = string
}

variable "key_name" {
  description = "AWS EC2 Key Pair 이름 (비어있으면 자동 생성)"
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "EC2 인스턴스를 배치할 서브넷 ID (비어있으면 자동 생성된 public 서브넷 사용)"
  type        = string
  default     = ""
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
  description = "Kubernetes 클러스터 조인 명령어"
  type        = string
  sensitive   = true
}


variable "k8s_api_server_domain" {
  description = "Kubernetes API 서버 도메인 (예: main-node.me)"
  type        = string
  default     = ""
}

variable "k8s_api_server_ip" {
  description = "Kubernetes API 서버 공인 IP (도메인 매핑용)"
  type        = string
  default     = ""
}

variable "developer_local_ip" {
  description = "개발자 로컬 IP 주소 (CIDR 형식, 예: 1.2.3.4/32)"
  type        = string
}

variable "k8s_control_plane_ssh_host" {
  description = "Control Plane 서버 SSH 호스트"
  type        = string
  default     = "main-node.me"
}

variable "k8s_control_plane_ssh_user" {
  description = "Control Plane 서버 SSH 사용자명 (기본값: root 또는 ubuntu)"
  type        = string
  default     = "root"
}

variable "k8s_control_plane_ssh_key" {
  description = "Control Plane 서버 SSH 키 파일 경로 (선택사항, 비어있으면 password 인증 또는 기본 키 사용)"
  type        = string
  default     = ""
}
