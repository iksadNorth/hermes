#!/bin/bash
# get-join-command.sh 스크립트를 직접 테스트하는 헬퍼 스크립트
# 사용법: ./scripts/test-get-join-command.sh

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================="
echo "Join Command 테스트 스크립트"
echo "==========================================${NC}"

# terraform.tfvars 파일 확인
if [ ! -f terraform.tfvars ]; then
  echo -e "${RED}Error: terraform.tfvars 파일이 없습니다.${NC}"
  echo "terraform.tfvars.example을 복사하여 terraform.tfvars를 생성하세요."
  exit 1
fi

# jq 설치 확인
if ! command -v jq &> /dev/null; then
  echo -e "${RED}Error: jq가 설치되어 있지 않습니다.${NC}"
  echo "설치 방법:"
  echo "  macOS: brew install jq"
  echo "  Ubuntu: apt-get install jq"
  exit 1
fi

# terraform.tfvars에서 설정 읽기
echo -e "${YELLOW}[1/4] terraform.tfvars에서 설정 읽는 중...${NC}"

SSH_HOST=$(grep "k8s_control_plane_ssh_host" terraform.tfvars 2>/dev/null | sed -E 's/.*=.*"([^"]+)".*/\1/' | head -1 || echo "main-node.me")
SSH_USER=$(grep "k8s_control_plane_ssh_user" terraform.tfvars 2>/dev/null | sed -E 's/.*=.*"([^"]+)".*/\1/' | head -1 || echo "root")
SSH_KEY=$(grep "k8s_control_plane_ssh_key" terraform.tfvars 2>/dev/null | sed -E 's/.*=.*"([^"]+)".*/\1/' | head -1 || echo "")
API_DOMAIN=$(grep "k8s_api_server_domain" terraform.tfvars 2>/dev/null | sed -E 's/.*=.*"([^"]+)".*/\1/' | head -1 || echo "main-node.me")

# SSH 키 경로 확장
if [ -n "$SSH_KEY" ]; then
  SSH_KEY="${SSH_KEY/#\~/$HOME}"
fi

echo -e "${GREEN}✓ 설정 읽기 완료${NC}"
echo ""
echo -e "${BLUE}=========================================="
echo "설정 정보"
echo "==========================================${NC}"
echo "SSH Host:      $SSH_HOST"
echo "SSH User:      $SSH_USER"
echo "SSH Key:       ${SSH_KEY:-"(기본 키 사용)"}"
echo "API Domain:    $API_DOMAIN"
echo ""

# SSH 키 파일 확인
if [ -n "$SSH_KEY" ] && [ ! -f "$SSH_KEY" ]; then
  echo -e "${YELLOW}Warning: SSH 키 파일이 존재하지 않습니다: $SSH_KEY${NC}"
  echo "기본 SSH 키를 사용하거나 키 파일 경로를 확인하세요."
  echo ""
fi

# JSON 입력 생성
echo -e "${YELLOW}[2/4] JSON 입력 생성 중...${NC}"

JSON_INPUT=$(cat <<EOF
{
  "ssh_host": "$SSH_HOST",
  "ssh_user": "$SSH_USER",
  "ssh_key_path": "$SSH_KEY",
  "api_server_domain": "$API_DOMAIN"
}
EOF
)

echo -e "${GREEN}✓ JSON 입력 생성 완료${NC}"
echo ""
echo -e "${BLUE}=========================================="
echo "JSON 입력 (get-join-command.sh로 전달될 데이터)"
echo "==========================================${NC}"
echo "$JSON_INPUT" | jq .
echo ""

# 스크립트 실행
echo -e "${YELLOW}[3/4] get-join-command.sh 실행 중...${NC}"
echo ""

# 스크립트 실행 및 결과 저장
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# stderr와 stdout을 모두 캡처
EXEC_OUTPUT=$(echo "$JSON_INPUT" | bash "$SCRIPT_DIR/get-join-command.sh" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
  echo -e "${RED}=========================================="
  echo "스크립트 실행 실패"
  echo "==========================================${NC}"
  echo "$EXEC_OUTPUT"
  exit $EXIT_CODE
fi

# stderr (디버그 메시지)와 stdout (JSON 결과) 분리
DEBUG_MSG=$(echo "$EXEC_OUTPUT" | grep -E '^\[DEBUG\]' || true)
JSON_RESULT=$(echo "$EXEC_OUTPUT" | grep -v '^\[DEBUG\]' || echo "$EXEC_OUTPUT")

echo -e "${GREEN}✓ 스크립트 실행 완료${NC}"
echo ""

# 디버그 메시지 출력
if [ -n "$DEBUG_MSG" ]; then
  echo -e "${BLUE}=========================================="
  echo "디버그 메시지 (stderr)"
  echo "==========================================${NC}"
  echo "$DEBUG_MSG" | sed 's/^\[DEBUG\]/  [DEBUG]/'
  echo ""
fi

# JSON 결과 출력
echo -e "${BLUE}=========================================="
echo "스크립트 실행 결과 (JSON)"
echo "==========================================${NC}"
echo "$JSON_RESULT" | jq .

# Join command 추출
JOIN_CMD=$(echo "$JSON_RESULT" | jq -r '.join_command // empty')

if [ -n "$JOIN_CMD" ]; then
  echo ""
  echo -e "${GREEN}=========================================="
  echo "추출된 Join Command"
  echo "==========================================${NC}"
  echo -e "${GREEN}$JOIN_CMD${NC}"
  echo ""
  echo -e "${YELLOW}[4/4] 테스트 완료!${NC}"
  echo ""
  echo -e "${BLUE}이 join command를 사용하여 노드를 클러스터에 조인할 수 있습니다.${NC}"
else
  echo ""
  echo -e "${YELLOW}Warning: join_command가 결과에 없습니다.${NC}"
fi

