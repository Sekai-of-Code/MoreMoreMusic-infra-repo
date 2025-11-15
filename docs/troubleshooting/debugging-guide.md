# 🔧 MoreMoreMusic 문제해결 및 디버깅 가이드

> 개발 중 발생할 수 있는 모든 문제에 대한 체계적인 해결 방법

## 📋 목차

1. [빠른 진단 체크리스트](#빠른-진단-체크리스트)
2. [Kubernetes 관련 문제](#kubernetes-관련-문제)
3. [Kafka 통신 문제](#kafka-통신-문제)
4. [네트워크 및 보안 문제](#네트워크-및-보안-문제)
5. [성능 관련 문제](#성능-관련-문제)
6. [로깅 및 모니터링](#로깅-및-모니터링)
7. [응급상황 대응](#응급상황-대응)

## ⚡ 빠른 진단 체크리스트

### 🔍 5분 진단 스크립트

```bash
#!/bin/bash
echo "🔍 MoreMoreMusic 개발환경 진단 시작..."

# 1. Kubernetes 클러스터 상태
echo "📊 클러스터 상태:"
kubectl cluster-info

# 2. Pod 상태 확인  
echo "📦 Pod 상태:"
kubectl get pods -n moremoremusic-msa

# 3. 서비스 엔드포인트 확인
echo "🌐 서비스 상태:"
kubectl get svc -n moremoremusic-msa

# 4. Kafka 브로커 상태
echo "📨 Kafka 상태:"
kubectl exec -n moremoremusic-msa kafka-secure-$(kubectl get pods -n moremoremusic-msa -l app.kubernetes.io/name=kafka -o jsonpath='{.items[0].metadata.name}' | cut -d'-' -f3-) -- \
  kafka-broker-api-versions --bootstrap-server localhost:9092 | head -3

# 5. 리소스 사용률
echo "💻 리소스 사용률:"
kubectl top nodes 2>/dev/null || echo "메트릭 서버 없음"

echo "✅ 진단 완료!"
```

### 🚨 문제 유형별 빠른 체크

| 증상             | 가능한 원인                | 빠른 확인                   |
| ---------------- | -------------------------- | --------------------------- |
| Pod 계속 재시작  | 리소스 부족, 설정 오류     | `kubectl describe pod`      |
| 서비스 접근 불가 | 네트워크 정책, DNS 문제    | `kubectl get networkpolicy` |
| Kafka 연결 실패  | 브로커 다운, 권한 문제     | `kafka-broker-api-versions` |
| 메시지 처리 안됨 | Consumer 오류, 토픽 없음   | `kafka-topics --list`       |
| 느린 응답 속도   | 리소스 부족, 네트워크 지연 | `kubectl top pods`          |

## 🚢 Kubernetes 관련 문제

### 1. Pod가 시작되지 않는 문제

#### 증상
```bash
NAME                     READY   STATUS             RESTARTS   AGE
kafka-secure-xxxxx       0/1     CrashLoopBackOff   5          10m
```

#### 진단 방법
```bash
# Pod 상세 정보 확인
kubectl describe pod -n moremoremusic-msa kafka-secure-xxxxx

# Pod 로그 확인
kubectl logs -n moremoremusic-msa kafka-secure-xxxxx --previous

# 이벤트 확인
kubectl get events -n moremoremusic-msa --sort-by=.metadata.creationTimestamp
```

#### 해결 방법

**A. 이미지 풀 실패**
```bash
# 이미지 존재 확인
docker pull confluentinc/cp-kafka:7.4.0

# 이미지 태그 확인
kubectl get deployment -n moremoremusic-msa kafka-secure -o yaml | grep image
```

**B. 리소스 부족**
```bash
# 노드 리소스 확인
kubectl top nodes

# 리소스 요청량 조정
kubectl patch deployment -n moremoremusic-msa kafka-secure \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"kafka","resources":{"requests":{"memory":"256Mi","cpu":"100m"}}}]}}}}'
```

#### C. 설정 오류
```bash
# ConfigMap 확인
kubectl get configmap -n moremoremusic-msa

# 환경변수 확인
kubectl get deployment -n moremoremusic-msa kafka-secure -o yaml | grep -A 20 env
```

### 2. Pod 간 통신 안되는 문제

#### 증상
```bash
# Pod에서 다른 서비스에 접근 안됨
kubectl exec -it test-pod -- curl kafka-service:9092
# curl: (7) Failed to connect to kafka-service port 9092: Connection refused
```

#### 진단 방법
```bash
# 네트워크 정책 확인
kubectl get networkpolicy -n moremoremusic-msa

# 서비스 엔드포인트 확인  
kubectl get endpoints -n moremoremusic-msa

# DNS 해상도 테스트
kubectl exec -it test-pod -- nslookup kafka-service.moremoremusic-msa.svc.cluster.local
```

#### 해결 방법

#### A. 네트워크 정책 문제
```bash
# 올바른 라벨로 Pod 생성
kubectl run test-pod \
  --labels="app.kubernetes.io/part-of=moremoremusic,tier=backend" \
  --image=busybox --rm -it --restart=Never -- \
  nc -zv kafka-service.moremoremusic-msa.svc.cluster.local 9092
```

#### B. 서비스 셀렉터 문제
```bash
# 서비스 설정 확인
kubectl get svc kafka-service -n moremoremusic-msa -o yaml

# Pod 라벨 확인
kubectl get pods -n moremoremusic-msa --show-labels
```

### 3. 네임스페이스 권한 문제

#### 증상
```bash
# RBAC 권한 부족
Error from server (Forbidden): pods is forbidden: User cannot create resource "pods" in API group
```

#### 해결 방법
```bash
# 서비스 계정 확인
kubectl get serviceaccount -n moremoremusic-msa

# Role 및 RoleBinding 확인
kubectl get role,rolebinding -n moremoremusic-msa

# 권한 테스트
kubectl auth can-i create pods --namespace=moremoremusic-msa \
  --as=system:serviceaccount:moremoremusic-msa:kafka-service-account
```

## 📨 Kafka 통신 문제

### 1. Kafka 브로커 연결 실패

#### 증상
```javascript
// Node.js 에러 로그
KafkaJSConnectionError: Connection timeout
```

#### 진단 방법
```bash
# Kafka 브로커 상태 확인
kubectl exec -n moremoremusic-msa kafka-secure-xxxxx -- \
  kafka-broker-api-versions --bootstrap-server localhost:9092

# 네트워크 연결 테스트
kubectl exec -n moremoremusic-msa kafka-secure-xxxxx -- \
  nc -zv kafka-service.moremoremusic-msa.svc.cluster.local 9092

# Kafka 로그 확인
kubectl logs -f -n moremoremusic-msa kafka-secure-xxxxx
```

#### 해결 방법

#### A. 브로커 설정 문제
```bash
# KAFKA_ADVERTISED_LISTENERS 확인
kubectl get deployment -n moremoremusic-msa kafka-secure -o yaml | \
  grep -A 5 KAFKA_ADVERTISED_LISTENERS

# 올바른 설정으로 수정
kubectl patch deployment -n moremoremusic-msa kafka-secure \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"kafka","env":[{"name":"KAFKA_ADVERTISED_LISTENERS","value":"PLAINTEXT://kafka-service:9092"}]}]}}}}'
```

#### B. 네트워크 정책 차단
```bash
# 애플리케이션 Pod에 올바른 라벨 추가 확인
kubectl label pod your-app-pod app.kubernetes.io/part-of=moremoremusic --overwrite
```

### 2. 토픽 관련 문제

#### 증상
```javascript
// Unknown topic or partition 에러
TopicAuthorizationException: Not authorized to access topics: [user-events]
```

#### 진단 방법
```bash
# 토픽 목록 확인
kubectl exec -n moremoremusic-msa kafka-secure-xxxxx -- \
  kafka-topics --bootstrap-server localhost:9092 --list

# 특정 토픽 상세 정보
kubectl exec -n moremoremusic-msa kafka-secure-xxxxx -- \
  kafka-topics --bootstrap-server localhost:9092 --describe --topic user-events
```

#### 해결 방법

#### A. 토픽 생성
```bash
# 필요한 토픽 생성
kubectl exec -n moremoremusic-msa kafka-secure-xxxxx -- \
  kafka-topics --bootstrap-server localhost:9092 \
  --create --topic user-events \
  --partitions 3 --replication-factor 1

# 토픽 설정 확인
kubectl exec -n moremoremusic-msa kafka-secure-xxxxx -- \
  kafka-configs --bootstrap-server localhost:9092 \
  --entity-type topics --entity-name user-events --describe
```

#### B. 자동 토픽 생성 활성화
```bash
# Kafka 설정에서 auto.create.topics.enable=true 확인
kubectl exec -n moremoremusic-msa kafka-secure-xxxxx -- \
  kafka-configs --bootstrap-server localhost:9092 \
  --entity-type brokers --entity-name 1 --describe | grep auto.create
```

### 3. Consumer Group 문제

#### 증상
```javascript
// Consumer가 메시지를 받지 못함
No messages received after 30 seconds
```

#### 진단 방법
```bash
# Consumer Group 상태 확인
kubectl exec -n moremoremusic-msa kafka-secure-xxxxx -- \
  kafka-consumer-groups --bootstrap-server localhost:9092 \
  --group music-service-group --describe

# 토픽 오프셋 확인
kubectl exec -n moremoremusic-msa kafka-secure-xxxxx -- \
  kafka-run-class kafka.tools.GetOffsetShell \
  --broker-list localhost:9092 --topic user-events
```

#### 해결 방법

#### A. Consumer 오프셋 리셋
```bash
# Consumer Group 오프셋 리셋 (주의: 메시지 재처리됨)
kubectl exec -n moremoremusic-msa kafka-secure-xxxxx -- \
  kafka-consumer-groups --bootstrap-server localhost:9092 \
  --group music-service-group --reset-offsets \
  --to-earliest --topic user-events --execute
```

#### B. Dead Consumer 제거
```bash
# 비활성 Consumer 확인 및 제거
kubectl exec -n moremoremusic-msa kafka-secure-xxxxx -- \
  kafka-consumer-groups --bootstrap-server localhost:9092 \
  --group music-service-group --delete
```

## 🔐 네트워크 및 보안 문제

### 1. NetworkPolicy로 인한 접근 차단

#### 증상
```bash
# 승인되지 않은 접근 시도
connection refused 또는 timeout 발생
```

#### 진단 방법
```bash
# NetworkPolicy 규칙 확인
kubectl describe networkpolicy -n moremoremusic-msa

# Pod 라벨 확인
kubectl get pods -n moremoremusic-msa --show-labels

# 네트워크 연결 테스트
kubectl run debug-pod \
  --labels="app.kubernetes.io/part-of=moremoremusic" \
  --image=busybox --rm -it --restart=Never -- \
  nc -zv kafka-service.moremoremusic-msa.svc.cluster.local 9092
```

#### 해결 방법

#### A. 올바른 라벨 추가
```yaml
# Pod에 필요한 라벨 추가
apiVersion: v1
kind: Pod
metadata:
  labels:
    app.kubernetes.io/part-of: moremoremusic
    tier: backend
```

#### B. NetworkPolicy 임시 비활성화 (디버깅용)
```bash
# 주의: 보안상 위험하므로 디버깅 용도로만 사용
kubectl delete networkpolicy -n moremoremusic-msa --all

# 문제 해결 후 다시 적용
kubectl apply -f security.yaml
```

### 2. RBAC 권한 문제

#### 증상
```bash
# ServiceAccount 권한 부족
Error: pods is forbidden: User cannot list resource "pods"
```

#### 해결 방법
```bash
# ServiceAccount 권한 확인
kubectl describe rolebinding -n moremoremusic-msa

# 추가 권한 부여 (예: EndpointSlice 권한)
kubectl patch role -n moremoremusic-msa msa-pod-reader \
  --type='json' \
  -p='[{"op": "add", "path": "/rules/-", "value": {"apiGroups": ["discovery.k8s.io"], "resources": ["endpointslices"], "verbs": ["get", "list", "watch", "create", "update", "patch"]}}]'
```

## ⚡ 성능 관련 문제

### 1. 높은 CPU/메모리 사용률

#### 진단 방법
```bash
# 리소스 사용률 모니터링
kubectl top nodes
kubectl top pods -n moremoremusic-msa

# Pod 상세 리소스 정보
kubectl describe pod -n moremoremusic-msa kafka-secure-xxxxx | grep -A 10 Requests
```

#### 해결 방법

#### A. 리소스 제한 조정
```bash
# Kafka Pod 리소스 늘리기
kubectl patch deployment -n moremoremusic-msa kafka-secure \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"kafka","resources":{"requests":{"memory":"1Gi","cpu":"500m"},"limits":{"memory":"2Gi","cpu":"1"}}}]}}}}'
```

#### B. HPA 설정 (Horizontal Pod Autoscaler)
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: kafka-hpa
  namespace: moremoremusic-msa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: kafka-secure
  minReplicas: 1
  maxReplicas: 3
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

### 2. 메시지 처리 지연

#### 진단 방법
```bash
# Consumer Lag 확인
kubectl exec -n moremoremusic-msa kafka-secure-xxxxx -- \
  kafka-consumer-groups --bootstrap-server localhost:9092 \
  --group music-service-group --describe

# 토픽별 처리량 확인
kubectl exec -n moremoremusic-msa kafka-secure-xxxxx -- \
  kafka-log-dirs --bootstrap-server localhost:9092 \
  --describe | grep -A 5 user-events
```

#### 해결 방법

#### A. Consumer 병렬 처리 증가
```javascript
// Consumer 설정 최적화
const consumer = kafka.consumer({
  groupId: 'music-service-group',
  maxBytesPerPartition: 1048576,  // 1MB
  minBytes: 1,
  maxWaitTimeInMs: 1000
});

// 여러 Consumer 인스턴스 실행
for (let i = 0; i < 3; i++) {
  const consumer = kafka.consumer({
    groupId: `music-service-group-${i}`
  });
  consumer.run(/* ... */);
}
```

#### B. 파티션 수 증가
```bash
# 토픽 파티션 추가 (주의: 줄일 수는 없음)
kubectl exec -n moremoremusic-msa kafka-secure-xxxxx -- \
  kafka-topics --bootstrap-server localhost:9092 \
  --alter --topic user-events --partitions 6
```

## 📊 로깅 및 모니터링

### 1. 로그 수집 및 분석

#### Kafka 로그 모니터링
```bash
# 실시간 로그 확인
kubectl logs -f -n moremoremusic-msa kafka-secure-xxxxx

# 에러 로그만 필터링
kubectl logs -n moremoremusic-msa kafka-secure-xxxxx | grep -i error

# 특정 시간대 로그
kubectl logs -n moremoremusic-msa kafka-secure-xxxxx \
  --since-time=2024-01-15T10:00:00Z | grep "2024-01-15T10" | head -n 1000
```

#### 애플리케이션 로그 구조화
```javascript
// 구조화된 로깅 예시
const logger = {
  info: (message, meta = {}) => {
    console.log(JSON.stringify({
      level: 'INFO',
      timestamp: new Date().toISOString(),
      message: message,
      service: process.env.SERVICE_NAME,
      ...meta
    }));
  },
  
  error: (message, error, meta = {}) => {
    console.error(JSON.stringify({
      level: 'ERROR', 
      timestamp: new Date().toISOString(),
      message: message,
      error: {
        message: error.message,
        stack: error.stack
      },
      service: process.env.SERVICE_NAME,
      ...meta
    }));
  }
};

// 사용 예시
logger.info('Kafka 메시지 전송', {
  topic: 'user-events',
  userId: 'user123'
});
```

### 2. 메트릭 수집

#### Custom Metrics 수집기
```javascript
// metrics.js - 메트릭 수집 모듈
class MetricsCollector {
  constructor() {
    this.metrics = {
      kafka: {
        messagesSent: 0,
        messagesReceived: 0,
        errors: 0,
        avgLatency: 0
      },
      http: {
        requests: 0,
        errors: 0,
        avgResponseTime: 0
      }
    };
    
    // 주기적으로 메트릭 출력
    setInterval(() => this.reportMetrics(), 60000);
  }
  
  recordKafkaMessage(type, latency = 0) {
    if (type === 'sent') this.metrics.kafka.messagesSent++;
    if (type === 'received') this.metrics.kafka.messagesReceived++;
    if (latency > 0) this.updateLatency(latency);
  }
  
  recordError(component) {
    if (component === 'kafka') this.metrics.kafka.errors++;
    if (component === 'http') this.metrics.http.errors++;
  }
  
  reportMetrics() {
    console.log('📊 메트릭 리포트:', JSON.stringify(this.metrics, null, 2));
    
    // 필요시 외부 모니터링 시스템으로 전송
    // this.sendToPrometheus(this.metrics);
  }
}

module.exports = new MetricsCollector();
```

## 🚨 응급상황 대응

### 1. Kafka 브로커 완전 다운

#### 응급 복구 절차
```bash
# 1단계: 브로커 상태 확인
kubectl get pods -n moremoremusic-msa | grep kafka

# 2단계: Pod 강제 재시작  
kubectl delete pod -n moremoremusic-msa kafka-secure-xxxxx

# 3단계: 데이터 손실 확인
kubectl exec -n moremoremusic-msa kafka-secure-xxxxx -- \
  kafka-log-dirs --bootstrap-server localhost:9092 --describe

# 4단계: 토픽 복구 확인
kubectl exec -n moremoremusic-msa kafka-secure-xxxxx -- \
  kafka-topics --bootstrap-server localhost:9092 --list
```

#### 데이터 백업 및 복원
```bash
# 토픽 설정 백업
kubectl exec -n moremoremusic-msa kafka-secure-xxxxx -- \
  kafka-configs --bootstrap-server localhost:9092 \
  --entity-type topics --describe > kafka-topics-backup.txt

# 필요시 토픽 재생성
while read topic; do
  kubectl exec -n moremoremusic-msa kafka-secure-xxxxx -- \
    kafka-topics --bootstrap-server localhost:9092 \
    --create --topic $topic --partitions 3 --replication-factor 1
done < topic-list.txt
```

### 2. 전체 네임스페이스 문제

#### 네임스페이스 재구성
```bash
# 1. 현재 상태 백업
kubectl get all -n moremoremusic-msa -o yaml > namespace-backup.yaml

# 2. 네임스페이스 재생성 (최후 수단)
kubectl delete namespace moremoremusic-msa
kubectl create namespace moremoremusic-msa

# 3. 리소스 재배포
kubectl apply -f security.yaml
kubectl apply -f kafka.yaml
kubectl apply -f services.yaml
```

### 3. 긴급 로그 수집

#### 문제 상황 스냅샷 생성
```bash
#!/bin/bash
# emergency-debug.sh

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEBUG_DIR="debug_${TIMESTAMP}"
mkdir -p $DEBUG_DIR

echo "🚨 긴급 디버그 정보 수집 중..."

# 클러스터 정보
kubectl cluster-info > $DEBUG_DIR/cluster-info.txt
kubectl get nodes -o wide > $DEBUG_DIR/nodes.txt

# Pod 상태
kubectl get pods -A > $DEBUG_DIR/all-pods.txt
kubectl get pods -n moremoremusic-msa -o yaml > $DEBUG_DIR/msa-pods.yaml

# 서비스 정보
kubectl get svc -A > $DEBUG_DIR/services.txt
kubectl get endpoints -n moremoremusic-msa > $DEBUG_DIR/endpoints.txt

# 이벤트 수집
kubectl get events -A --sort-by=.metadata.creationTimestamp > $DEBUG_DIR/events.txt

# 로그 수집
for pod in $(kubectl get pods -n moremoremusic-msa -o jsonpath='{.items[*].metadata.name}'); do
  kubectl logs -n moremoremusic-msa $pod > $DEBUG_DIR/logs_${pod}.txt 2>&1
done

# 네트워크 정책
kubectl get networkpolicy -n moremoremusic-msa -o yaml > $DEBUG_DIR/networkpolicy.yaml

echo "✅ 디버그 정보 수집 완료: $DEBUG_DIR"
tar -czf $DEBUG_DIR.tar.gz $DEBUG_DIR/
echo "📦 압축 파일 생성: $DEBUG_DIR.tar.gz"
```

## 📞 지원 요청 시 준비사항

### 버그 리포트 템플릿

```markdown
## 🐛 버그 리포트

**환경 정보:**
- Kubernetes 버전: 
- Kafka 이미지: 
- Node.js 버전:
- 운영체제:

**증상:**
[구체적인 에러 메시지나 예상과 다른 동작]

**재현 방법:**
1. 
2. 
3. 

**예상 동작:**
[정상적으로 동작할 때의 모습]

**첨부 파일:**
- [ ] 에러 로그
- [ ] kubectl describe 출력
- [ ] 네트워크 다이어그램
- [ ] 설정 파일

**추가 정보:**
[관련된 다른 정보나 시도해본 해결방법]
```

---

## 📚 유용한 명령어 모음

### 자주 사용하는 디버깅 명령어
```bash
# 전체 시스템 상태 한눈에 보기
kubectl get all -A | grep moremoremusic

# 특정 Pod 완전 정보
kubectl describe pod -n moremoremusic-msa [POD_NAME]

# 모든 로그 동시 확인
kubectl logs -f -n moremoremusic-msa -l app.kubernetes.io/part-of=moremoremusic

# 네트워크 연결 테스트
kubectl run test --image=busybox --rm -it --restart=Never -- \
  wget -qO- http://kafka-service.moremoremusic-msa.svc.cluster.local:9092

# 리소스 사용률 모니터링
watch kubectl top pods -n moremoremusic-msa
```

---

**💡 기억하세요:**
- 문제 해결 시 항상 로그를 먼저 확인하세요
- 변경사항은 작은 단위로 테스트하세요  
- 중요한 설정은 백업해두세요
- 의심스러울 때는 팀에 문의하세요

**🆘 긴급 연락처:**
- Slack: #moremoremusic-support
- 이슈 트래커: [GitHub Issues](https://github.com/Sekai-of-Code/MoreMoreMusic-infra-repo/issues)

---
*안전하고 즐거운 개발되세요! 🎵*