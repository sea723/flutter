import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'lidar.dart';
import 'simple_3d_viewer.dart';

final lidarDataProvider = StateProvider<Map<int, Lidar>>((ref) => {});

class MyHomePage extends ConsumerStatefulWidget {
  const MyHomePage({super.key});

  @override
  ConsumerState<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends ConsumerState<MyHomePage> {
  final TextEditingController _urlController = TextEditingController(text: 'ws://127.0.0.1:8765');
  WebSocketChannel? _channel;
  List<String> _messages = [];
  bool _connected = false;
  String _colorMode = 'distance'; // 색상 모드
  double _pointSize = 0.05; // 포인트 크기
  bool _showGrid = true; // 그리드 표시 여부
  double _gridStep = 1.0; // 그리드 간격 (미터)

  void _connect() {
    final url = _urlController.text.trim();
    print('연결 시도: $url');
    if (_channel != null) {
      _channel!.sink.close();
    }
    setState(() {
      _messages.clear();
      _connected = true;
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _channel!.stream.listen((data) {
        // 위젯이 여전히 활성 상태인지 확인
        if (!mounted) return;
        
        print('=== WebSocket 데이터 수신 ===');
        print('Raw data: $data');
        
        try {
          final jsonData = jsonDecode(data);
          print('Parsed JSON: $jsonData');
          print('Data type: ${jsonData['type']}');
          
          if (jsonData['type'] == 'lidar') {
            print('라이다 데이터 감지! 채널: ${jsonData['channel']}');
            print('거리 데이터 수: ${jsonData['distances']?.length ?? 0}');
            print('방위각 데이터 수: ${jsonData['azimuth']?.length ?? 0}');
            
            final lidar = Lidar.fromJson(jsonData);
            final channels = {...ref.read(lidarDataProvider)};
            channels[lidar.channel] = lidar;
            ref.read(lidarDataProvider.notifier).state = channels;
            
            print('Provider 업데이트 완료. 총 채널 수: ${channels.length}');
          } else {
            print('라이다 데이터가 아님: ${jsonData['type']}');
          }
        } catch (e) {
          print('JSON 파싱 에러: $e');
          print('문제가 된 데이터: $data');
        }
        
        // 위젯이 여전히 활성 상태인지 다시 확인
        if (mounted) {
          setState(() {
            _messages.add(data.toString());
          });
        }
      }, onDone: () {
        print('연결 종료');
        if (mounted) {
          setState(() {
            _connected = false;
          });
        }
      }, onError: (error) {
        print('에러 발생: $error');
        if (mounted) {
          setState(() {
            _connected = false;
            _messages.add('에러: $error');
          });
        }
      });
    });
  }

  void _disconnect() {
    _channel?.sink.close();
    setState(() {
      _connected = false;
      _messages.add('연결 해제됨');
    });
  }
  
  @override
  void dispose() {
    // WebSocket 연결을 먼저 정리
    _channel?.sink.close();
    _channel = null;
    
    // 컨트롤러 정리
    _urlController.dispose();
    
    // 부모 dispose 호출
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lidarDatas = ref.watch(lidarDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter LiDAR 3D Point Cloud Viewer'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 연결 설정 부분
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: '서버 IP, Port 입력 (ws://...)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _connected ? _disconnect : _connect,
                  child: Text(_connected ? '연결 해제' : '연결 버튼'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // 3D 뷰 제어 패널 - 반응형으로 수정
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    // 첫 번째 줄: 색상과 크기
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('색상: '),
                            DropdownButton<String>(
                              value: _colorMode,
                              items: const [
                                DropdownMenuItem(value: 'distance', child: Text('거리')),
                                DropdownMenuItem(value: 'channel', child: Text('채널')),
                                DropdownMenuItem(value: 'intensity', child: Text('강도')),
                                DropdownMenuItem(value: 'vertical_angle', child: Text('각도')),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  _colorMode = value ?? 'distance';
                                });
                              },
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('크기: '),
                            SizedBox(
                              width: 80,
                              child: Slider(
                                value: _pointSize,
                                min: 0.01,
                                max: 0.2,
                                divisions: 19,
                                onChanged: (value) {
                                  setState(() {
                                    _pointSize = value;
                                  });
                                },
                              ),
                            ),
                            Text(_pointSize.toStringAsFixed(2)),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('그리드: '),
                            Checkbox(
                              value: _showGrid,
                              onChanged: (value) {
                                setState(() {
                                  _showGrid = value ?? true;
                                });
                              },
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('간격: '),
                            DropdownButton<double>(
                              value: _gridStep,
                              items: const [
                                DropdownMenuItem(value: 0.5, child: Text('0.5m')),
                                DropdownMenuItem(value: 1.0, child: Text('1m')),
                                DropdownMenuItem(value: 2.0, child: Text('2m')),
                                DropdownMenuItem(value: 5.0, child: Text('5m')),
                                DropdownMenuItem(value: 10.0, child: Text('10m')),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  _gridStep = value ?? 1.0;
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // 메인 뷰 영역
            Expanded(
              child: Row(
                children: [
                  // 메시지 로그 (왼쪽)
                  Expanded(
                    flex: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black26),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Colors.grey,
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(8),
                                topRight: Radius.circular(8),
                              ),
                            ),
                            child: const Text('수신 메시지'),
                          ),
                          Expanded(
                            child: _messages.isEmpty
                                ? const Center(child: Text('대기 중...'))
                                : ListView.builder(
                                    itemCount: _messages.length,
                                    itemBuilder: (context, idx) => Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                      child: Text(
                                        _messages[idx],
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(width: 16),
                  
                  // 포인트클라우드 뷰 (오른쪽)
                  Expanded(
                    flex: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black26),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Colors.blue,
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(8),
                                topRight: Radius.circular(8),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Text(
                                  '3D 포인트클라우드',
                                  style: TextStyle(color: Colors.white),
                                ),
                                const Spacer(),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Simple3DViewer(
                              channels: lidarDatas,
                              pointSize: _pointSize * 20, // Canvas용 크기 조정
                              colorMode: _colorMode,
                              showGrid: _showGrid, // 그리드 옵션 전달
                              gridStep: _gridStep, // 그리드 간격 전달
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 테스트 버튼들
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _connected && _channel != null
                      ? () => _channel!.sink.add('{"type":"test1"}')
                      : null,
                  child: const Text('메시지 1'),
                ),
                ElevatedButton(
                  onPressed: _connected && _channel != null
                      ? () => _channel!.sink.add('{"type":"start_scan"}')
                      : null,
                  child: const Text('스캔 시작'),
                ),
                ElevatedButton(
                  onPressed: _connected && _channel != null
                      ? () => _channel!.sink.add('{"type":"stop_scan"}')
                      : null,
                  child: const Text('스캔 중지'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  runApp(
    ProviderScope(
      child: MaterialApp(
        title: 'LiDAR 3D Point Cloud Viewer',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
        ),
        home: const MyHomePage(),
      ),
    ),
  );
}