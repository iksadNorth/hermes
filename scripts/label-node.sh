#!/bin/bash
set -e

# 변수 설정 (환경 변수로 전달됨)
NODE_NAME="${NODE_NAME}"
K8S_CLUSTER_ENDPOINT="${K8S_CLUSTER_ENDPOINT}"
K8S_CLUSTER_TOKEN="${K8S_CLUSTER_TOKEN}"
K8S_CLUSTER_CA_CERT="${K8S_CLUSTER_CA_CERT}"
CLOUD_LABEL_KEY="${CLOUD_LABEL_KEY:-cloud-server}"
CLOUD_LABEL_VALUE="${CLOUD_LABEL_VALUE:-true}"
ADDITIONAL_LABELS="${ADDITIONAL_LABELS:-}"

if [ -z "$NODE_NAME" ] || [ -z "$K8S_CLUSTER_ENDPOINT" ] || [ -z "$K8S_CLUSTER_TOKEN" ] || [ -z "$K8S_CLUSTER_CA_CERT" ]; then
  echo "ERROR: Required environment variables are not set"
  exit 1
fi

# CA 인증서를 임시 파일로 저장
CA_CERT_FILE=$(mktemp)
echo "$K8S_CLUSTER_CA_CERT" | base64 -d > "$CA_CERT_FILE"

# 클라우드 서버 라벨 추가
echo "Adding label $CLOUD_LABEL_KEY=$CLOUD_LABEL_VALUE to node $NODE_NAME..."
kubectl --server="$K8S_CLUSTER_ENDPOINT" \
  --token="$K8S_CLUSTER_TOKEN" \
  --certificate-authority="$CA_CERT_FILE" \
  label nodes "$NODE_NAME" "$CLOUD_LABEL_KEY=$CLOUD_LABEL_VALUE" --overwrite

# 추가 라벨 설정 (형식: "key1=value1,key2=value2")
if [ -n "$ADDITIONAL_LABELS" ]; then
  IFS=',' read -ra LABELS <<< "$ADDITIONAL_LABELS"
  for label in "${LABELS[@]}"; do
    if [ -n "$label" ]; then
      echo "Adding additional label $label to node $NODE_NAME..."
      kubectl --server="$K8S_CLUSTER_ENDPOINT" \
        --token="$K8S_CLUSTER_TOKEN" \
        --certificate-authority="$CA_CERT_FILE" \
        label nodes "$NODE_NAME" "$label" --overwrite
    fi
  done
fi

rm -f "$CA_CERT_FILE"
echo "Labels successfully added to node $NODE_NAME"

