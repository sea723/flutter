// simple_3d_viewer.dart - 메인 3D 뷰어 위젯 (분할 완료)
import 'dart:html' as html;
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';

// 분할된 모듈들 import
import '../lidar.dart';
import 'coordinate_transform.dart';
import 'input_handler.dart';
import 'grid_renderer.dart';
import 'point_renderer.dart';
import 'performance_manager.dart';

class Simple3DViewer extends StatefulWidget {
  final Map<int, Lidar> channels;
  final double pointSize;
  final String colorMode;
  final bool showGrid;
  final bool showAxis;
  final double gridStep;
  final bool areaDrawing;
  final VoidCallback? onResetCamera;

  const Simple3DViewer({
    Key? key,
    required this.channels,
    this.pointSize = 2.0,
    this.colorMode = 'distance',
    this.showGrid = true,
    this.showAxis = true,
    this.gridStep = 1.0,
    this.areaDrawing = false,
    this.onResetCamera,
  }) : super(key: key);

  @override
  State<Simple3DViewer> createState() => _Simple3DViewerState();
}

class _Simple3DViewerState extends State<Simple3DViewer> {
  late html.CanvasElement canvas;
  late html.CanvasRenderingContext2D ctx;
  String viewId = '';
  
  // 3D 변환 상태
  double rotationX = 0.8;
  double rotationY = 0.0;
  double rotationZ = 0.0;
  double zoom = 10.0;
  double panX = 0.0;
  double panY = 150.0;
  bool isTopViewMode = false;

  // 회전 상태 추적
  bool isRotating = false;
  List<Point3D> lastPointsCache = []; 

    // 🔧 초기값 저장 (클래스 내부에서 관리)
  late final double _initialRotationX;
  late final double _initialRotationY;
  late final double _initialRotationZ;
  late final double _initialZoom;
  late final double _initialPanX;
  late final double _initialPanY;

  // 분할된 모듈들
  late InputHandler inputHandler;
  late PerformanceManager performanceManager;

  @override
  void initState() {
    super.initState();

    _initialRotationX = rotationX;
    _initialRotationY = rotationY;
    _initialRotationZ = rotationZ;
    _initialZoom = zoom;
    _initialPanX = panX;
    _initialPanY = panY;
    
    if (widget.onResetCamera != null) {
      // 여기서는 직접 연결하지 않고, 부모가 호출할 방법을 제공
    }


    // 모듈 초기화
    inputHandler = InputHandler(
      onRotationChanged: _onRotationChanged,
      onPanChanged: _onPanChanged,
      onZoomChanged: _onZoomChanged,
      onCoordinateClicked: _onCoordinateClicked,
      onRenderRequested: _requestRender,
      onRotationStateChanged: _onRotationStateChanged, 
    );
    
    performanceManager = PerformanceManager();
    
    // 뷰 등록
    viewId = 'simple-3d-${DateTime.now().millisecondsSinceEpoch}';
    
    ui.platformViewRegistry.registerViewFactory(viewId, (int id) {
      canvas = html.CanvasElement()
        ..width = 800
        ..height = 600
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = '#1a1a1a'
        ..tabIndex = 0;
      
      ctx = canvas.getContext('2d') as html.CanvasRenderingContext2D;
      
      // 입력 핸들러 설정
      inputHandler.setupEventListeners(canvas, ctx);
        
      // 초기화 완료 후 렌더링
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) {
              performanceManager.initializeGridCache(canvas.width!, canvas.height!);
              render();
            }
          });
        }
      });
      
      return canvas;
    });
  }

  // === 콜백 함수들 ===
  /// 🎯 회전 상태 변경 콜백
  void _onRotationStateChanged(bool rotating) {
    setState(() {
      isRotating = rotating;
    });
    
    if (!rotating) {
      // 회전이 끝나면 즉시 풀 렌더링
      render();
    }
  }

  void _onRotationChanged(double deltaX, double deltaY, double deltaZ) {
    if (isTopViewMode) return;

    setState(() {
      rotationX += deltaX;
      rotationY += deltaY;
      rotationZ += deltaZ;
    });
  }

  void _onPanChanged(double deltaX, double deltaY) {
    setState(() {
      panX += deltaX;
      panY += deltaY;
    });
  }

  void _onZoomChanged(double factor) {
    setState(() {
      zoom *= factor;
      zoom = zoom.clamp(0.05, 100.0);
    });
  }

  void _onCoordinateClicked(Point3D screenCoord) {
    if(!widget.areaDrawing) return;
    
    Point3D? worldCoord = CoordinateTransform.getWorldCoordinateFromMouse(
      screenCoord.x, // 화면 X
      screenCoord.y, // 화면 Y
      canvas.width!,
      canvas.height!,
      panX,
      panY,
      zoom,
      rotationX,
      rotationY,
      rotationZ,
    );
    
    if (worldCoord != null) {
      print('🎯 최종 좌표: X=${worldCoord.x.toStringAsFixed(2)}m, Y=${worldCoord.y.toStringAsFixed(2)}m, Z=${worldCoord.z.toStringAsFixed(2)}m');
      print('   거리: ${worldCoord.distance.toStringAsFixed(2)}m');
      
      // 🎯 그리드 스냅 옵션 제공
      Point3D snappedCoord = Point3D(
        x: worldCoord.x.round().toDouble(),
        y: worldCoord.y.round().toDouble(),
        z: 0,
        distance: math.sqrt(worldCoord.x.round() * worldCoord.x.round() + 
                          worldCoord.y.round() * worldCoord.y.round()),
        channel: 0, pointIndex: 0, verticalAngle: 0
      );
      
      print('📍 그리드 스냅: (${snappedCoord.x.toInt()}, ${snappedCoord.y.toInt()})');
      
      // 오차가 0.3 이하면 스냅된 값 사용
      double snapError = math.sqrt(
        math.pow(worldCoord.x - snappedCoord.x, 2) + 
        math.pow(worldCoord.y - snappedCoord.y, 2)
      );
      
      Point3D finalCoord = snapError < 0.3 ? snappedCoord : worldCoord;
      
      // 화면에 좌표 표시
      inputHandler.showCoordinateMarker(screenCoord.x, screenCoord.y, finalCoord);
      
      // 3초 후 다시 렌더링 (마커 제거)
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) render();
      });
    } else {
      print('❌ 좌표 변환 실패');
    }
  }

  void _requestRender() {
    render();
  }

  // === 메인 렌더링 함수 ===

  void render() {
    if (!mounted) return;
    
    // 프레임 제한 확인
    if (!performanceManager.canRender()) {
      return;
    }
    
    // FPS 업데이트
    performanceManager.updateFPS();
    
    // 캔버스 지우기
    ctx.fillStyle = '#1a1a1a';
    ctx.fillRect(0, 0, canvas.width!, canvas.height!);
    
    // 3D 포인트 데이터 수집
    List<Point3D> allPoints = [];
    widget.channels.values.forEach((lidar) {
      List<Point3D> points = lidar.to3DPoints();
      allPoints.addAll(points);
    });
    
    if (allPoints.isEmpty) {
      _showWaitingMessage();
      return;
    }
    
    double centerX = canvas.width! / 2 + panX;
    double centerY = canvas.height! / 2 + panY;
    
    // 성능 디버깅 정보 출력
    _debugPerformanceInfo();
    
    // 그리드 렌더링
    if (widget.showGrid) {
      _renderGrid(centerX, centerY);
    }
    
    // 🎯 회전 상태에 따른 포인트 렌더링
    if (isRotating) {
      // 회전 중: 간단한 렌더링 또는 캐시 사용
      _renderDuringRotation(centerX, centerY, allPoints);
    } else {
      // 정상 상태: 모든 포인트 렌더링
      _renderFullQuality(centerX, centerY, allPoints);
      // 캐시 업데이트
      lastPointsCache = List.from(allPoints);
    }

    // 좌표축 그리기
    if (widget.showAxis) {
      _drawAxes(centerX, centerY);
    }
  }


  /// 🎯 회전 중 경량 렌더링
  void _renderDuringRotation(double centerX, double centerY, List<Point3D> allPoints) {
    if (allPoints.isEmpty) return;
    
    DateTime start = DateTime.now();
    
    // 방법 1: LOD 적용 (데이터 양 줄이기)
    List<Point3D> lodPoints = allPoints.where((p) => p.pointIndex % 4 == 0).toList();
    
    // 방법 2: 단일 색상으로 빠른 렌더링
    ctx.fillStyle = '#888888'; // 회전 중엔 회색
    ctx.beginPath();
    
    int renderedCount = 0;
    for (var point in lodPoints) {
      Map<String, double>? projection = CoordinateTransform.projectToScreen(
        point, centerX, centerY, zoom, rotationX, rotationY, rotationZ,
        zOffset: 200
      );
      
      if (projection == null) continue;
      
      double screenX = projection['x']!;
      double screenY = projection['y']!;
      
      if (screenX < -50 || screenX > canvas.width! + 50 || 
          screenY < -50 || screenY > canvas.height! + 50) continue;
      
      // 작은 사각형으로 빠른 렌더링
      ctx.rect(screenX - 1, screenY - 1, 2, 2);
      renderedCount++;
    }
    
    ctx.fill();
  }
  
  /// 🎯 정상 품질 렌더링
  void _renderFullQuality(double centerX, double centerY, List<Point3D> allPoints) {
    if (allPoints.isEmpty) {
      _showWaitingMessage();
      return;
    }
    
    // 기존 고품질 렌더링
    PointRenderer.renderPoints(
      ctx,
      allPoints,
      centerX,
      centerY,
      zoom,
      rotationX,
      rotationY,
      rotationZ,
      canvas.width!,
      canvas.height!,
      widget.colorMode,
      widget.pointSize,
    );
  }

  void resetCameraView() {
    setState(() {
      rotationX = _initialRotationX;
      rotationY = _initialRotationY;
      rotationZ = _initialRotationZ;
      zoom = _initialZoom;
      panX = _initialPanX;
      panY = _initialPanY;
    });
    
    print('📷 카메라 뷰 초기화 완료');
  }

  Map<String, double> getCameraState() {
    return {
      'rotationX': rotationX,
      'rotationY': rotationY,
      'rotationZ': rotationZ,
      'zoom': zoom,
      'panX': panX,
      'panY': panY,
    };
  }

  void setCameraState(Map<String, double> state) {
    setState(() {
      rotationX = state['rotationX'] ?? rotationX;
      rotationY = state['rotationY'] ?? rotationY;
      rotationZ = state['rotationZ'] ?? rotationZ;
      zoom = state['zoom'] ?? zoom;
      panX = state['panX'] ?? panX;
      panY = state['panY'] ?? panY;
    });
    print('📷 카메라 상태 복원 완료');
  }

  void setTopView() {
    setState(() {
      isTopViewMode = true;

      rotationX = 0.0;
      rotationY = 0.0;
      rotationZ = 0.0;
      panX = 0.0;
      panY = 150;
    });
    print('📷 카메라 Top-Down View 설정');
  }

  void exitTopView() {
    setState(() {
      isTopViewMode = false;  // ← Top View 모드 비활성화
    });
    print('📷 일반 3D 모드로 복원 (회전 가능)');
  }
  
  // === 그리드 렌더링 ===

  void _renderGrid(double centerX, double centerY) {
    // 라이다 설정 가져오기
    double maxRange = 50.0;
    double hfov = 360.0;
    if (widget.channels.isNotEmpty) {
      maxRange = widget.channels.values.first.maxRange;
      hfov = widget.channels.values.first.hfov;
    }
    
    // 캐시 확인 및 업데이트
    if (performanceManager.shouldInvalidateCache(rotationX, rotationY, rotationZ, zoom, panX, panY) || 
        performanceManager.gridCacheInvalid) {
      _updateGridCache(centerX, centerY, maxRange, hfov);
      performanceManager.saveCurrentState(rotationX, rotationY, rotationZ, zoom, panX, panY);
    }
    
    // 캐시된 그리드 그리기
    if (performanceManager.gridCache != null) {
      ctx.drawImage(performanceManager.gridCache!, 0, 0);
    }
  }

  void _updateGridCache(double centerX, double centerY, double maxRange, double hfov) {
    if (performanceManager.gridCache == null) return;
    
    var cacheCtx = performanceManager.gridCache!.getContext('2d') as html.CanvasRenderingContext2D;
    
    // 캐시 캔버스 지우기
    cacheCtx.clearRect(0, 0, performanceManager.gridCache!.width!, performanceManager.gridCache!.height!);
    
    // 바둑판 그리드
    GridRenderer.drawSquareGrid(
      cacheCtx, centerX, centerY, maxRange, widget.gridStep,
      zoom, rotationX, rotationY, rotationZ,
      canvas.width!, canvas.height!, panX, panY,
    );
    
    // 원형 그리드
    GridRenderer.drawCircularGrid(
      cacheCtx, centerX, centerY, maxRange, widget.gridStep,
      zoom, rotationX, rotationY, rotationZ,
      canvas.width!, canvas.height!, panX, panY,
    );
    
    // 방사형 그리드
    GridRenderer.drawRadialGrid(
      cacheCtx, centerX, centerY, maxRange, hfov,
      zoom, rotationX, rotationY, rotationZ,
      canvas.width!, canvas.height!, panX, panY,
    );
    
    // 거리 라벨
    GridRenderer.drawDistanceLabels(
      cacheCtx, centerX, centerY, widget.gridStep, maxRange,
      rotationX, rotationY, rotationZ, zoom,
    );
    
    performanceManager.gridCacheInvalid = false;
  }

  // === 좌표축 그리기 ===

  void _drawAxes(double centerX, double centerY) {
    double axisLength = 6.5;
    
    Point3D xAxisEnd = Point3D(x: axisLength, y: 0, z: 0, distance: 0, channel: 0, pointIndex: 0, verticalAngle: 0);
    Point3D yAxisEnd = Point3D(x: 0, y: axisLength, z: 0, distance: 0, channel: 0, pointIndex: 0, verticalAngle: 0);
    Point3D zAxisEnd = Point3D(x: 0, y: 0, z: -axisLength, distance: 0, channel: 0, pointIndex: 0, verticalAngle: 0); //왼손좌표계 -> 오른손좌표계
    
    Point3D xAxis = CoordinateTransform.rotatePoint(xAxisEnd, rotationX, rotationY, rotationZ);
    Point3D yAxis = CoordinateTransform.rotatePoint(yAxisEnd, rotationX, rotationY, rotationZ);
    Point3D zAxis = CoordinateTransform.rotatePoint(zAxisEnd, rotationX, rotationY, rotationZ);
    
    double orthographicScale = zoom;
    
    // X축 (빨강)
    _drawAxisLine(centerX, centerY, xAxis, orthographicScale, '#ff0000', 'X');
    
    // Y축 (초록)
    _drawAxisLine(centerX, centerY, yAxis, orthographicScale, '#00ff00', 'Y');
    
    // Z축 (파랑)
    _drawAxisLine(centerX, centerY, zAxis, orthographicScale, '#0000ff', 'Z');
  }

  void _drawAxisLine(double centerX, double centerY, Point3D axis, double scale, String color, String label) {
    double endX = centerX + axis.x * scale;
    double endY = centerY - axis.y * scale;
    
    ctx.strokeStyle = color;
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(centerX, centerY);
    ctx.lineTo(endX, endY);
    ctx.stroke();
    
    // 라벨
    ctx.fillStyle = '#ffffff';
    ctx.font = '12px Arial';
    ctx.fillText(label, endX + 3, endY + 3);
  }

  // === 유틸리티 함수들 ===

  void _showWaitingMessage() {
    ctx.fillStyle = '#ffffff';
    ctx.font = '16px Arial';
    ctx.textAlign = 'center';
    // ctx.fillText('라이다 데이터 대기 중...', canvas.width! / 2, canvas.height! / 2);
  }

  void _debugPerformanceInfo() {
    performanceManager.debugPerformanceInfo(
      zoom: zoom,
      panX: panX,
      panY: panY,
      canvasWidth: canvas.width!,
      canvasHeight: canvas.height!,
      maxRange: widget.channels.isNotEmpty ? widget.channels.values.first.maxRange : 50.0,
      gridStep: widget.gridStep,
    );
  }

  // === 위젯 생명주기 ===

  @override
  void didUpdateWidget(Simple3DViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 그리드 설정이 변경되면 캐시 무효화
    if (oldWidget.showGrid != widget.showGrid ||
        oldWidget.gridStep != widget.gridStep ||
        oldWidget.channels != widget.channels ||
        oldWidget.colorMode != widget.colorMode ||
        oldWidget.pointSize != widget.pointSize) {
      performanceManager.gridCacheInvalid = true;
      if (mounted) render();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          // 메인 3D 뷰어
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(8),
              bottomRight: Radius.circular(8),
            ),
            child: HtmlElementView(viewType: viewId),
          ),
          
          // 성능 정보 표시 (오른쪽 상단)
          // Positioned(
          //   top: 10,
          //   right: 10,
          //   child: Container(
          //     padding: const EdgeInsets.all(4),
          //     decoration: BoxDecoration(
          //       color: Colors.black54,
          //       borderRadius: BorderRadius.circular(4),
          //     ),
          //     child: Text(
          //       '${performanceManager.currentFPS.toStringAsFixed(1)}fps | 모듈화 완료',
          //       style: const TextStyle(
          //         color: Colors.white,
          //         fontSize: 10,
          //       ),
          //     ),
          //   ),
          // ),
          
          // 컨트롤 가이드 (왼쪽 하단)
          Positioned(
            bottom: 10,
            left: 10,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('🖱️ 클릭: 좌표 측정', style: TextStyle(color: Colors.white, fontSize: 10)),
                  Text('🖱️ 드래그: 회전', style: TextStyle(color: Colors.white, fontSize: 10)),
                  Text('⇧ + 드래그: 이동', style: TextStyle(color: Colors.white, fontSize: 10)),
                  Text('⌃ + 드래그: Z축 회전', style: TextStyle(color: Colors.white, fontSize: 10)),
                  Text('🖱️ 휠: 줌', style: TextStyle(color: Colors.white, fontSize: 10)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    performanceManager.dispose();
    inputHandler.reset();
    super.dispose();
  }
}