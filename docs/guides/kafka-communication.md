# 🎵 MoreMoreMusic Kafka 통신 완전 가이드

> Kafka를 처음 접하는 개발자도 쉽게 이해할 수 있는 실전 통신 가이드

## 📋 목차

1. [Kafka 기초 개념](#kafka-기초-개념)
2. [MoreMoreMusic 메시지 아키텍처](#moremoremusic-메시지-아키텍처)
3. [실전 구현 예제](#실전-구현-예제)
4. [토픽 설계 가이드](#토픽-설계-가이드)
5. [에러 처리 및 재시도](#에러-처리-및-재시도)
6. [성능 최적화](#성능-최적화)
7. [모니터링 및 디버깅](#모니터링-및-디버깅)

## 🎯 Kafka 기초 개념

### Kafka란 무엇인가요?

**Kafka**는 여러 서비스가 서로 메시지를 주고받을 수 있게 해주는 **메시지 중계 시스템**입니다.

### 일상생활 비유로 이해하기

```
🏠 집 (User Service)          📮 우체통 (Kafka)           🎵 음악방 (Music Service)
    │                            │                            │
    "음악 틀어줘!" ──────────────→ [메시지 저장] ──────────────→ "네, 음악 재생할게요!"
```

카카오톡 그룹채팅과 비슷하다고 생각하세요:
- **메시지 전송**: 누군가 그룹채팅에 메시지를 보냄 (Producer)
- **메시지 저장**: 카카오톡 서버에 메시지가 저장됨 (Topic)
- **메시지 확인**: 다른 사람들이 메시지를 확인함 (Consumer)

### 핵심 용어 정리

| 용어          | 카카오톡 비유      | MoreMoreMusic 예시                    |
| ------------- | ------------------ | ------------------------------------- |
| **Producer**  | 메시지 보내는 사람 | User Service (로그인 알림)            |
| **Consumer**  | 메시지 읽는 사람   | Music Service (알림 받음)             |
| **Topic**     | 그룹채팅방         | `user-events`, `music-events`         |
| **Message**   | 채팅 메시지        | `{"event": "login", "userId": "123"}` |
| **Partition** | 채팅방 내 스레드   | 메시지를 빠르게 처리하기 위한 분할    |
| **Broker**    | 카카오톡 서버      | Kafka 서버                            |

## 🏗️ MoreMoreMusic 메시지 아키텍처

### 이벤트 플로우 설계

```
📱 사용자 행동                🎵 시스템 반응
    │                            │
    ├─ 로그인 ─────────────────→ 추천음악 준비
    ├─ 음악 재생 ──────────────→ 플레이리스트 업데이트  
    ├─ 좋아요 ────────────────→ 취향 분석
    └─ 플레이리스트 생성 ────────→ 친구들에게 알림
```

### Topic 구조

#### 1. `user-events` 토픽
```json
{
  "event": "user_login",
  "userId": "user_12345",
  "timestamp": "2024-01-15T10:30:00Z",
  "metadata": {
    "ip": "192.168.1.100",
    "device": "mobile",
    "location": "Seoul"
  }
}
```

#### 2. `music-events` 토픽  
```json
{
  "event": "song_played",
  "userId": "user_12345", 
  "songId": "song_67890",
  "timestamp": "2024-01-15T10:35:00Z",
  "metadata": {
    "duration": 180,
    "genre": "J-Pop",
    "quality": "320kbps"
  }
}
```

#### 3. `playlist-events` 토픽
```json
{
  "event": "playlist_created",
  "userId": "user_12345",
  "playlistId": "playlist_abc",
  "timestamp": "2024-01-15T11:00:00Z",
  "metadata": {
    "name": "내 애니송 모음",
    "isPublic": true,
    "songCount": 25
  }
}
```

## 💻 실전 구현 예제

### 1. KafkaJS 설정 및 연결

#### 기본 설정 (config/kafka.js)
```javascript
const { Kafka, logLevel } = require('kafkajs');

// Kafka 클라이언트 설정
const kafka = new Kafka({
  clientId: process.env.SERVICE_NAME || 'moremoremusic-service',
  brokers: [process.env.KAFKA_BROKERS || 'kafka-service:9092'],
  
  // 재시도 설정 (중요!)
  retry: {
    initialRetryTime: 100,
    retries: 8
  },
  
  // 로그 설정
  logLevel: process.env.NODE_ENV === 'production' ? logLevel.WARN : logLevel.INFO
});

module.exports = kafka;
```

### 2. Producer 구현 (메시지 보내기)

#### User Service - 로그인 이벤트 발송
```javascript
// services/userEventProducer.js
const kafka = require('../config/kafka');

class UserEventProducer {
  constructor() {
    this.producer = kafka.producer({
      // 메시지 전송 성능 최적화
      maxInFlightRequests: 1,
      idempotent: true,
      transactionTimeout: 30000
    });
    this.isConnected = false;
  }

  async connect() {
    if (!this.isConnected) {
      await this.producer.connect();
      this.isConnected = true;
      console.log('✅ Kafka Producer 연결 완료');
    }
  }

  // 사용자 로그인 이벤트
  async sendLoginEvent(userId, metadata = {}) {
    try {
      await this.connect();
      
      const message = {
        event: 'user_login',
        userId: userId,
        timestamp: new Date().toISOString(),
        metadata: {
          ip: metadata.ip,
          device: metadata.device,
          userAgent: metadata.userAgent
        }
      };

      const result = await this.producer.send({
        topic: 'user-events',
        messages: [
          {
            // 같은 사용자 메시지는 같은 파티션으로 (순서 보장)
            key: userId,
            value: JSON.stringify(message),
            // 메시지 헤더 (메타데이터)
            headers: {
              'content-type': 'application/json',
              'event-type': 'user_login',
              'source-service': 'user-service'
            }
          }
        ]
      });

      console.log(`🚀 로그인 이벤트 전송 완료: ${userId}`);
      return result;
    } catch (error) {
      console.error('❌ 로그인 이벤트 전송 실패:', error);
      throw error;
    }
  }

  // 사용자 로그아웃 이벤트
  async sendLogoutEvent(userId, sessionDuration) {
    try {
      const message = {
        event: 'user_logout',
        userId: userId,
        timestamp: new Date().toISOString(),
        metadata: {
          sessionDuration: sessionDuration
        }
      };

      await this.producer.send({
        topic: 'user-events',
        messages: [{
          key: userId,
          value: JSON.stringify(message)
        }]
      });

      console.log(`👋 로그아웃 이벤트 전송: ${userId}`);
    } catch (error) {
      console.error('❌ 로그아웃 이벤트 전송 실패:', error);
      throw error;
    }
  }

  async disconnect() {
    if (this.isConnected) {
      await this.producer.disconnect();
      this.isConnected = false;
      console.log('🔌 Kafka Producer 연결 해제');
    }
  }
}

module.exports = UserEventProducer;
```

#### Music Service - 음악 재생 이벤트 발송
```javascript
// services/musicEventProducer.js  
const kafka = require('../config/kafka');

class MusicEventProducer {
  constructor() {
    this.producer = kafka.producer();
    this.isConnected = false;
  }

  async connect() {
    if (!this.isConnected) {
      await this.producer.connect();
      this.isConnected = true;
    }
  }

  // 음악 재생 시작 이벤트
  async sendPlayEvent(userId, songId, playlistId = null) {
    try {
      await this.connect();
      const message = {
        event: 'song_play_started',
        userId: userId,
        songId: songId,
        playlistId: playlistId,
        timestamp: new Date().toISOString(),
        metadata: {
          quality: '320kbps',
          device: 'web'
        }
      };

      await this.producer.send({
        topic: 'music-events',
        messages: [{
          key: `${userId}_${songId}`,
          value: JSON.stringify(message)
        }]
      });

      console.log(`🎵 재생 시작 이벤트: ${songId} by ${userId}`);
    } catch (error) {
      console.error('❌ 재생 이벤트 전송 실패:', error);
    }
  }

  // 음악 재생 완료 이벤트
  async sendPlayCompleteEvent(userId, songId, actualDuration) {
    try {
      await this.connect();

      const message = {
        event: 'song_play_completed',
        userId: userId,
        songId: songId,
        timestamp: new Date().toISOString(),
        metadata: {
          duration: actualDuration,
          completion_rate: 1.0
        }
      };

      await this.producer.send({
        topic: 'music-events',
        messages: [{
          key: `${userId}_${songId}`,
          value: JSON.stringify(message)
        }]
      });

      console.log(`✅ 재생 완료 이벤트: ${songId}`);
    } catch (error) {
      console.error('❌ 재생 완료 이벤트 전송 실패:', error);
    }
  }
}

module.exports = MusicEventProducer;
```

### 3. Consumer 구현 (메시지 받기)

#### Music Service - 사용자 이벤트 구독
```javascript
// services/userEventConsumer.js
const kafka = require('../config/kafka');

class UserEventConsumer {
  constructor() {
    this.consumer = kafka.consumer({
      groupId: 'music-service-group',
      // 메시지를 놓치지 않도록 설정
      sessionTimeout: 30000,
      heartbeatInterval: 3000
    });
  }

  async start() {
    // Kafka 연결
    await this.consumer.connect();
    console.log('🔌 Music Service Consumer 연결됨');

    // user-events 토픽 구독
    await this.consumer.subscribe({ 
      topic: 'user-events',
      fromBeginning: false // 새로운 메시지만 처리
    });

    // 메시지 처리 시작
    await this.consumer.run({
      // 각 메시지 처리
      eachMessage: async ({ topic, partition, message }) => {
        try {
          const event = JSON.parse(message.value.toString());
          console.log(`📨 이벤트 수신 [${topic}]: ${event.event}`);

          // 이벤트 타입별 처리 분기
          await this.handleUserEvent(event);
          
        } catch (error) {
          console.error('❌ 메시지 처리 실패:', error);
          // 에러 로깅 또는 Dead Letter Queue로 전송
        }
      }
    });
  }

  async handleUserEvent(event) {
    switch (event.event) {
      case 'user_login':
        await this.handleUserLogin(event);
        break;
      
      case 'user_logout':
        await this.handleUserLogout(event);
        break;
        
      default:
        console.log(`ℹ️  처리되지 않은 이벤트: ${event.event}`);
    }
  }

  // 사용자 로그인 처리
  async handleUserLogin(event) {
    const { userId, metadata } = event;
    
    console.log(`🎵 ${userId}님 로그인 - 추천음악 준비 중...`);
    
    try {
      // 1. 사용자 최근 재생 기록 조회
      const recentSongs = await this.getUserRecentSongs(userId);
      
      // 2. 개인화된 추천 음악 생성
      const recommendations = await this.generateRecommendations(userId, recentSongs);
      
      // 3. 추천 음악 캐시에 저장
      await this.cacheRecommendations(userId, recommendations);
      
      console.log(`✅ ${userId}님 추천음악 준비 완료 (${recommendations.length}곡)`);
      
    } catch (error) {
      console.error(`❌ 추천음악 준비 실패 - ${userId}:`, error);
    }
  }

  // 사용자 로그아웃 처리  
  async handleUserLogout(event) {
    const { userId, metadata } = event;
    
    console.log(`👋 ${userId}님 로그아웃 - 세션 정리 중...`);
    
    try {
      // 1. 사용자 세션 캐시 정리
      await this.clearUserSession(userId);
      
      // 2. 임시 플레이리스트 정리
      await this.clearTempPlaylists(userId);
      
      // 3. 세션 통계 업데이트
      await this.updateSessionStats(userId, metadata.sessionDuration);
      
      console.log(`✅ ${userId}님 세션 정리 완료`);
      
    } catch (error) {
      console.error(`❌ 세션 정리 실패 - ${userId}:`, error);
    }
  }

  // 사용자 최근 재생 기록 조회
  async getUserRecentSongs(userId) {
    // DB에서 사용자의 최근 재생 기록 조회
    // 실제 구현은 여기서...
    return [];
  }

  // 추천 음악 생성
  async generateRecommendations(userId, recentSongs) {
    // ML 모델을 통한 추천 알고리즘
    // 실제 구현은 여기서...
    return [];
  }

  // 추천 음악 캐시 저장
  async cacheRecommendations(userId, recommendations) {
    // Redis에 추천 음악 목록 캐시
    // 실제 구현은 여기서...
  }

  async stop() {
    await this.consumer.disconnect();
    console.log('🔌 Consumer 연결 해제');
  }
}

module.exports = UserEventConsumer;
```

### 4. Express.js와 통합

#### User Service API에 이벤트 발송 추가
```javascript
// routes/auth.js
const express = require('express');
const UserEventProducer = require('../services/userEventProducer');

const router = express.Router();
const userEventProducer = new UserEventProducer();

// 로그인 API
router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    
    // 1. 사용자 인증 처리
    const user = await authenticateUser(email, password);
    if (!user) {
      return res.status(401).json({ error: '인증 실패' });
    }

    // 2. JWT 토큰 생성
    const token = generateJWT(user);

    // 3. 로그인 이벤트 Kafka로 전송
    await userEventProducer.sendLoginEvent(user.id, {
      ip: req.ip,
      device: req.get('User-Agent'),
      userAgent: req.get('User-Agent')
    });

    // 4. 응답 반환
    res.json({
      success: true,
      token: token,
      user: {
        id: user.id,
        email: user.email,
        name: user.name
      }
    });

  } catch (error) {
    console.error('로그인 처리 실패:', error);
    res.status(500).json({ error: '서버 오류' });
  }
});

// 로그아웃 API
router.post('/logout', async (req, res) => {
  try {
    const userId = req.user.id;
    const loginTime = req.user.loginTime;
    const sessionDuration = Date.now() - loginTime;

    // 로그아웃 이벤트 전송
    await userEventProducer.sendLogoutEvent(userId, sessionDuration);

    res.json({ success: true, message: '로그아웃 완료' });
  } catch (error) {
    console.error('로그아웃 처리 실패:', error);
    res.status(500).json({ error: '서버 오류' });
  }
});

module.exports = router;
```

## 📐 토픽 설계 가이드

### 토픽 명명 규칙

```
{도메인}-{액션타입}
```

**예시:**
- `user-events`: 사용자 관련 모든 이벤트
- `music-events`: 음악 재생 관련 이벤트  
- `playlist-events`: 플레이리스트 관련 이벤트
- `notification-events`: 알림 관련 이벤트

### 파티션 수 결정

```javascript
// 파티션 수 = max(처리량 요구사항 ÷ 파티션당 처리량, 병렬처리 요구사항)

// 예시: user-events 토픽
// - 초당 1,000개 이벤트
// - 파티션당 초당 500개 처리 가능  
// - 필요 파티션 수: 1,000 ÷ 500 = 2개
// - 여유분 고려: 3개 파티션
```

### 메시지 키(Key) 전략

```javascript
// ✅ 좋은 예시: 사용자별 순서 보장
{
  key: userId,  // 같은 사용자는 같은 파티션
  value: message
}

// ✅ 좋은 예시: 균등 분산  
{
  key: `${userId}_${timestamp}`,  // 시간으로 분산
  value: message
}

// ❌ 나쁜 예시: 핫스팟 생성
{
  key: 'constant_value',  // 모든 메시지가 한 파티션으로
  value: message
}
```

## ⚠️ 에러 처리 및 재시도

### 1. Producer 에러 처리

```javascript
class RobustProducer {
  constructor() {
    this.producer = kafka.producer({
      // 메시지 전송 보장 설정
      acks: 'all',  // 모든 replica에 확인
      retries: Number.MAX_SAFE_INTEGER,  // 무한 재시도
      idempotent: true  // 중복 메시지 방지
    });
    this.failedMessages = [];
  }

  async sendWithRetry(topic, messages, maxRetries = 3) {
    let attempt = 0;
    
    while (attempt < maxRetries) {
      try {
        const result = await this.producer.send({
          topic,
          messages
        });
        
        console.log(`✅ 메시지 전송 성공 (attempt: ${attempt + 1})`);
        return result;
        
      } catch (error) {
        attempt++;
        console.warn(`⚠️  메시지 전송 실패 (attempt: ${attempt}):`, error.message);
        
        if (attempt >= maxRetries) {
          // 최대 재시도 도달 시 실패 메시지 저장
          this.failedMessages.push({
            topic,
            messages,
            error: error.message,
            timestamp: new Date()
          });
          throw error;
        }
        
        // 지수 백오프 대기
        await this.delay(Math.pow(2, attempt) * 1000);
      }
    }
  }

  delay(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  // 실패한 메시지 재처리
  async retryFailedMessages() {
    const failed = [...this.failedMessages];
    this.failedMessages = [];
    
    for (const { topic, messages } of failed) {
      try {
        await this.sendWithRetry(topic, messages);
        console.log(`♻️  실패 메시지 재전송 성공`);
      } catch (error) {
        console.error(`❌ 실패 메시지 재전송 실패:`, error);
        // Dead Letter Queue로 전송하거나 로깅
      }
    }
  }
}
```

### 2. Consumer 에러 처리

```javascript
class RobustConsumer {
  constructor() {
    this.consumer = kafka.consumer({
      groupId: 'music-service-group'
    });
    this.deadLetterProducer = kafka.producer();
  }

  async processMessage(message) {
    const maxRetries = 3;
    let attempt = 0;
    
    while (attempt < maxRetries) {
      try {
        const event = JSON.parse(message.value.toString());
        
        // 메시지 처리 로직
        await this.handleEvent(event);
        
        console.log(`✅ 메시지 처리 완료 (attempt: ${attempt + 1})`);
        return;
        
      } catch (error) {
        attempt++;
        console.warn(`⚠️  메시지 처리 실패 (attempt: ${attempt}):`, error.message);
        
        if (attempt >= maxRetries) {
          // Dead Letter Queue로 전송
          await this.sendToDeadLetterQueue(message, error);
          console.error(`❌ 메시지 처리 최종 실패 - DLQ 전송`);
          return;
        }
        
        // 재시도 대기
        await this.delay(1000 * attempt);
      }
    }
  }

  // Dead Letter Queue 전송
  async sendToDeadLetterQueue(originalMessage, error) {
    try {
      const dlqMessage = {
        originalTopic: 'user-events',
        originalMessage: originalMessage.value.toString(),
        error: error.message,
        timestamp: new Date().toISOString(),
        retryCount: 3
      };

      await this.deadLetterProducer.send({
        topic: 'user-events-dlq',
        messages: [{
          key: originalMessage.key,
          value: JSON.stringify(dlqMessage)
        }]
      });
    } catch (dlqError) {
      console.error('DLQ 전송 실패:', dlqError);
      // 로깅 시스템에 기록
    }
  }
}
```

## 🚀 성능 최적화

### 1. Producer 최적화

```javascript
// 배치 처리로 처리량 향상
const optimizedProducer = kafka.producer({
  // 배치 설정
  batchSize: 16384,      // 16KB 배치
  lingerMs: 10,          // 10ms 대기 후 전송
  maxInFlightRequests: 5,
  
  // 압축 설정 (네트워크 대역폭 절약)
  compression: 'gzip',
  
  // 성능 최적화
  idempotent: true,      // 멱등성 보장
  acks: 'all'            // 안정성과 성능 균형
});
```

### 2. Consumer 최적화

```javascript
const optimizedConsumer = kafka.consumer({
  groupId: 'music-service-group',
  
  // 배치 처리 설정
  maxBytesPerPartition: 1048576,  // 1MB
  minBytes: 1,                    // 최소 1바이트
  maxWaitTimeInMs: 1000,         // 최대 1초 대기
  
  // 세션 설정
  sessionTimeout: 30000,          // 30초 세션 타임아웃
  heartbeatInterval: 3000,        // 3초 하트비트
  
  // 자동 커밋 설정
  allowAutoTopicCreation: false,   // 성능 향상
});
```

### 3. 메시지 크기 최적화

```javascript
// ❌ 비효율적인 메시지
{
  "event": "song_played",
  "userFullInformation": {
    "id": "user_12345",
    "email": "user@example.com",
    "profile": { /* 많은 데이터 */ },
    "preferences": { /* 많은 데이터 */ }
  },
  "songFullInformation": {
    /* 큰 메타데이터 */
  }
}

// ✅ 최적화된 메시지
{
  "event": "song_played",
  "userId": "user_12345",
  "songId": "song_67890", 
  "timestamp": "2024-01-15T10:35:00Z",
  "duration": 180
}
```

## 📊 모니터링 및 디버깅

### 1. 기본 모니터링 명령어

```bash
# Kafka 클러스터 상태 확인
kubectl exec -n moremoremusic-msa kafka-secure-xxxxx-xxxxx -- \
  kafka-topics --bootstrap-server localhost:9092 --list

# 토픽별 메시지 수 확인  
kubectl exec -n moremoremusic-msa kafka-secure-xxxxx-xxxxx -- \
  kafka-run-class kafka.tools.GetOffsetShell \
  --broker-list localhost:9092 \
  --topic user-events

# 컨슈머 그룹 상태 확인
kubectl exec -n moremoremusic-msa kafka-secure-xxxxx-xxxxx -- \
  kafka-consumer-groups --bootstrap-server localhost:9092 \
  --group music-service-group --describe
```

### 2. 애플리케이션 메트릭 수집

```javascript
// services/kafkaMetrics.js
class KafkaMetrics {
  constructor() {
    this.metrics = {
      messagesSent: 0,
      messagesReceived: 0,
      errors: 0,
      latency: []
    };
  }

  recordMessageSent() {
    this.metrics.messagesSent++;
  }

  recordMessageReceived() {
    this.metrics.messagesReceived++;
  }

  recordError(error) {
    this.metrics.errors++;
    console.error('Kafka Error:', error);
  }

  recordLatency(startTime) {
    const latency = Date.now() - startTime;
    this.metrics.latency.push(latency);
    
    // 최근 100개 지연시간만 유지
    if (this.metrics.latency.length > 100) {
      this.metrics.latency.shift();
    }
  }

  getAverageLatency() {
    if (this.metrics.latency.length === 0) return 0;
    
    const sum = this.metrics.latency.reduce((a, b) => a + b, 0);
    return Math.round(sum / this.metrics.latency.length);
  }

  getStats() {
    return {
      messagesSent: this.metrics.messagesSent,
      messagesReceived: this.metrics.messagesReceived,
      errors: this.metrics.errors,
      averageLatency: this.getAverageLatency(),
      timestamp: new Date().toISOString()
    };
  }

  // 주기적으로 메트릭 출력
  startReporting(intervalMs = 60000) {
    setInterval(() => {
      const stats = this.getStats();
      console.log('📊 Kafka Metrics:', JSON.stringify(stats, null, 2));
    }, intervalMs);
  }
}

module.exports = KafkaMetrics;
```

### 3. 디버깅 도구

```javascript
// utils/kafkaDebugger.js
class KafkaDebugger {
  static async debugTopic(topicName) {
    const admin = kafka.admin();
    
    try {
      await admin.connect();
      
      // 토픽 메타데이터 조회
      const metadata = await admin.fetchTopicMetadata({ topics: [topicName] });
      console.log('🔍 토픽 메타데이터:', JSON.stringify(metadata, null, 2));
      
      // 토픽 설정 조회
      const configs = await admin.describeConfigs({
        resources: [{
          type: 'TOPIC',
          name: topicName
        }]
      });
      console.log('⚙️  토픽 설정:', configs);
      
    } finally {
      await admin.disconnect();
    }
  }

  static async debugConsumerGroup(groupId) {
    const admin = kafka.admin();
    
    try {
      await admin.connect();
      
      // 컨슈머 그룹 상태 조회
      const groupDescription = await admin.describeGroups([groupId]);
      console.log('👥 컨슈머 그룹 상태:', groupDescription);
      
      // 오프셋 정보 조회
      const offsets = await admin.fetchOffsets({ groupId });
      console.log('📍 오프셋 정보:', offsets);
      
    } finally {
      await admin.disconnect();
    }
  }
}
```

## 🎯 실전 팁

### 1. 메시지 순서 보장이 중요한 경우
```javascript
// 같은 키를 사용하여 같은 파티션으로 전송
await producer.send({
  topic: 'user-events',
  messages: [{
    key: userId,  // 같은 사용자의 모든 이벤트는 순서 보장
    value: JSON.stringify(event)
  }]
});
```

### 2. 정확히 한 번 처리가 필요한 경우
```javascript
// 메시지 중복 처리 방지
const processedMessages = new Set();

async function processMessage(message) {
  const messageId = message.headers['message-id'];
  
  if (processedMessages.has(messageId)) {
    console.log('이미 처리된 메시지 스킵');
    return;
  }
  
  // 메시지 처리
  await handleMessage(message);
  
  // 처리 완료 기록
  processedMessages.add(messageId);
}
```

### 3. 스키마 버전 관리
```javascript
// 메시지에 스키마 버전 포함
const message = {
  schemaVersion: '1.0',
  event: 'user_login',
  // ... 데이터
};

// Consumer에서 버전별 처리
async function handleMessage(message) {
  const event = JSON.parse(message.value);
  
  switch (event.schemaVersion) {
    case '1.0':
      return handleV1Event(event);
    case '2.0':
      return handleV2Event(event);
    default:
      console.warn('지원하지 않는 스키마 버전:', event.schemaVersion);
  }
}
```

---

## 📚 추가 학습 자료

### 공식 문서
- [Apache Kafka 공식 문서](https://kafka.apache.org/documentation/)
- [KafkaJS 공식 가이드](https://kafka.js.org/docs/getting-started)

### 유용한 도구
- [Kafka Tool](https://www.kafkatool.com/) - GUI 관리 도구
- [Kafka Manager](https://github.com/yahoo/CMAK) - 웹 기반 관리도구
- [kafkacat](https://github.com/edenhill/kcat) - 명령줄 도구

---

**🎵 Happy Messaging! 즐거운 개발되세요!**

이 가이드와 함께라면 Kafka를 처음 접하는 개발자도 MoreMoreMusic의 메시지 통신을 완벽하게 이해하고 구현할 수 있을 것입니다.