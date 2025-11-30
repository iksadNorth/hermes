#!/bin/bash
set -e

NODE_NAME="${NODE_NAME}"

apt-get update
apt-get install -y curl apt-transport-https ca-certificates openssh-server

hostnamectl set-hostname "$NODE_NAME"
systemctl enable ssh
systemctl start ssh || true
