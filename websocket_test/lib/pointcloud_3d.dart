import 'dart:html' as html;
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:three_dart/three_dart.dart' as three;
import 'package:three_dart_jsm/three_dart_jsm.dart' as three_jsm;
import 'lidar.dart';

class PointCloud3DWidget extends StatefulWidget {
  final Map<int, Lidar> channels;
  final double pointSize;
  final String colorMode; // 'distance', 'channel', 'intensity'

  const PointCloud3DWidget({
    Key? key,
    required this.channels,
    this.pointSize = 0.05,
    this.colorMode = 'distance',
  }) : super(key: key);

  @override
  _PointCloud3DWidgetState createState() => _PointCloud3DWidgetState();
}

class _PointCloud3DWidgetState extends State<PointCloud3DWidget> {
  late three.WebGLRenderer renderer;
  late three.Scene scene;
  late three.PerspectiveCamera camera;
  late three_jsm.OrbitControls controls;
  late html.CanvasElement canvas;
  
  three.Points? currentPointCloud;
  bool isInitialized = false;
  String viewId = '';

  @override
  void initState() {
    super.initState();
    viewId = 'pointcloud-3d-${DateTime.now().millisecondsSinceEpoch}';
    
    // HTML 뷰 등록
    ui.platformViewRegistry.registerViewFactory(viewId, (int id) {
      canvas = html.CanvasElement()
        ..width = 800
        ..height = 600
        ..style.width = '100%'
        ..style.height = '100%';
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          initThreeJS();
        }
      });
      
      return canvas;
    });
  }

  void initThreeJS() {
    if (isInitialized) return;
    
    try {
      // Scene 초기화
      scene = three.Scene();
      scene.background = three.Color(0x0a0a0a);
      
      // Camera 초기화
      camera = three.PerspectiveCamera(75, canvas.width! / canvas.height!, 0.1, 1000);
      camera.position.set(10, 10, 10);
      camera.lookAt(three.Vector3(0, 0, 0));
      
      // Renderer 초기화
      renderer = three.WebGLRenderer({
        'canvas': canvas,
        'antialias': true,
        'alpha': true,
      });
      
      renderer.setSize(canvas.width!, canvas.height!);
      renderer.shadowMap.enabled = true;
      renderer.shadowMap.type = three.PCFSoftShadowMap;
      
      // 조명 추가
      var ambientLight = three.AmbientLight(three.Color(0x404040), 0.4);
      scene.add(ambientLight);
      
      var directionalLight = three.DirectionalLight(three.Color(0xffffff), 0.8);
      directionalLight.position.set(20, 20, 10);
      directionalLight.castShadow = true;
      scene.add(directionalLight);
      
      // 컨트롤 초기화
      controls = three_jsm.OrbitControls(camera, renderer.domElement);
      controls.enableDamping = true;
      controls.dampingFactor = 0.05;
      controls.maxDistance = 200;
      controls.minDistance = 1;
      
      // 좌표축 헬퍼 추가
      var axesHelper = three.AxesHelper(5);
      scene.add(axesHelper);
      
      // 그리드 헬퍼 추가
      var gridHelper = three.GridHelper(20, 20, three.Color(0x444444), three.Color(0x222222));
      scene.add(gridHelper);
      
      isInitialized = true;
      
      // 초기 포인트클라우드 생성
      updatePointCloud();
      
      // 애니메이션 시작
      animate();
    } catch (e) {
      print('ThreeJS 초기화 오류: $e');
    }
  }

  void updatePointCloud() {
    if (!isInitialized) return;
    
    // 기존 포인트클라우드 제거
    if (currentPointCloud != null) {
      scene.remove(currentPointCloud!);
      currentPointCloud!.geometry.dispose();
      currentPointCloud!.material.dispose();
    }
    
    if (widget.channels.isEmpty) return;
    
    // 모든 채널의 3D 포인트 수집
    List<Point3D> allPoints = [];
    widget.channels.values.forEach((lidar) {
      allPoints.addAll(lidar.to3DPoints());
    });
    
    if (allPoints.isEmpty) return;
    
    // 버텍스 및 컬러 데이터 준비
    List<double> vertices = [];
    List<double> colors = [];
    
    // 거리 범위 계산 (색상 정규화용)
    double minDistance = allPoints.map((p) => p.distance).reduce(math.min);
    double maxDistance = allPoints.map((p) => p.distance).reduce(math.max);
    
    for (var point in allPoints) {
      // 좌표 추가 (스케일 조정)
      vertices.addAll([
        point.x * 0.1, // 스케일 다운
        point.z * 0.1, // Y와 Z 축 교환 (라이다 좌표계 -> 3D 뷰 좌표계)
        point.y * 0.1,
      ]);
      
      // 색상 계산
      List<double> color = calculatePointColor(point, minDistance, maxDistance);
      colors.addAll(color);
    }
    
    // BufferGeometry 생성
    var geometry = three.BufferGeometry();
    geometry.setAttribute('position', 
        three.Float32BufferAttribute(Float32Array.fromList(vertices), 3));
    geometry.setAttribute('color', 
        three.Float32BufferAttribute(Float32Array.fromList(colors), 3));
    
    // 포인트 머티리얼 생성
    var material = three.PointsMaterial({
      'size': widget.pointSize,
      'vertexColors': true,
      'transparent': true,
      'opacity': 0.8,
      'sizeAttenuation': false,
    });
    
    // 포인트 메쉬 생성
    currentPointCloud = three.Points(geometry, material);
    scene.add(currentPointCloud!);
  }

  List<double> calculatePointColor(Point3D point, double minDistance, double maxDistance) {
    switch (widget.colorMode) {
      case 'distance':
        // 거리 기반 색상 (가까우면 빨강, 멀면 파랑)
        double normalized = maxDistance > minDistance 
            ? (point.distance - minDistance) / (maxDistance - minDistance)
            : 0.0;
        return [1.0 - normalized, 0.0, normalized];
        
      case 'channel':
        // 채널 기반 색상
        double hue = (point.channel * 60) % 360;
        return hsvToRgb(hue, 1.0, 1.0);
        
      case 'intensity':
        // 강도 기반 색상 (그레이스케일)
        return [point.intensity, point.intensity, point.intensity];
        
      default:
        return [1.0, 1.0, 1.0]; // 기본 흰색
    }
  }

  List<double> hsvToRgb(double h, double s, double v) {
    h = h / 60.0;
    int i = h.floor();
    double f = h - i;
    double p = v * (1 - s);
    double q = v * (1 - s * f);
    double t = v * (1 - s * (1 - f));
    
    switch (i % 6) {
      case 0: return [v, t, p];
      case 1: return [q, v, p];
      case 2: return [p, v, t];
      case 3: return [p, q, v];
      case 4: return [t, p, v];
      case 5: return [v, p, q];
      default: return [1.0, 1.0, 1.0];
    }
  }

  void animate() {
    if (!mounted || !isInitialized) return;
    
    controls.update();
    renderer.render(scene, camera);
    
    // 다음 프레임 요청
    html.window.requestAnimationFrame((timestamp) => animate());
  }

  @override
  void didUpdateWidget(PointCloud3DWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channels != widget.channels ||
        oldWidget.colorMode != widget.colorMode ||
        oldWidget.pointSize != widget.pointSize) {
      updatePointCloud();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 800,
      height: 600,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: HtmlElementView(viewType: viewId),
      ),
    );
  }

  @override
  void dispose() {
    if (isInitialized) {
      renderer.dispose();
      if (currentPointCloud != null) {
        currentPointCloud!.geometry.dispose();
        currentPointCloud!.material.dispose();
      }
    }
    super.dispose();
  }
}