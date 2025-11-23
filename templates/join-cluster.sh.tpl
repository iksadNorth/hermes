#!/bin/bash
set -e

# 시스템 업데이트
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y curl apt-transport-https ca-certificates

# 호스트명 설정
hostnamectl set-hostname ${node_name}
echo "127.0.0.1 ${node_name}" >> /etc/hosts

# Kubernetes 클러스터 조인
${k8s_join_command}

# 노드가 준비될 때까지 대기
echo "Waiting for kubelet to be ready..."
sleep 30

# 노드가 클러스터에 등록되었는지 확인
max_attempts=30
attempt=0
while [ $attempt -lt $max_attempts ]; do
  if kubectl get nodes ${node_name} &>/dev/null; then
    echo "Node ${node_name} successfully joined the cluster!"
    break
  fi
  echo "Waiting for node registration... (attempt $((attempt + 1))/$max_attempts)"
  sleep 10
  attempt=$((attempt + 1))
done

# 클라우드 서버 라벨 추가 (kubectl이 사용 가능한 경우)
if command -v kubectl &> /dev/null; then
  kubectl label nodes ${node_name} ${cloud_label_key}=${cloud_label_value} --overwrite || true
  echo "Label ${cloud_label_key}=${cloud_label_value} added to node ${node_name}"
fi

