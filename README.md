# Hermes

헤르메스는 길 잃은 나그네들의 수호신입니다. 

![헤르메스 그림](documents/cartoon-hermes.png)

*그림 0: 길 잃은 양들을 인도하는 헤르메스 그림*

해당 프로젝트는 과도한 트래픽으로 인해 IP 차단된 크롤링 노드들을 새로운 AWS 클라우드 서버로 자리를 바꿔 
순단 없이 작업을 이어갈 수 있도록 도움을 줍니다.

온프레미스에 구축된 Kubernetes Control Plane과 AWS 클라우드 노드를 연결하는 하이브리드 클러스터를 구성합니다.

Terraform을 사용하여 AWS EC2 인스턴스를 자동으로 생성하고, Kubernetes 클러스터에 자동으로 조인시킵니다.

IP 차단된 크롤링 컨테이너들을 새로운 클라우드 노드로 자동으로 마이그레이션할 수 있습니다.


이 모든 것은 사람이 직접 수행하는 것이 아닌 Terraform이라는 IaC(Infrastructure as Code) 툴을 이용하여 자동화를 이뤘습니다.

![시스템 아키텍처](documents/architecture-diagram.png)

## 왜 이런 식으로 만들었나요?

- **온프레미스 서버만 사용하면 IP 차단 시 대체할 서버가 없다..**
  - AWS 클라우드와 온프레미스를 연결하는 하이브리드 클러스터를 구성해보자!
- **AWS 클라우드 서버를 새로 띄우려면 꼭 내가 직접 AWS 콘솔창에 입력해야 하나? 자동화할 수는 없는건가..**
  - Terraform으로 AWS 클라우드 노드 자동 생성 및 Kubernetes 클러스터 자동 조인을 구현해보자!
- **Docker Compose로 1개 이상의 서버들의 컨테이너를 종합관리하는 것이 너무 힘들다..**
  - K8s를 도입해서 다중 노드의 컨테이너를 하나의 서버에서 제어해보자!
- **크롤링 컨테이너 말고도 연산을 위한 컨테이너, Airflow 컨테이너도 띄워야 하는데 이것들은 홈서버에서만 띄우고 싶다..**
  - 클라우드 노드에만 특정 라벨을 부여해서 해당 라벨의 노드에는 크롤링 Pod만 띄우자!

## 이거 어떻게 사용하는 거에요?

### 과정 1: Terraform으로 VPC 자동 생성

![demo](documents/aws-dashboard-vpc.gif)

### 과정 2: Terraform으로 인스턴스 및 방화벽 규칙 설정

![demo](documents/aws-dashboard-node.gif)

### 과정 3: 홈서버의 K8s API Server로 노드 Join 요청

![demo](documents/k8s-cli-node.gif)

### 과정 4: 홈서버의 K8s API Server로 노드 라벨링

![demo](documents/k8s-cli-label.gif)

## 그래서 의도한 대로 성과가 나왔나요?

1. **노드 추가 작업 자동화**
    - **수동 작업 vs 자동화**: 수동 작업(약 ??분)을 자동화(약 ??분)로 단축
    - SSH 접속, 패키지 설치, 클러스터 조인 등 모든 과정이 자동화됨

2. **인프라 관리의 일관성 확보**
    - Terraform을 통한 Infrastructure as Code로 모든 노드가 동일한 설정으로 구성됨
    - 버전 관리 및 재현 가능한 인프라 구성

## 프로젝트 구조

```
hermes/
├── versions.tf               # Terraform 버전 제약
├── providers.tf              # Terraform 프로바이더 설정
├── main-vpc.tf               # VPC, 서브넷, 라우팅 테이블 구성
├── main-node.tf              # EC2 인스턴스, 보안 그룹, SSH 키 생성
├── main-k8sjoin.tf           # Kubernetes 클러스터 조인 리소스
├── main-label.tf             # 노드 라벨 추가 리소스
├── outputs.tf                # Terraform 출력값 정의
├── variables.tf              # Terraform 변수 정의
├── terraform.tfvars.example  # 변수 설정 예시 파일
├── terraform.tfvars          # 변수 설정 파일
└── scripts/
    ├── setup-controlplane.sh # Control Plane 초기화 스크립트
    ├── init-node.sh          # 노드 초기 설정 스크립트
    └── join-cluster.sh       # 클러스터 조인 스크립트
```
