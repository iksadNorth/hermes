#!/bin/bash
# Terraform external data source용 스크립트
# Control Plane 노드에서 join command를 가져와서 JSON으로 반환
# 입력: JSON 형식 {"ssh_host": "...", "ssh_user": "...", "ssh_key_path": "...", "api_server_domain": "..."}
# 출력: JSON 형식 {"join_command": "kubeadm join main-node.me:6443 --token ... --discovery-token-ca-cert-hash ..."}

set -e

# jq 설치 확인
if ! command -v jq &> /dev/null; then
  echo '{"error": "jq is required but not installed. Please install jq: brew install jq (macOS) or apt-get install jq (Ubuntu)"}' >&2
  exit 1
fi

# JSON 입력 읽기
INPUT=$(cat)

# jq를 사용하여 JSON 파싱 (더 안전하고 간단)
SSH_HOST=$(echo "$INPUT" | jq -r '.ssh_host // ""')
SSH_USER=$(echo "$INPUT" | jq -r '.ssh_user // "root"')
SSH_KEY_PATH=$(echo "$INPUT" | jq -r '.ssh_key_path // ""')
API_SERVER_DOMAIN=$(echo "$INPUT" | jq -r '.api_server_domain // "main-node.me"')

# 필수 파라미터 확인
if [ -z "$SSH_HOST" ]; then
  echo '{"error": "ssh_host is required"}' >&2
  exit 1
fi

# SSH 키 경로 확장 (~ 처리)
if [ -n "$SSH_KEY_PATH" ]; then
  SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"
fi

# 디버그: SSH 키 경로 및 파일 존재 여부 확인
echo "[DEBUG] SSH_KEY_PATH: $SSH_KEY_PATH" >&2
echo "[DEBUG] SSH_KEY_PATH exists: $([ -f "$SSH_KEY_PATH" ] && echo 'yes' || echo 'no')" >&2
if [ -f "$SSH_KEY_PATH" ]; then
  echo "[DEBUG] SSH_KEY_PATH permissions: $(ls -l "$SSH_KEY_PATH" | awk '{print $1}')" >&2
fi

# SSH 명령어 구성
SSH_CMD="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o LogLevel=DEBUG"
if [ -n "$SSH_KEY_PATH" ] && [ -f "$SSH_KEY_PATH" ]; then
  SSH_CMD="$SSH_CMD -i $SSH_KEY_PATH"
  echo "[DEBUG] Using SSH key: $SSH_KEY_PATH" >&2
else
  echo "[DEBUG] SSH key not found, using password authentication" >&2
fi

# Control Plane 노드에서 join command 가져오기
JOIN_CMD=$(eval "$SSH_CMD $SSH_USER@$SSH_HOST 'kubeadm token create --print-join-command 2>/dev/null'" || echo "")

if [ -z "$JOIN_CMD" ]; then
  echo "{\"error\": \"Failed to get join command from Control Plane server: $SSH_USER@$SSH_HOST\"}" >&2
  exit 1
fi

# 디버그: 원본 join command 출력 (stderr로 출력하여 Terraform에 영향을 주지 않음)
echo "[DEBUG] Original join command: $JOIN_CMD" >&2

# IP 주소를 도메인:6443으로 치환
# 패턴: IP:6443 형식 (예: 192.168.xxx.xxx:6443 -> main-node.me:6443)
JOIN_CMD_FIXED=$(echo "$JOIN_CMD" | sed -E "s/[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:6443/${API_SERVER_DOMAIN}:6443/g")

# 디버그: 수정된 join command 출력
echo "[DEBUG] Fixed join command (IP replaced with $API_SERVER_DOMAIN): $JOIN_CMD_FIXED" >&2

# JSON 형식으로 출력
echo "{\"join_command\": \"$JOIN_CMD_FIXED\"}"

