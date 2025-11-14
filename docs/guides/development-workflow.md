# 🎵 MoreMoreMusic 개발 워크플로우 가이드

> 팀 개발 효율성을 극대화하는 체계적인 개발 프로세스

## 📋 목차

1. [개발 환경 세팅](#개발-환경-세팅)
2. [Git 브랜치 전략](#git-브랜치-전략)
3. [기능 개발 워크플로우](#기능-개발-워크플로우)
4. [테스트 및 배포 프로세스](#테스트-및-배포-프로세스)
5. [코드 리뷰 가이드라인](#코드-리뷰-가이드라인)
6. [커뮤니케이션 규칙](#커뮤니케이션-규칙)

## 🛠️ 개발 환경 세팅

### 1. 로컬 개발환경 준비

#### 필수 도구 설치 체크리스트
```bash
# ✅ 설치 확인 명령어들
node --version          # Node.js 18+ 
npm --version           # npm 9+
docker --version        # Docker 24+
kubectl version         # kubectl 1.25+
helm version            # Helm 3.0+
git --version           # Git 2.30+
```

#### IDE 설정 (VS Code 권장)
```json
// .vscode/settings.json
{
  "editor.formatOnSave": true,
  "editor.codeActionsOnSave": {
    "source.fixAll.eslint": true
  },
  "typescript.preferences.includePackageJsonAutoImports": "on",
  "files.exclude": {
    "**/node_modules": true,
    "**/.git": true
  }
}

// .vscode/extensions.json (팀 공통 확장)
{
  "recommendations": [
    "ms-vscode.vscode-typescript-next",
    "bradlc.vscode-tailwindcss",
    "ms-vscode.vscode-json",
    "redhat.vscode-yaml",
    "ms-kubernetes-tools.vscode-kubernetes-tools"
  ]
}
```

### 2. 개발환경별 설정

#### 로컬 개발 (개인 PC)
```bash
# 개발용 Kubernetes 클러스터 실행
# Docker Desktop의 Kubernetes 활성화 또는
minikube start --driver=docker --memory=4096 --cpus=2

# MoreMoreMusic 네임스페이스 생성
kubectl create namespace moremoremusic-dev

# 개발용 인프라 배포
kubectl apply -f security.yaml
kubectl apply -f kafka.yaml

# 환경변수 설정
export KAFKA_BROKERS="kafka-service.moremoremusic-dev.svc.cluster.local:9092"
export NODE_ENV="development"
export LOG_LEVEL="debug"
```

#### 공유 개발 환경 (Staging)
```bash
# Staging 환경 접속
kubectl config use-context staging-cluster

# Staging용 네임스페이스
kubectl create namespace moremoremusic-staging

# Helm을 통한 전체 스택 배포
helm install moremoremusic ./helm/moremoremusic \
  --namespace moremoremusic-staging \
  --values values-development.yaml
```

## 🌿 Git 브랜치 전략

### 브랜치 구조 (Git Flow 변형)

```
main (프로덕션)
  ├── develop (개발 통합)
  │   ├── feature/user-auth (기능 개발)
  │   ├── feature/music-player (기능 개발) 
  │   └── feature/playlist-management (기능 개발)
  └── hotfix/critical-bug (긴급 수정)
```

### 브랜치 명명 규칙

| 브랜치 타입 | 패턴 | 예시 | 설명 |
|------------|------|------|------|
| **Feature** | `feature/[이슈번호]-[기능명]` | `feature/123-user-login` | 새 기능 개발 |
| **Bugfix** | `bugfix/[이슈번호]-[버그명]` | `bugfix/456-kafka-timeout` | 버그 수정 |
| **Hotfix** | `hotfix/[이슈번호]-[수정내용]` | `hotfix/789-security-patch` | 긴급 수정 |
| **Release** | `release/v[버전]` | `release/v1.2.0` | 릴리즈 준비 |

### 브랜치 생성 및 관리

```bash
# 1. 최신 develop 브랜치로 이동
git checkout develop
git pull origin develop

# 2. 새 기능 브랜치 생성
git checkout -b feature/123-user-login

# 3. 개발 완료 후 원격 브랜치에 푸시
git add .
git commit -m "✨ feat: 사용자 로그인 기능 구현

- JWT 토큰 기반 인증 시스템 구현
- Kafka로 로그인 이벤트 발송
- 유효성 검사 미들웨어 추가

Closes #123"

git push origin feature/123-user-login
```

## 🚀 기능 개발 워크플로우

### 1. 이슈 생성 및 계획

#### GitHub 이슈 템플릿 활용
```markdown
## 🎯 기능 요구사항

**기능 설명:**
사용자가 이메일과 비밀번호로 로그인할 수 있는 시스템

**수용 기준 (Acceptance Criteria):**
- [ ] 유효한 이메일과 비밀번호로 로그인 성공
- [ ] 잘못된 인증정보로 로그인 실패 
- [ ] JWT 토큰 발급 및 세션 관리
- [ ] Kafka로 로그인 이벤트 전송

**기술 요구사항:**
- User Service API 엔드포인트 구현
- Kafka 이벤트 발송 로직
- 프론트엔드 로그인 폼

**예상 작업 시간:** 2-3일
```

### 2. 로컬 개발 프로세스

#### A. 환경 준비
```bash
# 개발환경 상태 확인
./scripts/health-check.sh

# 필요 시 Kafka 토픽 생성
kubectl exec -n moremoremusic-dev kafka-secure-xxxxx -- \
  kafka-topics --bootstrap-server localhost:9092 \
  --create --topic user-events \
  --partitions 3 --replication-factor 1
```

#### B. 개발 및 테스트 사이클

```bash
# 1. 의존성 설치
npm install

# 2. 로컬 서버 실행
npm run dev

# 3. 실시간 테스트 (다른 터미널)
npm run test:watch

# 4. Kafka 이벤트 모니터링 (다른 터미널)
kubectl logs -f -n moremoremusic-dev kafka-secure-xxxxx
```

#### C. 실시간 통신 테스트

```javascript
// test/integration/user-login.test.js
const request = require('supertest');
const app = require('../../src/app');

describe('사용자 로그인 통합 테스트', () => {
  test('정상 로그인 시 Kafka 이벤트 발송', async (done) => {
    // Kafka Consumer로 이벤트 수신 확인
    const consumer = kafka.consumer({ groupId: 'test-group' });
    await consumer.subscribe({ topic: 'user-events' });
    
    let eventReceived = false;
    consumer.run({
      eachMessage: async ({ message }) => {
        const event = JSON.parse(message.value.toString());
        if (event.event === 'user_login') {
          eventReceived = true;
          done();
        }
      }
    });

    // 로그인 API 호출
    const response = await request(app)
      .post('/api/auth/login')
      .send({
        email: 'test@example.com',
        password: 'password123'
      });

    expect(response.status).toBe(200);
    expect(response.body.token).toBeDefined();
    
    // 5초 후 이벤트 수신 확인
    setTimeout(() => {
      expect(eventReceived).toBe(true);
      done();
    }, 5000);
  });
});
```

### 3. 커밋 컨벤션

#### 커밋 메시지 형식
```
<이모지> <타입>: <제목>

[본문]

[푸터]
```

#### 타입별 이모지
| 타입 | 이모지 | 설명 | 예시 |
|------|--------|------|------|
| **feat** | ✨ | 새 기능 추가 | `✨ feat: 사용자 로그인 API 구현` |
| **fix** | 🐛 | 버그 수정 | `🐛 fix: Kafka 연결 타임아웃 해결` |
| **docs** | 📝 | 문서 수정 | `📝 docs: API 문서 업데이트` |
| **style** | 💄 | 코드 스타일 수정 | `💄 style: ESLint 규칙 적용` |
| **refactor** | ♻️ | 리팩토링 | `♻️ refactor: 사용자 서비스 구조 개선` |
| **test** | ✅ | 테스트 추가/수정 | `✅ test: 로그인 통합 테스트 추가` |
| **chore** | 🔧 | 빌드/설정 변경 | `🔧 chore: Dockerfile 최적화` |

#### 좋은 커밋 예시
```bash
✨ feat: 사용자 로그인 기능 구현

- JWT 토큰 기반 인증 시스템 추가
- bcrypt를 이용한 비밀번호 해싱
- Kafka로 로그인 이벤트 발송 (user-events 토픽)
- 로그인 실패 시 적절한 에러 메시지 반환

Breaking Change: 기존 세션 기반에서 토큰 기반으로 변경
Co-authored-by: TeamMate <teammate@example.com>

Closes #123
```

## ✅ 테스트 및 배포 프로세스

### 1. 테스트 전략

#### 테스트 피라미드
```
        🔺 E2E Tests (적음, 느림, 비쌈)
       /   \
      /     \  Integration Tests (중간)
     /       \
    /         \
   /___________\ Unit Tests (많음, 빠름, 저렴)
```

#### 단위 테스트 (Unit Test)
```javascript
// test/unit/userService.test.js
const UserService = require('../../src/services/userService');
const { UserEventProducer } = require('../../src/kafka/producers');

jest.mock('../../src/kafka/producers');

describe('UserService', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test('정상적인 로그인 처리', async () => {
    // Given
    const mockUser = { id: 1, email: 'test@example.com' };
    const userService = new UserService();
    UserEventProducer.sendLoginEvent = jest.fn().mockResolvedValue(true);

    // When
    const result = await userService.login('test@example.com', 'password');

    // Then
    expect(result.success).toBe(true);
    expect(UserEventProducer.sendLoginEvent).toHaveBeenCalledWith(
      mockUser.id,
      expect.objectContaining({ ip: expect.any(String) })
    );
  });
});
```

#### 통합 테스트 (Integration Test)
```javascript
// test/integration/kafka-communication.test.js
describe('Kafka 통신 통합 테스트', () => {
  let producer, consumer;

  beforeAll(async () => {
    producer = kafka.producer();
    consumer = kafka.consumer({ groupId: 'test-group' });
    await producer.connect();
    await consumer.connect();
  });

  test('사용자 이벤트 송수신', async () => {
    const testEvent = {
      event: 'user_login',
      userId: 'test123',
      timestamp: new Date().toISOString()
    };

    // Producer로 메시지 전송
    await producer.send({
      topic: 'user-events',
      messages: [{ value: JSON.stringify(testEvent) }]
    });

    // Consumer로 메시지 수신 확인
    const receivedMessages = [];
    await consumer.subscribe({ topic: 'user-events' });
    
    await consumer.run({
      eachMessage: async ({ message }) => {
        receivedMessages.push(JSON.parse(message.value.toString()));
      }
    });

    // 메시지 수신 대기 (최대 5초)
    await new Promise(resolve => setTimeout(resolve, 5000));
    
    expect(receivedMessages).toContainEqual(testEvent);
  });
});
```

### 2. CI/CD 파이프라인

#### GitHub Actions 워크플로우
```yaml
# .github/workflows/ci.yml
name: CI/CD Pipeline

on:
  push:
    branches: [ develop, main ]
  pull_request:
    branches: [ develop ]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      kafka:
        image: confluentinc/cp-kafka:7.4.0
        env:
          KAFKA_PROCESS_ROLES: broker,controller
          KAFKA_NODE_ID: 1
          KAFKA_CONTROLLER_QUORUM_VOTERS: 1@localhost:9093
          KAFKA_LISTENERS: PLAINTEXT://localhost:9092,CONTROLLER://localhost:9093
        ports:
          - 9092:9092

    steps:
    - uses: actions/checkout@v3
    
    - name: Node.js 설정
      uses: actions/setup-node@v3
      with:
        node-version: '18'
        cache: 'npm'
    
    - name: 의존성 설치
      run: npm ci
    
    - name: 린트 검사
      run: npm run lint
    
    - name: 단위 테스트
      run: npm run test:unit
    
    - name: 통합 테스트
      run: npm run test:integration
      env:
        KAFKA_BROKERS: localhost:9092
    
    - name: 코드 커버리지 업로드
      uses: codecov/codecov-action@v3

  deploy-staging:
    needs: test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/develop'
    
    steps:
    - name: Staging 배포
      run: |
        helm upgrade moremoremusic ./helm/moremoremusic \
          --namespace moremoremusic-staging \
          --values values-development.yaml
```

### 3. 배포 전략

#### 단계적 배포 (Blue-Green Deployment)
```bash
# 1. Green 환경에 새 버전 배포
helm install moremoremusic-green ./helm/moremoremusic \
  --namespace moremoremusic-staging \
  --values values-development.yaml \
  --set app.version=v1.2.0

# 2. Green 환경 헬스체크
kubectl get pods -n moremoremusic-staging -l version=v1.2.0

# 3. 트래픽 전환 (Ingress 업데이트)
kubectl patch ingress moremoremusic -n moremoremusic-staging \
  --patch '{"spec":{"rules":[{"host":"staging.moremoremusic.com","http":{"paths":[{"path":"/","pathType":"Prefix","backend":{"service":{"name":"moremoremusic-green","port":{"number":80}}}}]}}]}}'

# 4. Blue 환경 정리
helm uninstall moremoremusic-blue -n moremoremusic-staging
```

## 👥 코드 리뷰 가이드라인

### 1. Pull Request 작성법

#### PR 템플릿
```markdown
## 📝 변경 사항 요약

**변경 유형:** 🐛 버그 수정 / ✨ 새 기능 / 📝 문서 / ♻️ 리팩토링

**관련 이슈:** Closes #123

## 🔄 변경 내용

- [ ] 사용자 로그인 API 엔드포인트 추가 (`POST /api/auth/login`)
- [ ] JWT 토큰 인증 미들웨어 구현
- [ ] Kafka 로그인 이벤트 발송 로직
- [ ] 로그인 통합 테스트 추가

## 🧪 테스트 결과

- [ ] 단위 테스트 통과 (Coverage: 95%)
- [ ] 통합 테스트 통과
- [ ] Kafka 이벤트 발송 확인
- [ ] 로컬 환경에서 E2E 테스트 완료

## 📸 스크린샷 / 데모

[로그인 화면 스크린샷 또는 API 테스트 결과]

## ⚠️ 리뷰 포인트

- 보안: JWT 토큰 만료 시간이 적절한지 확인
- 성능: Kafka 이벤트 발송이 API 응답을 지연시키지 않는지
- 에러 처리: 네트워크 오류 시 적절한 폴백 로직

## 🚀 배포 확인사항

- [ ] 환경변수 설정 확인
- [ ] Kafka 토픽 존재 여부
- [ ] 데이터베이스 마이그레이션 필요성
```

### 2. 코드 리뷰 체크리스트

#### 기능적 검토
- [ ] **요구사항 충족**: 이슈에서 요구한 모든 기능 구현됨
- [ ] **비즈니스 로직**: 도메인 규칙 정확히 반영됨
- [ ] **엣지 케이스**: 예외 상황 처리 완료
- [ ] **성능**: 응답시간 및 리소스 사용량 적절

#### 기술적 검토
- [ ] **코드 품질**: Clean Code 원칙 준수
- [ ] **아키텍처**: 기존 구조와 일관성 유지
- [ ] **보안**: 취약점 없음 (SQL 인젝션, XSS 등)
- [ ] **테스트**: 적절한 테스트 커버리지

#### Kafka 특화 검토
- [ ] **이벤트 스키마**: 메시지 구조 명확하고 일관됨
- [ ] **에러 처리**: Kafka 연결 실패 시 적절한 대응
- [ ] **성능**: Producer/Consumer 설정 최적화
- [ ] **순서 보장**: 필요 시 메시지 키 사용

### 3. 리뷰 코멘트 예시

#### ✅ 건설적인 피드백
```
🤔 생각해볼 점: Kafka 이벤트 발송 실패 시 사용자 로그인은 성공시키는게 맞을까요? 
이벤트는 중요하지만 핵심 기능을 방해하지 않도록 비동기로 처리하거나 재시도 로직을 고려해보면 어떨까요?

💡 제안: try-catch로 감싸고 실패 시 로깅만 하는 것은 어떨까요?

```javascript
try {
  await userEventProducer.sendLoginEvent(user.id, metadata);
} catch (error) {
  logger.error('로그인 이벤트 발송 실패', { userId: user.id, error });
  // 로그인은 계속 진행
}
```
```

#### ❌ 피해야 할 코멘트
```
이 코드는 잘못됐습니다. 다시 짜세요.
너무 복잡합니다.
```

## 💬 커뮤니케이션 규칙

### 1. Slack 채널 구성

| 채널 | 용도 | 알림 레벨 |
|------|------|----------|
| **#moremoremusic-dev** | 개발 관련 전반 | 전체 |
| **#moremoremusic-deploy** | 배포 알림 | 중요 |
| **#moremoremusic-alerts** | 시스템 장애 | 즉시 |
| **#moremoremusic-random** | 자유 토론 | 무음 |

### 2. 일일 스탠드업 미팅

#### 형식 (15분 이내)
```
👋 안녕하세요! 오늘의 스탠드업입니다.

🔄 어제 한 일:
- 사용자 로그인 API 구현 완료
- Kafka 이벤트 발송 테스트 완료

🎯 오늘 할 일:
- PR 리뷰 반영
- 음악 재생 이벤트 Producer 개발

🚧 블로커:
- Kafka 브로커 간헐적 연결 실패 (DevOps 팀과 협의 중)
```

### 3. 이슈 관리

#### 이슈 라벨 시스템
```
우선순위:
🔴 priority/critical (즉시 처리)
🟠 priority/high (24시간 내)
🟡 priority/medium (이번 주)
🟢 priority/low (다음 스프린트)

타입:
🐛 type/bug
✨ type/feature  
📝 type/docs
🔧 type/chore

상태:
👀 status/review (리뷰 중)
⚡ status/in-progress (진행 중)  
✅ status/done (완료)
❌ status/blocked (블로킹)
```

### 4. 문서화 규칙

#### API 문서화 (OpenAPI/Swagger)
```yaml
# swagger/user-auth.yaml
paths:
  /api/auth/login:
    post:
      summary: 사용자 로그인
      description: |
        이메일과 비밀번호로 사용자 인증을 수행합니다.
        성공 시 JWT 토큰을 반환하고 Kafka로 로그인 이벤트를 발송합니다.
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                email:
                  type: string
                  format: email
                password:
                  type: string
                  minLength: 6
      responses:
        200:
          description: 로그인 성공
          content:
            application/json:
              schema:
                type: object
                properties:
                  success:
                    type: boolean
                    example: true
                  token:
                    type: string
                    description: JWT 인증 토큰
                  user:
                    $ref: '#/components/schemas/User'
```

#### 이벤트 스키마 문서화
```javascript
/**
 * 사용자 로그인 이벤트
 * Topic: user-events
 * 
 * @example
 * {
 *   "event": "user_login",
 *   "userId": "user_12345",
 *   "timestamp": "2024-01-15T10:30:00Z",
 *   "metadata": {
 *     "ip": "192.168.1.100",
 *     "device": "mobile",
 *     "userAgent": "Mozilla/5.0 ..."
 *   }
 * }
 */
const USER_LOGIN_EVENT_SCHEMA = {
  event: 'user_login',
  userId: { type: String, required: true },
  timestamp: { type: String, format: 'ISO8601', required: true },
  metadata: {
    ip: { type: String },
    device: { type: String, enum: ['web', 'mobile', 'desktop'] },
    userAgent: { type: String }
  }
};
```

---

## 📊 성과 측정 및 개선

### 주간 회고 미팅
```
📊 이번 주 메트릭:
- 완료한 이슈: 15개
- 평균 PR 리뷰 시간: 4시간
- 배포 횟수: 3회
- 버그 발견: 2개

🎯 잘한 점:
- Kafka 이벤트 통합 테스트 도입
- 코드 리뷰 품질 향상

🔧 개선점:
- 통합 테스트 실행 시간 단축 필요
- 문서화 자동화 도구 도입 검토

📋 다음 주 목표:
- 성능 테스트 환경 구축
- 모니터링 대시보드 개선
```

---

**🎵 함께 만들어가는 MoreMoreMusic!**

이 워크플로우는 팀의 성장과 함께 계속 진화해갑니다. 
더 나은 개발 프로세스에 대한 아이디어가 있다면 언제든 공유해주세요! 

**📞 문의사항:**
- Slack: #moremoremusic-dev
- 이슈: [GitHub Repository](https://github.com/Sekai-of-Code/MoreMoreMusic-infra-repo)

---
*효율적이고 즐거운 개발을 위해! 🚀*