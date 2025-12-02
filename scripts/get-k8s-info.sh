#!/bin/bash
# 온프레미스 Control Plane에서 Kubernetes 정보 추출 스크립트

echo "=========================================="
echo "Kubernetes Cluster Information"
echo "=========================================="
echo ""

# 1. Cluster Endpoint
CONTROL_PLANE_IP=$(hostname -I | awk '{print $1}')
echo "1. k8s_cluster_endpoint:"
echo "   https://${CONTROL_PLANE_IP}:6443"
echo ""

# 2. CA Certificate (base64)
echo "2. k8s_cluster_ca_certificate:"
if [ -f /etc/kubernetes/pki/ca.crt ]; then
    cat /etc/kubernetes/pki/ca.crt | base64 -w 0
    echo ""
    echo ""
else
    echo "   ERROR: CA certificate not found!"
    echo "   Make sure Control Plane is initialized."
    echo ""
fi

# 3. Join Command
echo "3. k8s_join_command:"
JOIN_CMD=$(kubeadm token create --print-join-command 2>/dev/null)
if [ $? -eq 0 ]; then
    echo "   ${JOIN_CMD}"
    echo ""
    
    # 토큰 추출
    TOKEN=$(echo "$JOIN_CMD" | grep -oP '--token \K[^\s]+')
    echo "4. k8s_cluster_token (추출된 토큰):"
    echo "   ${TOKEN}"
    echo ""
else
    echo "   ERROR: Failed to create token"
    echo "   Try: kubeadm token create --print-join-command"
    echo ""
fi

echo "=========================================="
echo "위 정보를 terraform.tfvars에 복사하세요!"
echo "=========================================="

