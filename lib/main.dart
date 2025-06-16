import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'lidar.dart';
import 'pointcloud/simple_3d_viewer.dart'; 

final lidarDataProvider = StateProvider<Map<int, Lidar>>((ref) => {});

class MyHomePage extends ConsumerStatefulWidget {
  const MyHomePage({super.key});

  @override
  ConsumerState<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends ConsumerState<MyHomePage> {
  final TextEditingController _urlController = TextEditingController(text: 'ws://127.0.0.1:8765');
  final GlobalKey _viewerKey = GlobalKey();
  WebSocketChannel? _channel;
  StreamSubscription? _webSocketSubscription;
  List<String> _messages = [];
  bool _connected = false;
  bool _scanStopped = true; // 초기에는 스캔 중지 상태
  String _colorMode = 'distance';
  double _pointSize = 1.0;
  bool _showGrid = true;
  bool _showAxis = true;
  bool _areaDrawing = false;
  double _gridStep = 1.0;
  bool _isDisposed = false;
  Map<String, double>? _savedCameraState;
  
  // 내부 라이다 데이터 저장소
  Map<int, Lidar> _localLidarData = {};
  
  // Provider 업데이트를 위한 타이머
  Timer? _providerUpdateTimer;
  
  // 로깅 제한용
  int _dataCount = 0;
  DateTime _lastLogTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    
    _providerUpdateTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      _safeUpdateProvider();
    });
  }

  void _safeUpdateProvider() {
    if (!_isDisposed && mounted && _localLidarData.isNotEmpty && !_scanStopped) {
      try {
        ref.read(lidarDataProvider.notifier).state = Map.from(_localLidarData);
      } catch (e) {
        // 에러는 조용히 무시
      }
    }
  }

  void _connect() {
    final url = _urlController.text.trim();
    print('🔗 연결 시도: $url');

    _disconnect();
    
    if (mounted && !_isDisposed) {
      setState(() {
        _messages.clear();
        _connected = true;
        _localLidarData.clear();
        _scanStopped = true; // 연결시 스캔 중지 상태로 시작
        _dataCount = 0;
      });
    }
    
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      
      _webSocketSubscription = _channel!.stream.listen(
        (data) => _handleWebSocketData(data),
        onDone: () => _handleWebSocketDone(),
        onError: (error) => _handleWebSocketError(error),
      );
      
    } catch (e) {
      print('❌ WebSocket 연결 실패: $e');
      if (mounted && !_isDisposed) {
        _safeSetState(() {
          _connected = false;
          _addMessage('연결 실패: $e');
        });
      }
    }
  }

  void _handleWebSocketData(dynamic data) {
    // 스캔이 중지되었으면 데이터 처리 중단
    if (_isDisposed || !mounted || _scanStopped) {
      return; // 조용히 무시
    }
    
    _dataCount++;
    
    // 로깅을 대폭 줄임 (100개마다 한 번만)
    bool shouldLog = _dataCount % 100 == 0 || 
                     DateTime.now().difference(_lastLogTime).inSeconds >= 5;
    
    if (shouldLog) {
      print('📡 데이터 수신 중... (${_dataCount}개 처리됨)');
      _lastLogTime = DateTime.now();
    }
    
    try {
      final jsonData = jsonDecode(data);
      
      if (jsonData['type'] == 'lidar') {
        _handleLidarDataQuiet(jsonData, shouldLog);
      } else {
        _handleGeneralMessage(jsonData, data);
      }
      
    } catch (e) {
      if (shouldLog) {
        print('❌ JSON 파싱 에러: $e');
      }
      _safeSetState(() {
        _addMessage('[에러] JSON 파싱 실패');
      });
    }
  }
  
  void _handleLidarDataQuiet(Map<String, dynamic> jsonData, bool shouldLog) {
    if (_isDisposed || !mounted || _scanStopped) return;
    
    try {
      if (shouldLog) {
        print('📊 라이다 채널 ${jsonData['channel']}: ${jsonData['distances']?.length ?? 0}개');
      }
      
      final lidar = Lidar.fromJsonQuiet(jsonData, verbose: shouldLog);
      
      // 로컬 데이터에 저장
      _localLidarData[lidar.channel] = lidar;
      
      /* 거리 수신 출력 비활성화 : sykim
      // UI 업데이트는 조건부로 (1초에 10번만)
      if (_dataCount % 10 == 0) {
        _safeSetState(() {
          _addMessage('[라이다] 채널 ${jsonData['channel']}: ${jsonData['distances']?.length ?? 0}개');
        });
      }
      */
      
    } catch (e) {
      if (shouldLog) {
        print('❌ 라이다 처리 실패: $e');
      }
      _safeSetState(() {
        _addMessage('[에러] 라이다 데이터 처리 실패');
      });
    }
  }
  
  void _handleGeneralMessage(Map<String, dynamic> jsonData, dynamic originalData) {
    if (_isDisposed || !mounted) return;
    
    String messageType = jsonData['type'] ?? 'unknown';
    String messageContent = jsonData['message'] ?? jsonData['status'] ?? originalData.toString();
    
    print('📢 서버 응답: $messageType - $messageContent');
    
    _safeSetState(() {
      _addMessage('[$messageType] $messageContent');
    });
  }
  
  void _handleWebSocketDone() {
    print('🔌 WebSocket 연결 종료');
    if (mounted && !_isDisposed) {
      _safeSetState(() {
        _connected = false;
        _addMessage('연결 종료됨');
      });
    }
  }
  
  void _handleWebSocketError(dynamic error) {
    print('❌ WebSocket 에러: $error');
    if (mounted && !_isDisposed) {
      _safeSetState(() {
        _connected = false;
        _addMessage('에러: $error');
      });
    }
  }
  
  void _addMessage(String message) {
    if (_messages.length > 50) { // 메시지 수 줄임
      _messages.removeAt(0);
    }
    _messages.add('[${DateTime.now().toString().substring(11, 19)}] $message');
  }

  void _resetCameraView() {
    final viewerState = _viewerKey.currentState;
    if (viewerState != null && viewerState is State) {
      // 리플렉션을 사용하지 않고 간단한 방법
      try {
        // dynamic으로 캐스팅해서 메서드 호출
        (viewerState as dynamic).resetCameraView();
        print('✅ 카메라 리셋 성공');
        
        if (mounted && !_isDisposed) {
          _safeSetState(() {
            _addMessage('[시스템] 카메라 뷰가 초기화되었습니다');
          });
        }
      } catch (e) {
        print('❌ 카메라 리셋 실패: $e');
        if (mounted && !_isDisposed) {
          _safeSetState(() {
            _addMessage('[에러] 카메라 초기화 실패: $e');
          });
        }
      }
    } else {
      print('❌ 3D 뷰어 상태를 찾을 수 없음');
      if (mounted && !_isDisposed) {
        _safeSetState(() {
          _addMessage('[에러] 3D 뷰어가 아직 준비되지 않았습니다');
        });
      }
    }
  }

  // 🎯 카메라 상태 저장 (resetCameraView와 동일한 패턴)
  void _saveCameraState() {
    final viewerState = _viewerKey.currentState;
    if (viewerState != null && viewerState is State) {
      try {
        // resetCameraView()와 동일한 호출 방식
        _savedCameraState = (viewerState as dynamic).getCameraState();
        print('📷 카메라 상태 저장됨');
        
        if (mounted && !_isDisposed) {
          _safeSetState(() {
            _addMessage('[시스템] 카메라 상태가 저장되었습니다');
          });
        }
      } catch (e) {
        print('❌ 카메라 상태 저장 실패: $e');
      }
    }
  }

  // 🎯 카메라 상태 복원 
  void _restoreCameraState() {
    if (_savedCameraState == null) {
      print('⚠️ 저장된 카메라 상태가 없습니다');
      return;
    }

    final viewerState = _viewerKey.currentState;
    if (viewerState != null && viewerState is State) {
      try {
        // resetCameraView()와 동일한 호출 방식
        (viewerState as dynamic).setCameraState(_savedCameraState!);
        print('📷 카메라 상태 복원됨');
        
        if (mounted && !_isDisposed) {
          _safeSetState(() {
            _addMessage('[시스템] 카메라 상태가 복원되었습니다');
          });
        }
        
        _savedCameraState = null; // 복원 후 클리어
        
      } catch (e) {
        print('❌ 카메라 상태 복원 실패: $e');
      }
    }
  }

  void _setTopView() {
  final viewerState = _viewerKey.currentState;
  if (viewerState != null && viewerState is State) {
    try {
      // 🎯 다른 카메라 메서드들과 동일한 dynamic 패턴
      (viewerState as dynamic).setTopView();
      print('✅ Top View 설정 성공');
      
      if (mounted && !_isDisposed) {
        _safeSetState(() {
          _addMessage('[시스템] Top-Down View로 전환되었습니다');
        });
      }
    } catch (e) {
      print('❌ Top View 설정 실패: $e');
      if (mounted && !_isDisposed) {
        _safeSetState(() {
          _addMessage('[에러] Top View 전환 실패: $e');
        });
      }
    }
  }
}
  
void _exitTopView() {
  final viewerState = _viewerKey.currentState;
  if (viewerState != null && viewerState is State) {
    try {
      // 🎯 다른 카메라 메서드들과 동일한 dynamic 패턴
      (viewerState as dynamic).exitTopView();
      print('✅ Top View 고정 종료');
      
      if (mounted && !_isDisposed) {
        _safeSetState(() {
          _addMessage('[시스템] Top-Down View가 종료되었습니다');
        });
      }
    } catch (e) {
      print('❌ Top View 종료 실패: $e');
      if (mounted && !_isDisposed) {
        _safeSetState(() {
          _addMessage('[에러] Top View 종료: $e');
        });
      }
    }
  }
}

  void _disconnect() {
    print('🔌 연결 해제 시작');
    
    if (_connected && _channel != null && !_scanStopped) {
      print('🛑 dispose 시 스캔 중지 신호 전송 (즉시)');
      try {
        _sendMessage('{"type":"stop_scan"}');
      } catch (e) {
        print('⚠️ dispose 시 스캔 중지 실패: $e');
      }
    } 
    
    _scanStopped = true; // 스캔 중지 플래그 설정
    
    _webSocketSubscription?.cancel();
    _webSocketSubscription = null;
    
    _channel?.sink.close();
    _channel = null;
    
    if (mounted && !_isDisposed) {
      _safeSetState(() {
        _connected = false;
        _addMessage('연결 해제됨');
      });
    }
    
    print('✅ 연결 해제 완료');
  }
  
  void _sendMessage(String message) {
    if (_connected && _channel != null && !_isDisposed) {
      try {
        // 스캔 중지 명령 감지
        if (message.contains('stop_scan')) {
          print('🛑 스캔 중지 명령 전송');
          _scanStopped = true; // 즉시 로컬 처리 중단
        } else if (message.contains('start_scan')) {
          print('▶️ 스캔 시작 명령 전송');
          _scanStopped = false; // 스캔 재개
          _dataCount = 0; // 카운터 리셋
        }
        
        _channel!.sink.add(message);
        print('📤 송신: $message');
      } catch (e) {
        print('❌ 메시지 전송 실패: $e');
      }
    }
  }

  void _safeSetState(VoidCallback fn) {
    if (!_isDisposed && mounted) {
      try {
        setState(fn);
      } catch (e) {
        // setState 실패는 조용히 무시
      }
    }
  }

  @override
  void dispose() {
    print('🗑️ MyHomePage dispose 시작');

    if (_connected && _channel != null && !_scanStopped) {
      print('🛑 dispose 시 스캔 중지 신호 전송 (즉시)');
      try {
        _sendMessage('{"type":"stop_scan"}');
      } catch (e) {
        print('⚠️ dispose 시 스캔 중지 실패: $e');
      }
    }    

    _isDisposed = true;
    _scanStopped = true;
    
    _providerUpdateTimer?.cancel();
    _providerUpdateTimer = null;
    
    _webSocketSubscription?.cancel();
    _webSocketSubscription = null;
    
    _channel?.sink.close();
    _channel = null;
    
    _localLidarData.clear();
    _urlController.dispose();
    
    print('✅ MyHomePage dispose 완료');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Map<int, Lidar> lidarDatas = {};
    
    if (!_isDisposed && mounted) {
      try {
        lidarDatas = ref.watch(lidarDataProvider);
      } catch (e) {
        lidarDatas = Map.from(_localLidarData);
      }
      
      if (lidarDatas.isEmpty && _localLidarData.isNotEmpty) {
        lidarDatas = Map.from(_localLidarData);
      }
    }

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
            
            // 3D 뷰 제어 패널
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
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
                              ],
                              onChanged: (value) {
                                if (!_isDisposed && mounted) {
                                  setState(() {
                                    _colorMode = value ?? 'distance';
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('크기: '),
                            SizedBox(
                              width: 120,
                              child: Slider(
                                value: _pointSize,
                                min: 0.05,
                                max: 2.0,
                                divisions: 100,
                                onChanged: (value) {
                                  if (!_isDisposed && mounted) {
                                    setState(() {
                                      _pointSize = value;
                                    });
                                  }
                                },
                              ),
                            ),
                            SizedBox(
                              width: 50,
                              child: Text(_pointSize.toStringAsFixed(2)),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start, // 왼쪽 정렬
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('그리드: '),
                                Checkbox(
                                  value: _showGrid,
                                  onChanged: (value) {
                                    if (!_isDisposed && mounted) {
                                      setState(() {
                                        _showGrid = value ?? true;
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('AXIS: '),
                                Checkbox(
                                  value: _showAxis,
                                  onChanged: (value) {
                                    if (!_isDisposed && mounted) {
                                      setState(() {
                                        _showAxis = value ?? true;
                                      });
                                    }
                                  },
                                ),
                              ],
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
                                if (!_isDisposed && mounted) {
                                  setState(() {
                                    _gridStep = value ?? 1.0;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _resetCameraView,
                              icon: const Icon(Icons.camera_alt, size: 16),
                              label: const Text('뷰 초기화'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green[600],
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
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
                            child: Row(
                              children: [
                                const Text('수신 메시지'),
                                const Spacer(), 
                              ],
                            ),
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
                    flex: 3,
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
                              color: Colors.grey,
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
                                // 스캔 상태 표시
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: (_connected ? (_scanStopped ? Colors.red : Colors.green) : Colors.grey),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${_connected ? (_scanStopped ? "중지됨" : "스캔중") : "대기중"}',
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Simple3DViewer(
                              key: _viewerKey,
                              channels: lidarDatas,
                              pointSize: _pointSize,
                              colorMode: _colorMode,
                              showGrid: _showGrid,
                              showAxis: _showAxis,
                              gridStep: _gridStep,
                              areaDrawing: _areaDrawing,
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
                  onPressed: _connected && _channel != null && !_isDisposed
                      ? () => _sendMessage('{"type":"ping", "timestamp":"${DateTime.now().millisecondsSinceEpoch}"}')
                      : null,
                  child: const Text('핑 테스트'),
                ),
                ElevatedButton(
                  onPressed: _connected && _channel != null && !_isDisposed
                      ? () {
                          _sendMessage('{"type":"start_scan"}');
                          setState(() {
                            _scanStopped = false;
                          });
                        }
                      : null,
                  child: Text(_scanStopped ? '스캔 시작' : '스캔 중'),
                ),
                ElevatedButton(
                  onPressed: _connected && _channel != null && !_isDisposed && !_scanStopped
                      ? () {
                          _sendMessage('{"type":"stop_scan"}');
                          setState(() {
                            _scanStopped = true;
                          });
                        }
                      : null,
                  child: const Text('스캔 중지'),
                ),
                ElevatedButton(
                  onPressed: _connected && _channel != null && !_isDisposed
                      ? () => _sendMessage('{"type":"get_status"}')
                      : null,
                  child: const Text('상태 확인'),
                ),
                ElevatedButton(
                  onPressed: _connected && _channel != null && !_isDisposed
                      ? () {
                          setState(() {
                            _areaDrawing = !_areaDrawing;
                            if(_areaDrawing) {
                              _saveCameraState();
                              _setTopView();
                            } else {
                              _restoreCameraState();
                              _exitTopView();
                            }
                          });
                        }
                      : null,
                  child: Text(_areaDrawing ? '영역 그리기 종료' : '영역 그리기 시작'),
                ),
                ElevatedButton(
                  onPressed: _connected && _channel != null && !_isDisposed && _areaDrawing
                      ? () {
                          
                        }
                      : null,
                  child: const Text('영역 그리기 설정'),
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