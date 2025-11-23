# Hermes

AWS 클라우드 서버에 새로운 노드를 생성하고 Kubernetes 클러스터에 통합하는 Terraform 프로젝트입니다.

## 개요

Hermes는 AWS EC2 인스턴스를 생성하고, 이를 Kubernetes 클러스터에 워커 노드로 추가하며, 클라우드 서버임을 나타내는 라벨을 자동으로 설정합니다. 이 라벨을 통해 특정 Pod들을 클라우드 노드에만 배치할 수 있습니다.

## 주요 기능

- AWS EC2 인스턴스 자동 생성
- Kubernetes 클러스터 자동 조인
- 클라우드 서버 라벨 자동 설정 (`cloud-server=true`)
- 추가 커스텀 라벨 지원

## 사전 요구사항

1. Terraform >= 1.0
2. AWS CLI 설정 및 자격 증명
3. Kubernetes 클러스터 접근 권한
4. `kubectl` 명령어 (로컬 환경)
5. Kubernetes 클러스터 조인 명령어 (kubeadm join 또는 EKS bootstrap 스크립트)

## 사용 방법

### 1. 변수 설정

`terraform.tfvars` 파일을 생성하여 필요한 변수들을 설정하세요:

```hcl
aws_region = "ap-northeast-2"
node_name  = "cloud-node-01"

instance_type = "t3.medium"
key_name      = "your-key-pair-name"
subnet_id     = "subnet-xxxxxxxxx"

# Kubernetes 클러스터 정보
k8s_cluster_endpoint       = "https://your-k8s-api-server:6443"
k8s_cluster_ca_certificate = "LS0tLS1CRUdJTi..." # base64 인코딩된 CA 인증서
k8s_cluster_token          = "your-k8s-token"
k8s_join_command           = "kubeadm join ..." # 또는 EKS bootstrap 스크립트

# 추가 라벨 (선택사항)
additional_labels = {
  "environment" = "production"
  "node-type"   = "compute"
}
```

### 2. Terraform 실행

```bash
# 초기화
terraform init

# 실행 계획 확인
terraform plan

# 적용
terraform apply
```

### 3. 노드 확인

노드가 클러스터에 추가되고 라벨이 설정되었는지 확인:

```bash
kubectl get nodes --show-labels
```

`cloud-server=true` 라벨이 설정된 노드를 확인할 수 있습니다.

## 변수 설명

### 필수 변수

- `node_name`: Kubernetes 노드 이름
- `key_name`: AWS EC2 Key Pair 이름
- `subnet_id`: EC2 인스턴스를 배치할 서브넷 ID
- `k8s_cluster_endpoint`: Kubernetes 클러스터 API 서버 엔드포인트
- `k8s_cluster_ca_certificate`: Kubernetes 클러스터 CA 인증서 (base64)
- `k8s_cluster_token`: Kubernetes 클러스터 인증 토큰
- `k8s_join_command`: Kubernetes 클러스터 조인 명령어

### 선택 변수

- `aws_region`: AWS 리전 (기본값: `ap-northeast-2`)
- `instance_type`: EC2 인스턴스 타입 (기본값: `t3.medium`)
- `security_group_ids`: 보안 그룹 ID 목록 (비어있으면 자동 생성)
- `cloud_label_key`: 클라우드 서버 라벨 키 (기본값: `cloud-server`)
- `cloud_label_value`: 클라우드 서버 라벨 값 (기본값: `true`)
- `additional_labels`: 추가 라벨 맵
- `tags`: EC2 인스턴스 태그

## 출력값

- `instance_id`: 생성된 EC2 인스턴스 ID
- `instance_private_ip`: EC2 인스턴스의 Private IP
- `instance_public_ip`: EC2 인스턴스의 Public IP (있는 경우)
- `node_name`: Kubernetes 노드 이름
- `node_labels`: 노드에 설정된 라벨

## Pod 배치 예시

클라우드 노드에만 Pod를 배치하려면 다음과 같이 nodeSelector를 사용하세요:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-cloud-pod
spec:
  nodeSelector:
    cloud-server: "true"
  containers:
  - name: app
    image: nginx
```

## 주의사항

1. Kubernetes 클러스터 조인 명령어는 클러스터 타입에 따라 다릅니다:
   - **kubeadm 클러스터**: `kubeadm join <control-plane>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>`
   - **EKS 클러스터**: EKS optimized AMI를 사용하고 bootstrap 스크립트를 실행해야 합니다.

2. 보안 그룹이 자동 생성되는 경우, 필요한 포트를 추가로 열어야 할 수 있습니다 (예: K8s API 서버 포트).

3. IAM 역할은 기본 권한만 포함되어 있습니다. 필요에 따라 추가 권한을 부여해야 할 수 있습니다.

## 라이선스

MIT

