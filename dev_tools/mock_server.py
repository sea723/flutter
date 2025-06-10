import asyncio
import websockets
import json
import random
from datetime import datetime

class LidarServer:
    def __init__(self):
        self.scanning = False
        self.model_name = "R4"
        self.point_size = 400
        self.hfov = 100
        self.vfov = [-1.1, 0, 1.1, 2.2]
        self.max_range = 50
        self.channels = 4
    
    async def send_lidar_data(self, websocket):
        """라이다 데이터 송신"""
        for channel in range(self.channels):
            data = {
                "type": "lidar",
                "model": self.model_name,
                "pointsize": self.point_size,
                "channel": channel,
                "hfov": self.hfov,
                "vfov": self.vfov,
                "distances": [round(random.uniform(0.0, self.max_range), 2) for _ in range(self.point_size)],
                "max": self.max_range,
                "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            }
            await websocket.send(json.dumps(data))
            await asyncio.sleep(0.1)
    
    async def handle_message(self, websocket, message):
        """클라이언트 메시지 처리"""
        try:
            data = json.loads(message)
            message_type = data.get("type", "unknown")
            
            print(f"수신된 메시지: {message_type}")
            
            # 각 메시지 타입별 처리
            if message_type == "test1":
                response = {
                    "type": "test1_response",
                    "message": "테스트 메시지 1 응답 완료",
                    "original_data": data.get("data", ""),
                    "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                }
                await websocket.send(json.dumps(response))
            
            elif message_type == "ping":
                client_timestamp = data.get("timestamp", "")
                response = {
                    "type": "pong",
                    "message": "핑 응답 완료",
                    "client_timestamp": client_timestamp,
                    "server_timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                    "latency_check": "OK"
                }
                await websocket.send(json.dumps(response))
            
            elif message_type == "start_scan":
                self.scanning = True
                response = {
                    "type": "scan_status",
                    "status": "스캔이 시작되었습니다",
                    "scanning": self.scanning,
                    "message": f"모델 {self.model_name} 스캔 시작"
                }
                await websocket.send(json.dumps(response))
            
            elif message_type == "stop_scan":
                self.scanning = False
                response = {
                    "type": "scan_status",
                    "status": "스캔이 중지되었습니다",
                    "scanning": self.scanning,
                    "message": "스캔 중지됨"
                }
                await websocket.send(json.dumps(response))
            
            elif message_type == "get_status":
                response = {
                    "type": "status_response",
                    "status": "정상 작동 중",
                    "scanning": self.scanning,
                    "model": self.model_name,
                    "channels": self.channels,
                    "hfov": self.hfov,
                    "max_range": self.max_range,
                    "point_size": self.point_size,
                    "uptime": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                }
                await websocket.send(json.dumps(response))
            
            else:
                # 알 수 없는 메시지 타입
                response = {
                    "type": "error",
                    "message": f"알 수 없는 메시지 타입: {message_type}",
                    "received_data": data
                }
                await websocket.send(json.dumps(response))
        
        except json.JSONDecodeError:
            # JSON이 아닌 텍스트 메시지 처리
            response = {
                "type": "text_response",
                "message": f"텍스트 메시지 받음: {message}",
                "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            }
            await websocket.send(json.dumps(response))
        
        except Exception as e:
            # 기타 오류 처리
            error_response = {
                "type": "error",
                "message": f"메시지 처리 중 오류 발생: {str(e)}",
                "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            }
            await websocket.send(json.dumps(error_response))

async def handler(websocket, *args):
    server = LidarServer()
    print(f"클라이언트 연결됨: {websocket.remote_address}")
    
    try:
        # 라이다 데이터 송신 태스크
        async def lidar_data_sender():
            while True:
                if server.scanning:  # 스캔이 활성화된 경우에만 데이터 송신
                    await server.send_lidar_data(websocket)
                    await asyncio.sleep(1)  # 1초마다 전체 채널 데이터 송신
                else:
                    await asyncio.sleep(0.1)  # 스캔 중지 시 대기
        
        # 메시지 수신 태스크
        async def message_receiver():
            async for message in websocket:
                await server.handle_message(websocket, message)
        
        # 연결 알림 메시지
        welcome_message = {
            "type": "connection",
            "message": "서버에 연결되었습니다",
            "server_info": {
                "model": server.model_name,
                "channels": server.channels,
                "hfov": server.hfov,
                "max_range": server.max_range
            },
            "instructions": "스캔을 시작하려면 'start_scan' 메시지를 보내세요"
        }
        await websocket.send(json.dumps(welcome_message))
        
        # 두 태스크를 동시에 실행
        await asyncio.gather(
            lidar_data_sender(),
            message_receiver()
        )
        
    except websockets.ConnectionClosed:
        print(f"클라이언트 연결 종료: {websocket.remote_address}")
    except Exception as e:
        print(f"연결 처리 중 오류: {e}")

async def main():
    print("WebSocket 서버 시작 중...")
    async with websockets.serve(handler, "0.0.0.0", 8765):
        print("🚀 WebSocket 서버가 ws://0.0.0.0:8765 에서 실행 중입니다.")
        print("📡 지원하는 메시지 타입:")
        print("   - test1: 테스트 메시지")
        print("   - ping: 핑 테스트")
        print("   - start_scan: 라이다 스캔 시작")
        print("   - stop_scan: 라이다 스캔 중지")
        print("   - get_status: 서버 상태 확인")
        print("🔄 라이다 데이터는 스캔 시작 후 자동 송신됩니다.")
        
        await asyncio.Future()  # 서버 계속 실행

if __name__ == "__main__":
    asyncio.run(main())