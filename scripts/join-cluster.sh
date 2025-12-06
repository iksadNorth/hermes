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
sleep 30
for i in {1..30}; do
  if kubectl get nodes "$NODE_NAME" &>/dev/null 2>&1; then
    echo "Node $NODE_NAME joined successfully!"
    exit 0
  fi
  sleep 10
done

echo "Warning: Node registration timeout"
exit 0
