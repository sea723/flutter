# Flutter LiDAR 3D Point Cloud Viewer

## WebSocket API 명세

이 Flutter 앱은 WebSocket을 통해 LiDAR 데이터를 실시간으로 수신하여 3D 포인트 클라우드로 시각화합니다.

### 연결 정보
- **WebSocket URL**: `ws://localhost:8765` (기본값)
- **프로토콜**: JSON 메시지 기반 통신

## 메시지 형식

### 1. 클라이언트 → 서버 (제어 명령)

#### 스캔 시작
```json
{
  "type": "start_scan"
}
```

#### 스캔 중지
```json
{
  "type": "stop_scan"
}
```

#### 서버 상태 확인
```json
{
  "type": "get_status"
}
```

#### 연결 테스트
```json
{
  "type": "ping"
}
```

### 2. 서버 → 클라이언트 (데이터 전송)

#### LiDAR 포인트 클라우드 데이터 ⭐
```json
{
  "type": "lidar",
  "model": "VL-R4",
  "channel": 0,
  "pointsize": 400,
  "hfov": 100.0,
  "vfov": -1.1,
  "distances": [12.45, 8.32, 15.67, ...],
  "hresolution": 0.25,
  "max": 50.0
}
```

**필드 설명:**
- `type`: "lidar" (고정값)
- `model`: LiDAR 모델명 (예: "VL-R4", "VL-R2")
- `channel`: 채널 번호 (0~3)
- `pointsize`: 포인트 개수
- `hfov`: 수평 시야각 (도, float)
- `vfov`: 수직 시야각 - 채널별 고정값 (도, float)
- `distances`: 거리 배열 (미터, float)
- `hresolution`: 수평 해상도 = 방위각 간격 (도, float)
- `max`: 최대 거리 (미터)

#### 상태 응답
```json
{
  "type": "scan_status",
  "status": "Kanavi 라이다 스캔 시작",
  "scanning": true,
  "listen_port": 5000,
  "multicast_group": "224.0.0.5"
}
```

```json
{
  "type": "status_response", 
  "status": "Kanavi VL-Series 라이다 서버 가동 중",
  "scanning": false,
  "connected_clients": 1,
  "protocol": "Kanavi VL-Series Protocol v1.5.2"
}
```

```json
{
  "type": "pong",
  "message": "Kanavi 라이다 서버 응답",
  "server_timestamp": "2025-06-10 14:30:15"
}
```

## 데이터 구조 상세

### 핵심 개념
- **HFOV (Horizontal Field of View)**: 수평 시야각 (예: 100°)
- **VFOV (Vertical Field of View)**: 수직 시야각 - 채널별 고정값
- **HResolution**: 수평 해상도 = 방위각 간격 (예: 0.25°)

### 지원 LiDAR 모델
- **VL-R2**: 2채널, 120° HFOV
- **VL-R4**: 4채널, 100° HFOV  
- **VL-R270**: 1채널, 270° HFOV

## 구현 가이드

### 서버 측 구현 (Python)
```python
import asyncio
import websockets
import json

async def send_lidar_data(websocket):
    # 실제 LiDAR 데이터 처리 로직
    while True:
        # Kanavi 라이다에서 데이터 수신
        raw_data = get_kanavi_lidar_data()  # 사용자 구현 필요
        
        # WebSocket JSON 형태로 변환
        lidar_data = {
            "type": "lidar",
            "model": "VL-R4",
            "channel": raw_data.channel,
            "hfov": 100.0,
            "vfov": get_channel_vfov(raw_data.channel),
            "distances": raw_data.distances,
            "hresolution": 0.25,
            "pointsize": len(raw_data.distances),
            "max": max(raw_data.distances)
        }
        
        await websocket.send(json.dumps(lidar_data))
        await asyncio.sleep(0.05)  # 20Hz 전송

def get_channel_vfov(channel):
    """채널별 고정 수직각 반환"""
    vfov_map = {0: -1.1, 1: 0.0, 2: 1.1, 3: 2.2}
    return vfov_map.get(channel, 0.0)
```

### 클라이언트 측 사용법
1. **연결**: WebSocket으로 `ws://your-server:8765` 연결
2. **시작**: `{"type": "start_scan"}` 메시지 전송
3. **수신**: LiDAR 데이터 실시간 수신
4. **렌더링**: Flutter 앱에서 자동 3D 시각화

### 테스트 및 디버깅

#### 간단한 테스트 데이터 (JavaScript/Node.js)
```javascript
const WebSocket = require('ws');

// 테스트 서버 생성
const wss = new WebSocket.Server({ port: 8765 });

wss.on('connection', (ws) => {
    console.log('클라이언트 연결됨');
    
    // 테스트 데이터 전송 (1초마다)
    setInterval(() => {
        const testData = {
            "type": "lidar",
            "model": "VL-R4",
            "channel": 0,
            "hfov": 100.0,
            "vfov": -1.1,
            "distances": generateRandomDistances(400),  // 400개 랜덤 거리
            "hresolution": 0.25,
            "pointsize": 400,
            "max": 50.0
        };
        
        ws.send(JSON.stringify(testData));
    }, 1000);
});

function generateRandomDistances(count) {
    return Array.from({length: count}, () => Math.random() * 50 + 1);
}
```


## 데이터 처리 흐름

```
1. Kanavi LiDAR → UDP 멀티캐스트 (224.0.0.5:5000)
2. Python 서버 → 프로토콜 파싱 → JSON 변환
3. WebSocket → Flutter 클라이언트
4. Flutter → azimuth 자동계산 → 3D 좌표 변환
5. 3D 렌더링 → 실시간 포인트클라우드 표시
```


이 형식에 맞춰 데이터를 전송하면 Flutter 앱에서 자동으로 3D 포인트 클라우드로 시각화됩니다!