# Kubernetes 클러스터 구성 가이드

## 단계 1: 온프레미스에 Control Plane 구성

### 1-1. Control Plane 노드 준비

온프레미스 서버에서 다음을 실행합니다:

```bash
# Kubernetes 설치 (kubeadm, kubelet, kubectl)
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

### 1-2. Control Plane 초기화

```bash
# Control Plane 초기화 (온프레미스 서버 IP 사용)
sudo kubeadm init \
  --apiserver-advertise-address=<온프레미스_서버_IP> \
  --pod-network-cidr=10.244.0.0/16 \
  --control-plane-endpoint=<온프레미스_서버_IP>:6443

# 출력 예시:
# kubeadm join <온프레미스_서버_IP>:6443 --token <토큰> \
#   --discovery-token-ca-cert-hash sha256:<해시값>
```

**중요**: 출력된 `kubeadm join` 명령어를 복사해두세요!

### 1-3. kubeconfig 설정

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### 1-4. CNI 네트워크 플러그인 설치 (Flannel 예시)

```bash
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

### 1-4-1. Control Plane 노드를 워커 노드로도 사용하기 (선택사항)

기본적으로 Control Plane 노드는 taint가 있어서 일반 Pod가 스케줄링되지 않습니다. Control Plane 노드도 워커 노드로 사용하려면 taint를 제거하세요:

```bash
# 1단계: 현재 taint 확인
kubectl describe node <노드이름> | grep Taints

# 출력 예시:
# - Taints: node-role.kubernetes.io/control-plane:NoSchedule (taint가 있음)
# - Taints: <none> (taint가 없음, 이미 워커 노드로 사용 가능)

# 2단계: taint 제거 (taint가 있는 경우만)
# Kubernetes 1.24+ 버전
kubectl taint nodes <노드이름> node-role.kubernetes.io/control-plane:NoSchedule-

# 또는 구버전 Kubernetes (1.23 이하)
kubectl taint nodes <노드이름> node-role.kubernetes.io/master:NoSchedule-

# 3단계: 확인
kubectl describe node <노드이름> | grep Taints
# 출력: Taints: <none> (또는 아무것도 없음)

# 4단계: 테스트 (Pod가 스케줄링되는지 확인)
kubectl run test-pod --image=nginx --restart=Never
kubectl get pod test-pod -o wide
kubectl delete pod test-pod
```

**참고:**
- "taint not found" 에러가 발생하면 이미 taint가 없는 상태입니다
- 이 경우 노드는 이미 워커 노드로 사용 가능합니다

**주의사항:**
- Control Plane 노드에 워크로드를 실행하면 리소스 경합이 발생할 수 있습니다
- 프로덕션 환경에서는 Control Plane과 워커 노드를 분리하는 것을 권장합니다
- 테스트 환경이나 리소스가 제한적인 경우에만 사용하세요

### 1-5. Control Plane 정보 확인

```bash
# 클러스터 상태 확인
kubectl get nodes

# API 서버 정보 확인
kubectl cluster-info

# CA 인증서 추출 (base64)
cat /etc/kubernetes/pki/ca.crt | base64 -w 0

# 토큰 생성 (만료된 경우)
kubeadm token create --print-join-command
```

---

## 단계 2: Terraform으로 클라우드 서버 Join

### 2-1. Terraform 변수 설정

`terraform.tfvars` 파일에 다음 정보를 입력합니다:

```hcl
node_name = "cloud-node-01"
key_name  = "your-key-pair-name"

# 단계 1에서 얻은 정보들
k8s_cluster_endpoint = "https://<온프레미스_서버_IP>:6443"
k8s_cluster_ca_certificate = "<단계1-5에서_추출한_base64_인증서>"
k8s_cluster_token = "<단계1-2에서_얻은_토큰>"
k8s_join_command = "kubeadm join <온프레미스_서버_IP>:6443 --token <토큰> --discovery-token-ca-cert-hash sha256:<해시값>"
```

### 2-2. Terraform 실행

```bash
# 1단계: VPC와 EC2 노드 생성
terraform apply -target=aws_vpc.hermes -target=aws_instance.k8s_node

# 2단계: K8s 조인 (파일명 변경 후)
mv main-k8sjoin_tf main-k8sjoin.tf
terraform apply -target=null_resource.join_cluster

# 3단계: 라벨 추가 (선택사항)
mv main-label_tf main-label.tf
terraform apply -target=null_resource.label_node
```

### 2-3. 노드 조인 확인

온프레미스 Control Plane에서:

```bash
kubectl get nodes
kubectl get nodes --show-labels
```

`cloud-server=true` 라벨이 있는 노드를 확인할 수 있습니다.

---

## 문제 해결

### 토큰 만료 시

```bash
# 새 토큰 생성
kubeadm token create --print-join-command

# 출력된 명령어를 k8s_join_command에 업데이트
```

### 네트워크 연결 문제

- 온프레미스와 클라우드 간 네트워크 연결 확인
- 보안 그룹에서 필요한 포트(6443, 10250 등) 허용 확인
- VPN/Direct Connect 설정 확인

### 노드가 Ready 상태가 아닐 때

```bash
# 클라우드 노드에서 확인
sudo systemctl status kubelet
sudo journalctl -xeu kubelet

# Control Plane에서 확인
kubectl describe node <노드이름>
```

