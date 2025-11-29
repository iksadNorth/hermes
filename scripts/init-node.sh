#!/bin/bash
set -e

# 변수 설정 (환경 변수로 전달됨)
NODE_NAME="${NODE_NAME}"

# 시스템 업데이트
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y curl apt-transport-https ca-certificates openssh-server

# 호스트명 설정
if [ -n "$NODE_NAME" ]; then
  hostnamectl set-hostname "$NODE_NAME"
  echo "127.0.0.1 $NODE_NAME" >> /etc/hosts
fi

# SSH 서비스 시작 (이미 시작되어 있을 수 있음)
systemctl enable ssh
systemctl start ssh || true

echo "Node initialization completed for $NODE_NAME"

