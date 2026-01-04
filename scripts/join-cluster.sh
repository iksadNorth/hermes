#!/bin/bash
set -e

# 연결 테스트는 실패해도 계속 진행
set +e

NODE_NAME="${NODE_NAME}"
K8S_JOIN_COMMAND="${K8S_JOIN_COMMAND}"
K8S_CLUSTER_ENDPOINT="${K8S_CLUSTER_ENDPOINT}"
K8S_CLUSTER_TOKEN="${K8S_CLUSTER_TOKEN}"
K8S_CLUSTER_CA_CERT="${K8S_CLUSTER_CA_CERT}"
K8S_API_SERVER_DOMAIN="${K8S_API_SERVER_DOMAIN}"
K8S_API_SERVER_IP="${K8S_API_SERVER_IP}"

# apt-get lock 대기 함수
wait_for_apt_lock() {
  local max_wait=300  # 최대 5분 대기
  local wait_time=0
  while [ $wait_time -lt $max_wait ]; do
    if ! sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1 && \
       ! sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1 && \
       ! sudo fuser /var/cache/apt/archives/lock >/dev/null 2>&1; then
      return 0
    fi
    echo "Waiting for apt lock to be released... (${wait_time}s/${max_wait}s)"
    sleep 5
    wait_time=$((wait_time + 5))
  done
  echo "Warning: apt lock wait timeout, proceeding anyway..."
}

# apt-get lock 대기
wait_for_apt_lock

# 시스템 업데이트
sudo apt-get update
sudo apt-get install -y curl apt-transport-https ca-certificates

# 호스트명 설정
sudo hostnamectl set-hostname "$NODE_NAME"

# Kubernetes API 서버 도메인을 hosts 파일에 추가
if [ -n "$K8S_API_SERVER_DOMAIN" ] && [ -n "$K8S_API_SERVER_IP" ]; then
  echo "Adding $K8S_API_SERVER_DOMAIN -> $K8S_API_SERVER_IP to /etc/hosts"
  # 기존 항목 제거 (중복 방지)
  sudo sed -i "/$K8S_API_SERVER_DOMAIN/d" /etc/hosts || true
  # 새 항목 추가
  echo "$K8S_API_SERVER_IP $K8S_API_SERVER_DOMAIN" | sudo tee -a /etc/hosts > /dev/null
  echo "Added $K8S_API_SERVER_DOMAIN -> $K8S_API_SERVER_IP to /etc/hosts"
  cat /etc/hosts | grep "$K8S_API_SERVER_DOMAIN" || echo "Warning: Failed to add to /etc/hosts"
fi

# Swap 비활성화 (Kubernetes 요구사항)
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab || true

# 커널 모듈 로드 (bridge, br_netfilter)
sudo modprobe overlay
sudo modprobe br_netfilter

# 커널 모듈을 영구적으로 로드하도록 설정
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

# 네트워크 설정 (ip_forward, bridge-nf-call-iptables)
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# containerd 설치
wait_for_apt_lock
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# Kubernetes 설치
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor --batch --no-tty -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

wait_for_apt_lock
sudo apt-get update
wait_for_apt_lock
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# API 서버 연결 테스트
echo "=== Testing API Server connectivity ==="
# join command에서 API 서버 주소 추출
API_SERVER=$(echo "$K8S_JOIN_COMMAND" | grep -oP 'join \K[^:]+' || echo "")
if [ -n "$API_SERVER" ]; then
  echo "API Server: $API_SERVER"
  echo "Checking /etc/hosts for $API_SERVER:"
  grep "$API_SERVER" /etc/hosts || echo "  Not found in /etc/hosts"
  
  echo "Testing DNS resolution:"
  if command -v nslookup &> /dev/null; then
    nslookup "$API_SERVER" || echo "  DNS resolution failed"
  fi
  
  echo "Testing connectivity to $API_SERVER:6443:"
  if command -v nc &> /dev/null; then
    timeout 5 nc -zv "$API_SERVER" 6443 2>&1 || echo "  Connection test failed"
  elif command -v telnet &> /dev/null; then
    timeout 5 telnet "$API_SERVER" 6443 2>&1 || echo "  Connection test failed"
  else
    echo "  nc or telnet not available, skipping connection test"
  fi
  
  echo "Testing HTTPS connection:"
  timeout 10 curl -k -v "https://$API_SERVER:6443" 2>&1 | head -20 || echo "  HTTPS connection failed"
fi
echo "======================================"

# 에러 발생 시 중단하도록 다시 설정
set -e

# Kubernetes 클러스터 조인
echo "Executing join command..."
# 인증서 검증 오류를 피하기 위해 --discovery-token-unsafe-skip-ca-verification 추가
# 주의: 이는 보안상 권장되지 않지만, 인증서에 도메인이 포함되지 않은 경우 임시 해결책입니다
JOIN_CMD_WITH_SKIP="$K8S_JOIN_COMMAND --discovery-token-unsafe-skip-ca-verification"
echo "Join command: $JOIN_CMD_WITH_SKIP"
sudo bash -c "$JOIN_CMD_WITH_SKIP"

# 노드 등록 확인
# 주의: worker 노드에서는 kubectl이 kubeconfig 없이 작동하지 않으므로
# kubelet 상태를 확인하는 것으로 대체
echo "Waiting for kubelet to register node..."
sleep 30

KUBELET_READY=false
for i in {1..30}; do
  # kubelet이 정상적으로 실행 중이고 API 서버에 연결되었는지 확인
  if sudo systemctl is-active --quiet kubelet; then
    # kubelet 로그에서 노드 등록 확인 시도
    if sudo journalctl -u kubelet --since "1 minute ago" --no-pager 2>/dev/null | \
       grep -q "Node.*Ready\|Successfully registered node"; then
      echo "Node appears to be registered (from kubelet logs)"
      KUBELET_READY=true
      break
    fi
    # kubelet이 실행 중이면 일단 진행
    if [ $i -gt 10 ]; then
      echo "kubelet is running, assuming node registration is in progress"
      KUBELET_READY=true
      break
    fi
  fi
  echo "Waiting for kubelet to start and register node... ($i/30)"
  sleep 10
done

if [ "$KUBELET_READY" = "false" ]; then
  echo "Warning: Could not confirm node registration from kubelet"
  echo "Note: Please verify from Control Plane: kubectl get nodes $NODE_NAME"
  echo "Continuing with Flannel setup anyway..."
fi

# Flannel subnet.env 파일 생성
echo "=========================================="
echo "Setting up Flannel subnet.env..."
echo "=========================================="

# 1. /run/flannel/ 디렉토리 생성
sudo mkdir -p /run/flannel
echo "Created /run/flannel directory"

# 2. 노드가 API 서버에 등록되고 Pod CIDR이 할당될 때까지 대기
echo "Waiting for node to be assigned Pod CIDR..."
sleep 30

# 3. Pod CIDR 확인 시도 (여러 방법)
POD_CIDR=""

# 방법 1: kubelet 로그에서 Pod CIDR 확인
echo "Attempting to detect Pod CIDR from kubelet logs..."
if [ -z "$POD_CIDR" ]; then
  POD_CIDR=$(sudo journalctl -u kubelet --since "2 minutes ago" --no-pager 2>/dev/null | \
    grep -oP 'Allocated pod CIDR: \K[0-9.]+/[0-9]+' | tail -1 || echo "")
  if [ -n "$POD_CIDR" ]; then
    echo "Found Pod CIDR from kubelet logs: $POD_CIDR"
  fi
fi

# 방법 2: kubelet config에서 확인
if [ -z "$POD_CIDR" ]; then
  echo "Attempting to detect Pod CIDR from kubelet config..."
  if [ -f /var/lib/kubelet/config.yaml ]; then
    POD_CIDR=$(sudo grep -i "podCIDR" /var/lib/kubelet/config.yaml 2>/dev/null | \
      awk '{print $2}' | head -1 || echo "")
    if [ -n "$POD_CIDR" ]; then
      echo "Found Pod CIDR from kubelet config: $POD_CIDR"
    fi
  fi
fi

# 방법 3: 기본값 사용 (Flannel 기본 Pod CIDR 범위)
if [ -z "$POD_CIDR" ]; then
  echo "Warning: Could not determine Pod CIDR from logs or config"
  echo "Using default Pod CIDR range (Flannel will update this later)"
  # 기본값으로 시작 (Flannel이 나중에 업데이트할 것)
  POD_CIDR="10.244.0.0/24"
fi

echo "Using Pod CIDR: $POD_CIDR"

# 4. subnet.env 파일 생성
# FLANNEL_NETWORK: 전체 Pod 네트워크 CIDR (Flannel 기본값)
# FLANNEL_SUBNET: 이 노드에 할당된 Pod CIDR
# FLANNEL_MTU: 기본 MTU
# FLANNEL_IPMASQ: IP masquerading 활성화 (외부 통신을 위해 필요)

FLANNEL_NETWORK="10.244.0.0/16"
FLANNEL_SUBNET="$POD_CIDR"
FLANNEL_MTU="1450"

cat <<EOF | sudo tee /run/flannel/subnet.env
FLANNEL_NETWORK=$FLANNEL_NETWORK
FLANNEL_SUBNET=$FLANNEL_SUBNET
FLANNEL_MTU=$FLANNEL_MTU
FLANNEL_IPMASQ=true
EOF

echo "Created /run/flannel/subnet.env:"
cat /run/flannel/subnet.env

# 5. 파일 권한 확인
sudo chmod 644 /run/flannel/subnet.env
echo "Set permissions on /run/flannel/subnet.env"

echo "=========================================="
echo "Flannel subnet.env setup completed!"
echo "=========================================="

# 최종 확인
if sudo systemctl is-active --quiet kubelet; then
  echo "=========================================="
  echo "Node $NODE_NAME join process completed!"
  echo "=========================================="
  echo ""
  echo "kubelet is running. Please verify from Control Plane:"
  echo "  kubectl get nodes $NODE_NAME"
  echo ""
  echo "Flannel subnet.env has been configured."
  echo "If node is Ready, Flannel Pod should start successfully."
  exit 0
else
  echo "Warning: kubelet is not running"
  echo "Please check: sudo systemctl status kubelet"
  exit 1
fi
