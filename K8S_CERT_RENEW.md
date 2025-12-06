# Kubernetes API 서버 인증서에 도메인 추가하기

## 문제 상황
Kubernetes API 서버 인증서에 특정 도메인(`main-node.me`)이 포함되지 않아 클러스터 조인 시 TLS 인증서 검증 오류가 발생합니다.

## 해결 방법

### 방법 1: 기존 클러스터의 인증서 재생성 (권장)

온프레미스 Control Plane 서버에서 다음 단계를 수행하세요:

#### 1단계: 기존 인증서 백업

```bash
# 인증서 디렉토리 백업
sudo cp -r /etc/kubernetes/pki /etc/kubernetes/pki.backup.$(date +%Y%m%d_%H%M%S)
```

#### 2단계: kubeadm 설정 파일 생성

```bash
# 현재 클러스터 설정 확인
sudo kubeadm config print init-defaults > /tmp/kubeadm-config.yaml

# 설정 파일 편집 (또는 새로 생성)
sudo mkdir -p /etc/kubernetes
sudo tee /etc/kubernetes/kubeadm-config.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: $(kubectl version -o json | jq -r '.serverVersion.gitVersion' | sed 's/v//')
controlPlaneEndpoint: "main-node.me:6443"
apiServer:
  certSANs:
    - "main-node.me"
    - "mainnode"
    - "kubernetes"
    - "kubernetes.default"
    - "kubernetes.default.svc"
    - "kubernetes.default.svc.cluster.local"
    - "127.0.0.1"
    - "localhost"
    - "$(hostname -I | awk '{print $1}')"  # 온프레미스 서버 IP
    - "$(curl -s ifconfig.me 2>/dev/null || echo '')"  # 공인 IP (있는 경우)
networking:
  podSubnet: "10.244.0.0/16"
EOF
```

#### 3단계: API 서버 인증서 재생성

```bash
# API 서버 인증서만 재생성
sudo kubeadm certs renew apiserver --config=/etc/kubernetes/kubeadm-config.yaml

# 또는 모든 인증서 재생성 (더 안전)
sudo kubeadm certs renew all --config=/etc/kubernetes/kubeadm-config.yaml
```

#### 4단계: API 서버 재시작

```bash
# kubelet 재시작 (API 서버도 함께 재시작됨)
sudo systemctl restart kubelet

# 상태 확인
sudo systemctl status kubelet
kubectl get nodes
```

#### 5단계: 인증서 확인

```bash
# 인증서에 도메인이 포함되었는지 확인
echo | openssl s_client -connect main-node.me:6443 -servername main-node.me 2>/dev/null | \
  openssl x509 -noout -text | grep -A 1 "Subject Alternative Name"

# 또는
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout | grep -A 1 "Subject Alternative Name"
```

출력에 `DNS:main-node.me`가 포함되어 있어야 합니다.

---

### 방법 2: 클러스터 초기화 시 설정 (새 클러스터용)

새 클러스터를 초기화할 때부터 도메인을 포함시키려면:

```bash
# kubeadm 설정 파일 생성
sudo tee /etc/kubernetes/kubeadm-config.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: "$(hostname -I | awk '{print $1}')"
  bindPort: 6443
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.28.15
controlPlaneEndpoint: "main-node.me:6443"
apiServer:
  certSANs:
    - "main-node.me"
    - "mainnode"
    - "kubernetes"
    - "kubernetes.default"
    - "kubernetes.default.svc"
    - "kubernetes.default.svc.cluster.local"
    - "127.0.0.1"
    - "localhost"
    - "$(hostname -I | awk '{print $1}')"
    - "$(curl -s ifconfig.me 2>/dev/null || echo '')"
networking:
  podSubnet: "10.244.0.0/16"
EOF

# 설정 파일을 사용하여 초기화
sudo kubeadm init --config=/etc/kubernetes/kubeadm-config.yaml
```

---

### 방법 3: 수동으로 인증서 재생성 (고급)

kubeadm certs renew가 작동하지 않는 경우:

```bash
# 1. kubeadm 설정 파일 생성 (위와 동일)

# 2. 인증서 디렉토리로 이동
cd /etc/kubernetes/pki

# 3. 기존 인증서 백업
sudo mv apiserver.crt apiserver.crt.old
sudo mv apiserver.key apiserver.key.old

# 4. 새 인증서 생성
sudo kubeadm init phase certs apiserver --config=/etc/kubernetes/kubeadm-config.yaml

# 5. kubelet 재시작
sudo systemctl restart kubelet
```

---

## 문제 해결

### 인증서 재생성 후에도 문제가 발생하는 경우

1. **kubelet이 새 인증서를 로드하지 않는 경우:**
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl restart kubelet
   ```

2. **API 서버가 시작되지 않는 경우:**
   ```bash
   # 로그 확인
   sudo journalctl -xeu kubelet
   sudo journalctl -xeu kube-apiserver
   
   # 백업에서 복원
   sudo cp -r /etc/kubernetes/pki.backup.*/apiserver.* /etc/kubernetes/pki/
   sudo systemctl restart kubelet
   ```

3. **인증서가 여전히 업데이트되지 않는 경우:**
   ```bash
   # 모든 인증서 재생성
   sudo kubeadm certs renew all --config=/etc/kubernetes/kubeadm-config.yaml
   sudo systemctl restart kubelet
   ```

---

## 확인 사항

인증서 재생성 후 다음을 확인하세요:

```bash
# 1. 인증서에 도메인 포함 확인
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout | grep -A 5 "Subject Alternative Name"

# 2. API 서버 연결 테스트
curl -k https://main-node.me:6443/version

# 3. 클러스터 상태 확인
kubectl cluster-info
kubectl get nodes
```

---

## 문제: kubeadm join이 사설 IP로 접근하려고 하는 경우

### 증상
`kubeadm join main-node.me:6443`으로 실행했는데, 에러 메시지에서 `https://192.168.xxx.xxx:6443`로 접근하려고 한다.

### 원인
`kubeadm join`이 클러스터 정보를 가져올 때, 다음 중 하나에서 사설 IP를 사용합니다:
1. `cluster-info` ConfigMap (kube-public 네임스페이스) - 가장 가능성 높음
2. API 서버의 실제 바인딩 주소
3. 클러스터 초기화 시 사용된 `--apiserver-advertise-address` 값

`kubeadm-config` ConfigMap에 `controlPlaneEndpoint`가 없으면, kubeadm은 `cluster-info` ConfigMap을 참조합니다.

### 해결 방법

#### 1단계: cluster-info ConfigMap 확인

```bash
# 온프레미스 Control Plane 서버에서 실행
kubectl get configmap cluster-info -n kube-public -o yaml
```

이 ConfigMap에 `server` 필드가 `https://192.168.xxx.xxx:6443`으로 되어 있을 것입니다.

#### 2단계: kubeadm-config 업데이트

```bash
# ConfigMap 편집
kubectl edit configmap kubeadm-config -n kube-system
```

또는 직접 수정:

```bash
# ConfigMap 가져오기
kubectl get configmap kubeadm-config -n kube-system -o yaml > /tmp/kubeadm-config.yaml

# controlPlaneEndpoint를 main-node.me:6443으로 변경
sed -i 's/192.168.xxx.xxx:6443/main-node.me:6443/g' /tmp/kubeadm-config.yaml
# 또는 직접 편집

# ConfigMap 업데이트
kubectl apply -f /tmp/kubeadm-config.yaml
```

#### 3단계: cluster-info ConfigMap 업데이트 (중요!)

`cluster-info` ConfigMap이 실제 문제의 원인일 가능성이 높습니다:

```bash
# 1. cluster-info ConfigMap 확인
kubectl get configmap cluster-info -n kube-public -o yaml

# 2. ConfigMap 편집
kubectl edit configmap cluster-info -n kube-public
```

편집기에서 `kubeconfig` 섹션의 `server` 필드를 찾아:
- `https://192.168.xxx.xxx:6443` → `https://main-node.me:6443`으로 변경

또는 직접 수정:

```bash
# ConfigMap 가져오기
kubectl get configmap cluster-info -n kube-public -o yaml > /tmp/cluster-info.yaml

# server 주소 변경 (base64 인코딩된 kubeconfig 내부)
# 주의: kubeconfig는 base64로 인코딩되어 있으므로 디코딩 후 수정해야 함
kubectl get configmap cluster-info -n kube-public -o jsonpath='{.data.kubeconfig}' | \
  base64 -d | \
  sed 's|https://192.168.xxx.xxx:6443|https://main-node.me:6443|g' | \
  base64 -w 0 > /tmp/kubeconfig-encoded.txt

# ConfigMap 업데이트
kubectl patch configmap cluster-info -n kube-public --type merge -p "{\"data\":{\"kubeconfig\":\"$(cat /tmp/kubeconfig-encoded.txt)\"}}"
```

또는 더 간단한 방법:

```bash
# cluster-info ConfigMap 삭제 후 재생성
kubectl delete configmap cluster-info -n kube-public

# kubeadm이 자동으로 재생성하도록 트리거
# (다음 join 시도 시 자동으로 재생성됨)
# 또는 수동으로 재생성:
kubectl create configmap cluster-info \
  --from-literal=kubeconfig="$(kubectl config view --flatten --minify | base64 -w 0)" \
  -n kube-public
```

#### 4단계: kubeadm-config 업데이트 (더 안전한 방법)

더 안전한 방법은 kubeadm을 사용하여 설정을 업데이트하는 것입니다:

```bash
# 1. 현재 설정 내보내기
kubeadm config print init-defaults > /tmp/kubeadm-config-init.yaml

# 2. 클러스터 설정 내보내기
kubeadm config print cluster-defaults > /tmp/kubeadm-config-cluster.yaml

# 3. 두 파일을 합쳐서 수정
# controlPlaneEndpoint를 main-node.me:6443으로 변경
# certSANs에 main-node.me 추가

# 4. kubeadm config upload로 업데이트 (이 방법은 제한적일 수 있음)
```

#### 5단계: 클러스터 재초기화 (최후의 수단)

위 방법이 작동하지 않으면, 클러스터를 재초기화해야 할 수 있습니다:

```bash
# 주의: 이 방법은 클러스터를 완전히 재설정합니다!
# 모든 데이터가 삭제되므로 백업이 필요합니다.

# 1. 클러스터 리셋
sudo kubeadm reset

# 2. 올바른 설정으로 재초기화
sudo kubeadm init \
  --apiserver-advertise-address="$(hostname -I | awk '{print $1}')" \
  --pod-network-cidr=10.244.0.0/16 \
  --control-plane-endpoint="main-node.me:6443" \
  --upload-certs

# 3. kubeadm-config.yaml 파일 생성 (위의 방법 1 참고)
# 4. 인증서 재생성
```

---

## 참고사항

- 인증서 재생성 후에는 모든 워커 노드가 자동으로 새 인증서를 사용합니다.
- Control Plane 노드가 여러 개인 경우, 모든 노드에서 동일한 설정으로 인증서를 재생성해야 합니다.
- 인증서 재생성은 클러스터 다운타임 없이 수행할 수 있습니다 (kubelet 재시작만 필요).
- **중요**: `kubeadm-config` ConfigMap의 `controlPlaneEndpoint`가 올바른 도메인으로 설정되어 있어야 합니다.

