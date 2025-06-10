import asyncio
import websockets
import json
import socket
import struct
import threading
from datetime import datetime
from collections import defaultdict
import time
import queue

class KanaviLidarParser:
    """Kanavi VL-Series LiDAR 프로토콜 파서"""
    
    def __init__(self):
        # 라이다 모델별 설정
        self.lidar_models = {
            0x03: {"name": "VL-R2", "channels": 2, "hfov": 120, "interface": "Ethernet"},
            0x06: {"name": "VL-R4", "channels": 4, "hfov": 100, "interface": "Ethernet"},
            0x07: {"name": "VL-R270", "channels": 1, "hfov": 270, "interface": "Ethernet"}
        }
        
    def parse_kanavi_packet(self, data):
        """Kanavi VL-Series 패킷 파싱"""
        try:
            if len(data) < 8:  # 최소 헤더 크기
                return None
            
            # 프로토콜 구조 파싱 (Big Endian)
            header = data[0]
            if header != 0xFA:  # 시작 바이트 확인
                return None
            
            product_line = data[1]
            lidar_id = data[2]
            command = struct.unpack('>H', data[3:5])[0]  # Big Endian 2바이트
            data_length = struct.unpack('>H', data[5:7])[0]  # Big Endian 2바이트
            
            # Distance Data 명령인지 확인 (0xDDCX 형태)
            if (command & 0xFF00) != 0xDD00:
                return None
                
            channel = command & 0x00FF  # 채널 번호 (0xC0~0xCF에서 채널 추출)
            if (channel & 0xF0) != 0xC0:
                return None
                
            actual_channel = channel & 0x0F  # 실제 채널 번호 (0~15)
            
            # 데이터 영역 파싱
            data_start = 7
            data_end = data_start + data_length
            
            if len(data) < data_end + 1:  # 체크섬 포함 확인
                return None
            
            packet_data = data[data_start:data_end]
            checksum = data[data_end]
            
            # 체크섬 검증 (Header부터 DataLength까지 XOR - Distance Data는 예외)
            calculated_checksum = 0
            for i in range(7):  # Header ~ DataLength
                calculated_checksum ^= data[i]
                
            if calculated_checksum != checksum:
                print(f"체크섬 오류: 계산값={calculated_checksum:02X}, 수신값={checksum:02X}")
                return None
            
            # Distance Data 파싱 - Kanavi 실제 구조에 맞게 수정
            points = []
            
            # 디버그 정보 추가
            print(f"🔍 디버그: 채널 {actual_channel}, 패킷 크기: {len(data)}바이트, "
                  f"데이터 길이: {len(packet_data)}바이트")
            
            model_info = self.lidar_models.get(product_line, {
                "name": f"Unknown_{product_line:02X}",
                "channels": 4,
                "hfov": 360,
                "interface": "Unknown"
            })
            
            # VL-R4의 경우 400포인트 예상
            expected_points = 400 if product_line == 0x06 else 360  # VL-R4는 400, 나머지는 추정
            
            if len(packet_data) >= expected_points * 2:
                # 거리 데이터: 각 포인트당 2바이트 (Distance_D + Distance_F)
                valid_points = 0
                zero_distance_count = 0
                
                # 거리 데이터 파싱 (2바이트씩)
                for i in range(expected_points):
                    if i * 2 + 1 >= len(packet_data):
                        break
                        
                    distance_d = packet_data[i * 2]      # 정수부
                    distance_f = packet_data[i * 2 + 1]  # 소수부
                    
                    # 거리 계산 (미터 단위)
                    distance = distance_d + (distance_f / 100.0)
                    
                    # 각도 계산 (HFoV를 포인트 수로 균등 분할)
                    hfov = model_info["hfov"]
                    azimuth = -hfov/2 + (i * hfov / (expected_points - 1)) if expected_points > 1 else 0
                    
                    # Detection 정보 (마지막 바이트에서 추출하거나 기본값)
                    detection = 0
                    if len(packet_data) > expected_points * 2:
                        # 추가 Detection 데이터가 있는 경우
                        detection_offset = expected_points * 2
                        if i < len(packet_data) - detection_offset:
                            detection = packet_data[detection_offset + (i % (len(packet_data) - detection_offset))]
                    
                    if distance > 0:  # 유효한 거리값만
                        points.append({
                            'channel': actual_channel,
                            'distance': distance,
                            'azimuth': azimuth,
                            'detection': detection,
                            'point_index': i
                        })
                        valid_points += 1
                    else:
                        zero_distance_count += 1
                
                print(f"   → 예상 포인트: {expected_points}개, 유효 포인트: {valid_points}개, 무효 포인트: {zero_distance_count}개")
            
            return {
                'points': points,
                'product_line': product_line,
                'lidar_id': lidar_id,
                'channel': actual_channel,
                'model_info': model_info,
                'num_points': len(points),
                'raw_command': command,
                'packet_size': len(data),
                'data_length': len(packet_data)
            }
            
        except Exception as e:
            print(f"Kanavi 파싱 오류: {e}")
            return None

class KanaviLidarReceiver:
    """Kanavi 라이다 UDP 수신기 (멀티캐스트 지원)"""
    
    def __init__(self, listen_port=2020, multicast_group="224.0.0.5"):
        self.listen_port = listen_port
        self.multicast_group = multicast_group  # Kanavi 기본 멀티캐스트 그룹
        self.parser = KanaviLidarParser()
        self.running = False
        self.socket = None
        self.data_callback = None
        
    def set_data_callback(self, callback):
        """데이터 수신 콜백 설정"""
        self.data_callback = callback
    
    def start_receiving(self):
        """UDP 멀티캐스트 수신 시작"""
        try:
            # UDP 소켓 생성
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            
            # 멀티캐스트 그룹 조인
            self.socket.bind(('', self.listen_port))  # 모든 인터페이스에서 수신
            
            # 멀티캐스트 그룹에 참여
            mreq = struct.pack("4sl", socket.inet_aton(self.multicast_group), socket.INADDR_ANY)
            self.socket.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
            
            self.socket.settimeout(1.0)  # 1초 타임아웃
            
            self.running = True
            print(f"🎯 Kanavi 멀티캐스트 수신 시작:")
            print(f"   - 멀티캐스트 그룹: {self.multicast_group}")
            print(f"   - 포트: {self.listen_port}")
            print(f"📡 파서 타입: Kanavi VL-Series")
            
            while self.running:
                try:
                    data, addr = self.socket.recvfrom(2048)  # 최대 2KB 패킷
                    
                    # Kanavi 프로토콜 파싱
                    parsed_data = self.parser.parse_kanavi_packet(data)
                    
                    if parsed_data and self.data_callback:
                        self.data_callback(parsed_data, addr)
                        
                except socket.timeout:
                    continue
                except Exception as e:
                    print(f"패킷 수신 오류: {e}")
                    
        except Exception as e:
            print(f"멀티캐스트 UDP 소켓 초기화 오류: {e}")
            print("💡 해결 방법:")
            print("   1. 관리자 권한으로 실행")
            print("   2. 방화벽에서 포트 5000 허용")
            print("   3. 네트워크 어댑터에서 멀티캐스트 활성화")
        finally:
            if self.socket:
                try:
                    # 멀티캐스트 그룹에서 탈퇴
                    mreq = struct.pack("4sl", socket.inet_aton(self.multicast_group), socket.INADDR_ANY)
                    self.socket.setsockopt(socket.IPPROTO_IP, socket.IP_DROP_MEMBERSHIP, mreq)
                except:
                    pass
                self.socket.close()
    
    def stop_receiving(self):
        """수신 중지"""
        self.running = False

class KanaviWebSocketServer:
    """Kanavi 라이다 WebSocket 서버"""
    
    def __init__(self, listen_port=5000, multicast_group="224.0.0.5"):
        self.lidar_receiver = KanaviLidarReceiver(listen_port, multicast_group)
        self.connected_clients = set()
        self.receiving = False
        self.last_send_time = defaultdict(float)
        self.data_queue = queue.Queue()  # 스레드 간 데이터 전달용 큐
        
        # 라이다 데이터 콜백 설정
        self.lidar_receiver.set_data_callback(self.on_lidar_data_received)
    
    def on_lidar_data_received(self, parsed_data, source_addr):
        """Kanavi 라이다 데이터 수신 콜백"""
        try:
            points = parsed_data['points']
            channel = parsed_data['channel']
            model_info = parsed_data['model_info']
            
            if not points:
                return
            
            # 전송 속도 제한 (채널당 최대 20Hz)
            current_time = time.time()
            if current_time - self.last_send_time[channel] < 0.05:
                return
            
            self.last_send_time[channel] = current_time
            
            # WebSocket JSON 형태로 변환
            distances = [p['distance'] for p in points]
            azimuths = [p['azimuth'] for p in points]
            detections = [p['detection'] for p in points]
            
            # 수직각 계산 (채널별 고정값)
            if model_info['name'] == 'VL-R4':
                vfov_map = {0: -1.5, 1: -0.5, 2: 0.5, 3: 1.5}
                vertical_angle = vfov_map.get(channel, 0.0)
            elif model_info['name'] == 'VL-R2':
                vfov_map = {0: -0.5, 1: 0.5}
                vertical_angle = vfov_map.get(channel, 0.0)
            else:
                vertical_angle = 0.0
            
            vertical_angles = [vertical_angle] * len(points)
            
            lidar_data = {
                "type": "lidar",
                "model": model_info['name'],
                "pointsize": len(distances),
                "channel": channel,
                "hfov": model_info['hfov'],
                "vfov": vertical_angles,
                "distances": distances,
                "azimuth": azimuths,
                "vertical_angle": vertical_angles,
                "max": max(distances) if distances else 50,
                "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "source_ip": str(source_addr[0]),
                "lidar_id": f"0x{parsed_data['lidar_id']:02X}",
                "detection_data": detections,
                "product_line": f"0x{parsed_data['product_line']:02X}"
            }
            
            # 큐를 통해 메인 스레드로 데이터 전달
            try:
                self.data_queue.put_nowait(lidar_data)
                print(f"📤 데이터 큐에 추가: 채널 {channel}, {len(distances)}개 포인트")
            except queue.Full:
                print(f"⚠️  데이터 큐가 가득참")
            
            # 디버그 출력
            print(f"📊 {model_info['name']} Ch{channel}: {len(distances)}개 포인트, "
                  f"거리범위: {min(distances):.2f}~{max(distances):.2f}m")
                
        except Exception as e:
            print(f"Kanavi 라이다 데이터 처리 오류: {e}")
    
    async def broadcast_to_clients(self, data):
        """모든 클라이언트에 데이터 브로드캐스트"""
        if not self.connected_clients:
            return
            
        disconnected = []
        success_count = 0
        
        for client in self.connected_clients.copy():
            try:
                json_data = json.dumps(data)
                await client.send(json_data)
                success_count += 1
            except websockets.ConnectionClosed:
                disconnected.append(client)
            except Exception as e:
                print(f"❌ 클라이언트 전송 오류: {e}")
                disconnected.append(client)
        
        # 연결 끊어진 클라이언트 제거
        for client in disconnected:
            self.connected_clients.discard(client)
            
        if success_count > 0:
            print(f"✅ WebSocket 전송 성공: {success_count}개 클라이언트")
    
    async def broadcast_data_loop(self):
        """데이터 큐 처리 루프 (메인 이벤트 루프에서 실행)"""
        print("🔄 데이터 브로드캐스트 루프 시작")
        while self.receiving:
            try:
                # 논블로킹으로 큐에서 데이터 가져오기
                while not self.data_queue.empty():
                    lidar_data = self.data_queue.get_nowait()
                    await self.broadcast_to_clients(lidar_data)
                
                # 짧은 대기 후 다시 확인
                await asyncio.sleep(0.01)  # 10ms 대기
                
            except queue.Empty:
                await asyncio.sleep(0.01)  # 10ms 대기
            except Exception as e:
                print(f"데이터 큐 처리 오류: {e}")
                await asyncio.sleep(0.1)
        
        print("🔄 데이터 브로드캐스트 루프 종료")
    
    async def handle_client_message(self, websocket, message):
        """클라이언트 메시지 처리"""
        try:
            data = json.loads(message)
            message_type = data.get("type", "unknown")
            
            if message_type == "start_scan":
                if not self.receiving:
                    self.receiving = True
                    # 별도 스레드에서 라이다 수신 시작
                    threading.Thread(target=self.lidar_receiver.start_receiving, daemon=True).start()
                    # 데이터 큐 처리 태스크 시작
                    asyncio.create_task(self.broadcast_data_loop())
                    
                response = {
                    "type": "scan_status",
                    "status": "Kanavi 라이다 스캔 시작",
                    "scanning": self.receiving,
                    "listen_port": self.lidar_receiver.listen_port,
                    "multicast_group": self.lidar_receiver.multicast_group,
                    "supported_models": ["VL-R2SL", "VL-R2", "VL-R4", "VL-R270"]
                }
                await websocket.send(json.dumps(response))
            
            elif message_type == "stop_scan":
                if self.receiving:
                    self.receiving = False
                    self.lidar_receiver.stop_receiving()
                
                response = {
                    "type": "scan_status", 
                    "status": "Kanavi 라이다 스캔 중지",
                    "scanning": self.receiving
                }
                await websocket.send(json.dumps(response))
            
            elif message_type == "get_status":
                response = {
                    "type": "status_response",
                    "status": "Kanavi VL-Series 라이다 서버 가동 중",
                    "scanning": self.receiving,
                    "listen_port": self.lidar_receiver.listen_port,
                    "multicast_group": self.lidar_receiver.multicast_group,
                    "protocol": "Kanavi VL-Series Protocol v1.5.2",
                    "supported_models": {
                        "VL-R2": "2Ch 120° Ethernet", 
                        "VL-R4": "4Ch 100° Ethernet",
                        "VL-R270": "1Ch 270° Ethernet"
                    },
                    "connected_clients": len(self.connected_clients),
                    "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                }
                await websocket.send(json.dumps(response))
            
            elif message_type == "ping":
                response = {
                    "type": "pong",
                    "message": "Kanavi 라이다 서버 응답",
                    "server_timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                }
                await websocket.send(json.dumps(response))
            
            else:
                response = {
                    "type": "error",
                    "message": f"지원하지 않는 명령: {message_type}"
                }
                await websocket.send(json.dumps(response))
                
        except json.JSONDecodeError:
            response = {
                "type": "error",
                "message": "잘못된 JSON 형식"
            }
            await websocket.send(json.dumps(response))

async def handle_client(websocket):
    """WebSocket 클라이언트 처리"""
    server = websocket.server.server_instance
    server.connected_clients.add(websocket)
    
    print(f"🔗 클라이언트 연결: {websocket.remote_address}")
    
    # 연결 환영 메시지
    welcome = {
        "type": "connection",
        "message": "Kanavi VL-Series 라이다 서버에 연결되었습니다",
        "protocol_info": {
            "version": "1.5.2",
            "encoding": "Big Endian",
            "communication": "Ethernet UDP Multicast",
            "multicast_group": server.lidar_receiver.multicast_group,
            "listen_port": server.lidar_receiver.listen_port
        },
        "instructions": "스캔을 시작하려면 'start_scan' 메시지를 보내세요"
    }
    await websocket.send(json.dumps(welcome))
    
    try:
        async for message in websocket:
            await server.handle_client_message(websocket, message)
    except websockets.ConnectionClosed:
        pass
    finally:
        server.connected_clients.discard(websocket)
        print(f"❌ 클라이언트 연결 해제: {websocket.remote_address}")

async def main():
    """메인 서버 실행"""
    print("🚀 Kanavi VL-Series LiDAR WebSocket 서버 시작")
    print("=" * 50)
    
    # 네트워크 설정
    UDP_PORT = 5000
    WEBSOCKET_PORT = 8765
    MULTICAST_GROUP = "224.0.0.5"  # Kanavi 기본 멀티캐스트 그룹
    
    print("📋 네트워크 설정:")
    print(f"   - 멀티캐스트 그룹: {MULTICAST_GROUP}")
    print(f"   - UDP 포트: {UDP_PORT}")
    print(f"   - WebSocket 포트: {WEBSOCKET_PORT}")
    print()
    print("📋 프로토콜 정보:")
    print("   - 제조사: Kanavi Mobility Co.,Ltd.")
    print("   - 프로토콜 버전: 1.5.2")
    print("   - 데이터 인코딩: Big Endian")
    print("   - 통신 방식: Ethernet UDP Multicast")
    print()
    print("🎯 지원 모델:")
    print("   - VL-R2: 2채널 120° (Ethernet)")
    print("   - VL-R4: 4채널 100° (Ethernet)")
    print("   - VL-R270: 1채널 270° (Ethernet)")
    print()
    print(f"🌐 WebSocket: ws://0.0.0.0:{WEBSOCKET_PORT}")
    print("=" * 50)
    
    # 서버 인스턴스 생성 (멀티캐스트 설정 포함)
    kanavi_server = KanaviWebSocketServer(
        listen_port=UDP_PORT,
        multicast_group=MULTICAST_GROUP
    )
    
    # WebSocket 서버 시작
    async with websockets.serve(handle_client, "0.0.0.0", WEBSOCKET_PORT) as server:
        # 서버 인스턴스를 핸들러에서 접근 가능하도록 설정
        server.server_instance = kanavi_server
        
        print("🎯 Kanavi 멀티캐스트 데이터 수신 대기 중...")
        print("📱 Flutter 앱에서 '스캔 시작' 버튼을 눌러주세요!")
        
        await asyncio.Future()  # 무한 대기

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n🛑 Kanavi 라이다 서버 종료")