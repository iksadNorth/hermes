#!/bin/bash
set -e

NODE_NAME="${NODE_NAME}"
K8S_API_SERVER_DOMAIN="${K8S_API_SERVER_DOMAIN}"
K8S_API_SERVER_IP="${K8S_API_SERVER_IP}"

apt-get update
apt-get install -y curl apt-transport-https ca-certificates openssh-server

hostnamectl set-hostname "$NODE_NAME"
systemctl enable ssh
systemctl start ssh || true

# Kubernetes API 서버 도메인을 hosts 파일에 추가
if [ -n "$K8S_API_SERVER_DOMAIN" ] && [ -n "$K8S_API_SERVER_IP" ]; then
  # 기존 항목 제거 (중복 방지)
  sed -i "/$K8S_API_SERVER_DOMAIN/d" /etc/hosts || true
  # 새 항목 추가
  echo "$K8S_API_SERVER_IP $K8S_API_SERVER_DOMAIN" >> /etc/hosts
  echo "Added $K8S_API_SERVER_DOMAIN -> $K8S_API_SERVER_IP to /etc/hosts"
fi
