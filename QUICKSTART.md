# 빠른 시작 가이드

## 사전 요구사항

1. **Terraform 설치** (>= 1.0)
2. **AWS CLI 설정** 및 자격 증명
3. **kubectl 설치** (로컬 환경)
4. **SSH 키** (EC2 접근용)

## 실행 단계

### 1. 변수 설정

`terraform.tfvars` 파일을 생성하고 필요한 값들을 설정하세요:

```bash
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars 파일을 편집하여 실제 값 입력
```

**필수 변수:**
- `node_name`: 노드 이름
- `key_name`: AWS Key Pair 이름
- `subnet_id`: 서브넷 ID
- `k8s_cluster_endpoint`: K8s API 서버 주소
- `k8s_cluster_ca_certificate`: CA 인증서 (base64)
- `k8s_cluster_token`: 인증 토큰
- `k8s_join_command`: 조인 명령어

**SSH 키 경로 확인:**
- `ssh_private_key_path`가 올바른지 확인 (기본값: `~/.ssh/id_rsa`)
- Key Pair 이름과 SSH 키 파일이 일치하는지 확인

### 2. Terraform 초기화

```bash
terraform init
```

### 3. 실행 계획 확인

```bash
terraform plan
```

### 4. 실행

```bash
terraform apply
```

## 문제 해결

### SSH 접속 실패
- `ssh_private_key_path`가 올바른지 확인
- 보안 그룹이 SSH(22번 포트)를 허용하는지 확인
- 인스턴스가 Public IP를 가지고 있는지 확인 (Private IP만 있으면 VPN/Bastion 필요)

### 클러스터 조인 실패
- `k8s_join_command`가 올바른지 확인
- 클러스터 토큰이 유효한지 확인
- 네트워크 연결 확인 (인스턴스에서 클러스터 API 서버 접근 가능해야 함)

### 노드 라벨 추가 실패
- `kubectl`이 로컬에 설치되어 있는지 확인
- K8s 클러스터 인증 정보가 올바른지 확인

