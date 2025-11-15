# MoreMoreMusic 개발환경 설정 가이드

> 🎵 오타쿠 중심 음악 스트리밍 플랫폼 개발환경 완전 설정 가이드

## 📋 목차

1. [시스템 요구사항](#시스템-요구사항)
2. [개발환경 개요](#개발환경-개요)
3. [Kubernetes 클러스터 설정](#kubernetes-클러스터-설정)
4. [MoreMoreMusic 인프라 배포](#moremoremusic-인프라-배포)
5. [Kafka 통신 이해하기](#kafka-통신-이해하기)
6. [서비스 간 통신 설정](#서비스-간-통신-설정)
7. [개발 워크플로우](#개발-워크플로우)
8. [문제 해결 가이드](#문제-해결-가이드)

## 🔧 시스템 요구사항

### 최소 요구사항
- **CPU**: 4 코어 이상
- **Memory**: 8GB 이상  
- **Storage**: 20GB 이상 여유 공간
- **OS**: macOS, Linux, Windows (WSL2)

### 필수 도구
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) 4.0+
- [Kubernetes](https://kubernetes.io/ko/docs/setup/) (Docker Desktop 포함 또는 Minikube)
- [Helm](https://helm.sh/ko/docs/intro/install/) 3.0+
- [kubectl](https://kubernetes.io/ko/docs/tasks/tools/install-kubectl/) 1.25+

### 설치 확인
```bash
# Docker 설치 확인
docker version

# Kubernetes 클러스터 확인
kubectl cluster-info

# Helm 설치 확인
helm version
```

## 🏗️ 개발환경 개요

### MSA 아키텍처 구성도
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Frontend      │    │  User Service   │    │ Music Service   │
│   (React)       │    │   (NestJS)      │    │   (NestJS)      │
└─────────┬───────┘    └─────────┬───────┘    └─────────┬───────┘
          │                      │                      │
          │              ┌───────▼──────────────────────▼───────┐
          │              │            Kafka Broker            │
          │              │          (메시지 버스)             │
          └──────────────┤        이벤트 드리븐 통신           │
                         └───────┬──────────────────────┬───────┘
                                 │                      │
                    ┌────────────▼────────┐  ┌─────────▼─────────┐
                    │   PostgreSQL        │  │      Redis        │
                    │   (메인 DB)         │  │    (캐시)         │
                    └─────────────────────┘  └───────────────────┘
```

### 핵심 컴포넌트
1. **Frontend**: React 기반 사용자 인터페이스
2. **User Service**: 사용자 관리, 인증, 세션
3. **Music Service**: 음악 스트리밍, 플레이리스트 관리
4. **Kafka**: 서비스 간 비동기 메시지 통신
5. **PostgreSQL**: 사용자 데이터, 음악 메타데이터 저장
6. **Redis**: 세션 캐시, 임시 데이터 저장

## ⚙️ Kubernetes 클러스터 설정

### 1. Docker Desktop에서 Kubernetes 활성화

1. **Docker Desktop 열기**
2. **Settings (⚙️)** → **Kubernetes**
3. **Enable Kubernetes** 체크박스 선택
4. **Apply & Restart** 클릭

### 2. 클러스터 연결 확인
```bash
# 클러스터 상태 확인
kubectl cluster-info

# 노드 목록 확인  
kubectl get nodes

# 예상 출력:
# NAME                 STATUS   ROLES                  AGE
# docker-desktop       Ready    control-plane,master   1d
```

### 3. 네임스페이스 생성
```bash
# 개발용 네임스페이스 생성
kubectl create namespace moremoremusic-msa

# 네임스페이스 확인
kubectl get namespaces
```

## 🚀 MoreMoreMusic 인프라 배포

### 1. 리포지토리 클론
```bash
git clone https://github.com/Sekai-of-Code/MoreMoreMusic-infra-repo.git
cd MoreMoreMusic-infra-repo
```

### 2. 보안 설정 배포
```bash
# RBAC 및 네트워크 정책 적용
kubectl apply -f security.yaml

# 적용 확인
kubectl get networkpolicy -n moremoremusic-msa
kubectl get serviceaccount -n moremoremusic-msa
```

### 3. Kafka 브로커 배포
```bash
# Kafka 배포
kubectl apply -f kafka.yaml

# Kafka Pod 상태 확인 (Ready 될 때까지 대기)
kubectl get pods -n moremoremusic-msa -w

# 예상 출력:
# NAME                            READY   STATUS    RESTARTS   AGE
# kafka-secure-xxxxx-xxxxx        1/1     Running   0          2m
```

### 4. 서비스 배포 확인
```bash
# 서비스 엔드포인트 확인
kubectl get svc -n moremoremusic-msa

# 예상 출력:
# NAME            TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
# kafka-service   ClusterIP   10.43.45.8     <none>        9092/TCP   5m
```

### 5. Helm을 이용한 전체 스택 배포 (선택사항)
```bash
cd helm/moremoremusic

# 개발 환경으로 배포
helm install moremoremusic . \
  --namespace moremoremusic-dev \
  --create-namespace \
  --values ../../values-development.yaml

# 배포 상태 확인
helm status moremoremusic -n moremoremusic-dev
```

## 📨 Kafka 통신 이해하기

### Kafka란 무엇인가요?

**Kafka**는 서로 다른 서비스들이 메시지를 주고받을 수 있게 도와주는 **메시지 전달 시스템**입니다. 
우편함과 비슷한 개념으로 생각하면 쉽습니다.

```
🏠 User Service ────📮───→ [Kafka 우편함] ─────📬───→ 🎵 Music Service
   "사용자가 로그인했어요"                           "알겠습니다! 추천 음악 준비할게요"
```

### 핵심 용어 설명

| 용어 | 설명 | 예시 |
|------|------|------|
| **Producer** | 메시지를 보내는 서비스 | User Service가 로그인 이벤트 전송 |
| **Consumer** | 메시지를 받는 서비스 | Music Service가 로그인 이벤트 수신 |
| **Topic** | 메시지 종류별 우편함 | `user-events`, `music-events` |
| **Partition** | 우편함 안의 칸막이 (처리 속도 향상) | topic마다 3개 partition |
| **Broker** | Kafka 서버 (우체국) | kafka-service:9092 |

### MoreMoreMusic에서 사용하는 Topic들

1. **`user-events`**: 사용자 관련 이벤트
   - 로그인/로그아웃
   - 프로필 수정
   - 구독 상태 변경

2. **`music-events`**: 음악 관련 이벤트
   - 곡 재생 시작/끝
   - 플레이리스트 생성/수정
   - 즐겨찾기 추가

## 🔌 서비스 간 통신 설정

### 1. 환경 변수 설정

각 서비스에서 Kafka에 연결하기 위한 환경 변수:

```yaml
# User Service 환경변수
env:
  - name: KAFKA_BROKERS
    value: "kafka-service.moremoremusic-msa.svc.cluster.local:9092"
  - name: SERVICE_NAME
    value: "user-service"
  - name: NODE_ENV
    value: "development"
```

### 2. Node.js에서 Kafka 연결 (KafkaJS 사용)

#### Producer 예제 (메시지 보내기)
```javascript
// kafka-producer.js
const { Kafka } = require('kafkajs');

// Kafka 클라이언트 생성
const kafka = new Kafka({
  clientId: 'user-service',
  brokers: [process.env.KAFKA_BROKERS]
});

const producer = kafka.producer();

// 사용자 로그인 이벤트 전송
async function sendUserLoginEvent(userId, ip) {
  await producer.connect();
  
  const message = {
    event: 'user_login',
    userId: userId,
    timestamp: new Date().toISOString(),
    ip: ip
  };
  
  await producer.send({
    topic: 'user-events',
    messages: [
      {
        key: userId,
        value: JSON.stringify(message)
      }
    ]
  });
  
  console.log(`✅ 로그인 이벤트 전송: ${userId}`);
}

module.exports = { sendUserLoginEvent };
```

#### Consumer 예제 (메시지 받기)
```javascript
// kafka-consumer.js  
const { Kafka } = require('kafkajs');

const kafka = new Kafka({
  clientId: 'music-service',
  brokers: [process.env.KAFKA_BROKERS]
});

const consumer = kafka.consumer({ 
  groupId: 'music-service-group' 
});

// 사용자 이벤트 구독
async function subscribeToUserEvents() {
  await consumer.connect();
  await consumer.subscribe({ topic: 'user-events' });
  
  await consumer.run({
    eachMessage: async ({ topic, partition, message }) => {
      const event = JSON.parse(message.value.toString());
      
      console.log(`📨 이벤트 수신: ${event.event}`, event);
      
      // 이벤트 종류별 처리
      switch (event.event) {
        case 'user_login':
          await prepareRecommendations(event.userId);
          break;
        case 'user_logout':
          await cleanupUserSession(event.userId);
          break;
      }
    }
  });
}

async function prepareRecommendations(userId) {
  console.log(`🎵 ${userId}님을 위한 추천 음악 준비 중...`);
  // 추천 로직 구현
}

module.exports = { subscribeToUserEvents };
```

### 3. 서비스별 통신 패턴

#### User Service → Music Service
```javascript
// User Service에서
await sendUserLoginEvent('user123', '192.168.1.100');

// Music Service에서 자동으로 받아서 처리
// → 사용자 맞춤 추천 음악 준비
```

#### Music Service → Analytics Service  
```javascript
// Music Service에서
await sendMusicPlayEvent({
  userId: 'user123',
  songId: 'song456', 
  duration: 180
});

// Analytics Service에서 자동으로 받아서 처리
// → 청취 패턴 분석, 통계 업데이트
```

## 💻 개발 워크플로우

### 1. 새로운 기능 개발 시

```bash
# 1. 개발 브랜치 생성
git checkout -b feature/user-playlist

# 2. Kafka 토픽이 필요한 경우
kubectl exec -n moremoremusic-msa kafka-secure-xxxxx-xxxxx -- \
  kafka-topics --bootstrap-server localhost:9092 \
  --create --topic playlist-events \
  --partitions 3 --replication-factor 1

# 3. 코드 개발 및 테스트
# 4. 통신 테스트
```

### 2. 메시지 통신 테스트

#### Producer 테스트
```bash
# 수동으로 메시지 전송 테스트
kubectl exec -n moremoremusic-msa kafka-secure-xxxxx-xxxxx -- \
  bash -c 'echo "{"event":"test","data":"hello"}" | \
  kafka-console-producer \
  --bootstrap-server localhost:9092 \
  --topic user-events'
```

#### Consumer 테스트  
```bash
# 메시지 수신 확인
kubectl exec -n moremoremusic-msa kafka-secure-xxxxx-xxxxx -- \
  kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic user-events \
  --from-beginning \
  --max-messages 5
```

### 3. 로그 모니터링

```bash
# Kafka 로그 확인
kubectl logs -f -n moremoremusic-msa kafka-secure-xxxxx-xxxxx

# User Service 로그 확인 (배포 후)
kubectl logs -f -n moremoremusic-msa deployment/user-service

# Music Service 로그 확인 (배포 후)
kubectl logs -f -n moremoremusic-msa deployment/music-service
```

## 🔧 문제 해결 가이드

### 자주 발생하는 문제들

#### 1. "Connection refused to kafka-service" 에러

**원인**: 네트워크 정책으로 인한 접근 거부

**해결책**: Pod에 올바른 라벨 추가
```yaml
labels:
  app.kubernetes.io/part-of: moremoremusic
  tier: backend
```

#### 2. "Topic does not exist" 에러

**원인**: 필요한 토픽이 생성되지 않음

**해결책**: 토픽 수동 생성
```bash
kubectl exec -n moremoremusic-msa kafka-secure-xxxxx-xxxxx -- \
  kafka-topics --bootstrap-server localhost:9092 \
  --create --topic 토픽이름 \
  --partitions 3 --replication-factor 1
```

#### 3. Kafka Pod가 계속 재시작됨

**해결책**: 리소스 부족 확인
```bash
# 노드 리소스 확인
kubectl top nodes

# Pod 리소스 확인  
kubectl top pods -n moremoremusic-msa

# Kafka Pod 상태 확인
kubectl describe pod -n moremoremusic-msa kafka-secure-xxxxx-xxxxx
```

### 유용한 디버깅 명령어

```bash
# 전체 Pod 상태 확인
kubectl get pods -A

# 서비스 엔드포인트 확인
kubectl get endpoints -n moremoremusic-msa

# 네트워크 정책 확인
kubectl get networkpolicy -n moremoremusic-msa

# Kafka 토픽 목록 확인
kubectl exec -n moremoremusic-msa kafka-secure-xxxxx-xxxxx -- \
  kafka-topics --bootstrap-server localhost:9092 --list

# 특정 토픽의 메시지 개수 확인
kubectl exec -n moremoremusic-msa kafka-secure-xxxxx-xxxxx -- \
  kafka-run-class kafka.tools.GetOffsetShell \
  --broker-list localhost:9092 --topic user-events
```

## 📚 추가 리소스

### 공식 문서
- [Kafka 공식 문서](https://kafka.apache.org/documentation/)
- [KafkaJS 가이드](https://kafka.js.org/docs/getting-started)
- [Kubernetes 네트워크 정책](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

### 팀 내부 리소스
- [MoreMoreMusic API 문서](https://github.com/Sekai-of-Code/MoreMoreMusic/wiki)
- [프로젝트 아키텍처 가이드](https://github.com/Sekai-of-Code/MoreMoreMusic/blob/main/ARCHITECTURE.md)
- [코딩 컨벤션](https://github.com/Sekai-of-Code/MoreMoreMusic/blob/main/CODING_CONVENTION.md)

---

**💡 도움이 필요하시면?**
- Slack: #moremoremusic-dev 채널
- 이슈 등록: [GitHub Issues](https://github.com/Sekai-of-Code/MoreMoreMusic-infra-repo/issues)
- 위키: [프로젝트 위키](https://github.com/Sekai-of-Code/MoreMoreMusic/wiki)

---
*이 문서는 MoreMoreMusic 개발팀을 위해 작성되었습니다. 🎵*