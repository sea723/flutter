import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'lidar.dart';
import 'pointcloud.dart';
final lidarDataProvider =  StateProvider<Map<int, Lidar>>((ref) => {});

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
        final jsonData = jsonDecode(data);
        if (jsonData['type'] == 'lidar') {
          final lidar = Lidar.fromJson(jsonData);
          final channels = {...ref.read(lidarDataProvider)};
          channels[lidar.channel] = lidar;
          ref.read(lidarDataProvider.notifier).state = channels;
        }
        setState(() {
          _messages.add(jsonData.toString());
        });
      }, onDone: () {
        print('연결 종료');
        setState(() {
          _connected = false;
        });
      }, onError: (error) {
        print('에러 발생: $error');
        setState(() {
          _connected = false;
          _messages.add('에러: $error');
        });
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
    _channel?.sink.close();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lidarDatas = ref.watch(lidarDataProvider);
    final firstLidar = lidarDatas.isNotEmpty ? lidarDatas.values.first : null;
    final angle = firstLidar?.hfov ?? 360;
    final vfov = firstLidar?.vfov is double ? firstLidar!.vfov as double : 30.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter WebSocket Demo Page'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
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
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black26),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _messages.isEmpty
                    ? const Center(child: Text('수신 메시지 표시'))
                    : ListView.builder(
                        itemCount: _messages.length,
                        itemBuilder: (context, idx) => ListTile(
                          title: Text(_messages[idx]),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ElevatedButton(
                          onPressed: _connected && _channel != null
                              ? () => _channel!.sink.add('{"type":"test1"}')
                              : null,
                          child: const Text('메시지 1'),
                        ),
                        // ... 추가 버튼들
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (lidarDatas != null)
              SizedBox(
                width: 400,
                height: 400,
                child: CustomPaint(
                  painter: PointCloudPainter(lidarDatas, angle, vfov),
                ),
              )
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
        home: MyHomePage(),
      ),
    ),
  );
}