#!/bin/bash
set -e

NODE_NAME="${NODE_NAME}"
K8S_JOIN_COMMAND="${K8S_JOIN_COMMAND}"

# 시스템 업데이트
sudo apt-get update
sudo apt-get install -y curl apt-transport-https ca-certificates

# 호스트명 설정
sudo hostnamectl set-hostname "$NODE_NAME"

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
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# Kubernetes 설치
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Kubernetes 클러스터 조인
sudo bash -c "$K8S_JOIN_COMMAND"

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
