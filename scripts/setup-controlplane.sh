#!/bin/bash
# 온프레미스 Control Plane 설정 스크립트
# 사용법: sudo ./setup-controlplane.sh <온프레미스_서버_IP>

set -e

CONTROL_PLANE_IP="${1:-$(hostname -I | awk '{print $1}')}"

echo "Setting up Kubernetes Control Plane on $CONTROL_PLANE_IP"

# Kubernetes 설치
apt-get update
apt-get install -y apt-transport-https ca-certificates curl

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# Control Plane 초기화
kubeadm init \
  --apiserver-advertise-address="$CONTROL_PLANE_IP" \
  --pod-network-cidr=10.244.0.0/16 \
  --control-plane-endpoint="$CONTROL_PLANE_IP:6443"

# kubeconfig 설정
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# CNI 설치 (Flannel)
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

echo ""
echo "=========================================="
echo "Control Plane 설정 완료!"
echo "=========================================="
echo ""
echo "다음 명령어로 조인 정보를 확인하세요:"
echo "  kubeadm token create --print-join-command"
echo ""
echo "CA 인증서 (base64):"
cat /etc/kubernetes/pki/ca.crt | base64 -w 0
echo ""
echo "=========================================="

