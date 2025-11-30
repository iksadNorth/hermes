#!/bin/bash
set -e

NODE_NAME="${NODE_NAME}"
K8S_JOIN_COMMAND="${K8S_JOIN_COMMAND}"

# 시스템 업데이트
apt-get update
apt-get install -y curl apt-transport-https ca-certificates

# 호스트명 설정
hostnamectl set-hostname "$NODE_NAME"

# Kubernetes 클러스터 조인
eval "$K8S_JOIN_COMMAND"

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
