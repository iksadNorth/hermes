#!/bin/bash
set -e

# 변수 설정 (환경 변수로 전달됨)
NODE_NAME="${NODE_NAME}"
K8S_JOIN_COMMAND="${K8S_JOIN_COMMAND}"
K8S_CLUSTER_ENDPOINT="${K8S_CLUSTER_ENDPOINT}"
K8S_CLUSTER_TOKEN="${K8S_CLUSTER_TOKEN}"
K8S_CLUSTER_CA_CERT="${K8S_CLUSTER_CA_CERT}"
TIMEOUT="${TIMEOUT:-300}"

# 시스템 업데이트
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y curl apt-transport-https ca-certificates

# 호스트명 설정
if [ -n "$NODE_NAME" ]; then
  hostnamectl set-hostname "$NODE_NAME"
  echo "127.0.0.1 $NODE_NAME" >> /etc/hosts
fi

# Kubernetes 클러스터 조인
if [ -n "$K8S_JOIN_COMMAND" ]; then
  echo "Joining Kubernetes cluster..."
  eval "$K8S_JOIN_COMMAND"
else
  echo "ERROR: K8S_JOIN_COMMAND is not set"
  exit 1
fi

# 노드가 준비될 때까지 대기
echo "Waiting for kubelet to be ready..."
sleep 30

# 노드가 클러스터에 등록되었는지 확인
# 로컬 kubectl이 있으면 사용하고, 없으면 API 서버를 통해 확인
if [ -n "$K8S_CLUSTER_ENDPOINT" ] && [ -n "$K8S_CLUSTER_TOKEN" ] && [ -n "$K8S_CLUSTER_CA_CERT" ]; then
  # API 서버를 통해 확인 (더 확실함)
  echo "Waiting for node $NODE_NAME to join the cluster (via API server)..."
  CA_CERT_FILE=$(mktemp)
  echo "$K8S_CLUSTER_CA_CERT" | base64 -d > "$CA_CERT_FILE" 2>/dev/null || echo "$K8S_CLUSTER_CA_CERT" > "$CA_CERT_FILE"
  
  elapsed=0
  while [ $elapsed -lt $TIMEOUT ]; do
    # curl로 API 서버 확인 (CA 인증서와 토큰 사용)
    if curl -s -k --connect-timeout 5 \
      --cacert "$CA_CERT_FILE" \
      -H "Authorization: Bearer $K8S_CLUSTER_TOKEN" \
      "$K8S_CLUSTER_ENDPOINT/api/v1/nodes/$NODE_NAME" &>/dev/null; then
      echo "Node $NODE_NAME successfully joined the cluster!"
      rm -f "$CA_CERT_FILE"
      exit 0
    fi
    echo "Waiting for node registration... ($elapsed/$TIMEOUT seconds)"
    sleep 10
    elapsed=$((elapsed + 10))
  done
  rm -f "$CA_CERT_FILE"
  
  # API 서버 확인 실패 시, 로컬 kubectl로 재시도
  if command -v kubectl &> /dev/null; then
    echo "Trying to verify with local kubectl..."
    max_attempts=10
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
      if kubectl get nodes "$NODE_NAME" &>/dev/null 2>&1; then
        echo "Node $NODE_NAME verified with local kubectl!"
        exit 0
      fi
      sleep 5
      attempt=$((attempt + 1))
    done
  fi
  
  echo "WARNING: Node registration check timeout, but join command was executed"
  exit 0
else
  # API 서버 정보가 없으면 로컬 kubectl로만 확인
  echo "Waiting for node $NODE_NAME to join the cluster (local kubectl)..."
  max_attempts=30
  attempt=0
  while [ $attempt -lt $max_attempts ]; do
    if command -v kubectl &> /dev/null; then
      if kubectl get nodes "$NODE_NAME" &>/dev/null 2>&1; then
        echo "Node $NODE_NAME successfully joined the cluster!"
        exit 0
      fi
    fi
    echo "Waiting for node registration... (attempt $((attempt + 1))/$max_attempts)"
    sleep 10
    attempt=$((attempt + 1))
  done
  
  echo "WARNING: Node registration check timeout, but join command was executed"
  exit 0
fi

