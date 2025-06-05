// simple_3d_viewer.dart
import 'dart:html' as html;
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'lidar.dart'; // Point3D 클래스가 포함됨

class Simple3DViewer extends StatefulWidget {
  final Map<int, Lidar> channels;
  final double pointSize;
  final String colorMode;
  final bool showGrid; // 그리드 표시 여부 추가
  final double gridStep; // 그리드 간격 추가

  const Simple3DViewer({
    Key? key,
    required this.channels,
    this.pointSize = 2.0,
    this.colorMode = 'distance',
    this.showGrid = true, // 기본값: 그리드 표시
    this.gridStep = 1.0, // 기본값: 1m 간격
  }) : super(key: key);

  @override
  State<Simple3DViewer> createState() => _Simple3DViewerState();
}

class _Simple3DViewerState extends State<Simple3DViewer> {
  late html.CanvasElement canvas;
  late html.CanvasRenderingContext2D ctx;
  String viewId = '';
  
  double rotationX = 0;
  double rotationY = 0;
  double zoom = 1.0;
  bool isDragging = false;
  html.Point? lastMousePos;

  @override
  void initState() {
    super.initState();
    viewId = 'simple-3d-${DateTime.now().millisecondsSinceEpoch}';
    
    // 초기 시점을 라이다 데이터 보기에 적합하게 설정
    rotationX = -0.3; // 약간 위에서 내려다보는 각도
    rotationY = 0.0;  // 정면
    zoom = 0.5;       // 더 멀리서 전체 보기
    
    // HTML 뷰 등록
    ui.platformViewRegistry.registerViewFactory(viewId, (int id) {
      canvas = html.CanvasElement()
        ..width = 800
        ..height = 600
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = '#1a1a1a';
      
      ctx = canvas.getContext('2d') as html.CanvasRenderingContext2D;
      
      // 마우스 이벤트 추가
      canvas.onMouseDown.listen(_onMouseDown);
      canvas.onMouseMove.listen(_onMouseMove);
      canvas.onMouseUp.listen(_onMouseUp);
      canvas.onWheel.listen(_onWheel);
      
      // 첫 렌더링 약간 지연
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) {
              render();
            }
          });
        }
      });
      
      return canvas;
    });
  }

  void _onMouseDown(html.MouseEvent event) {
    isDragging = true;
    lastMousePos = event.client;
  }

  void _onMouseMove(html.MouseEvent event) {
    if (isDragging && lastMousePos != null) {
      double deltaX = event.client.x.toDouble() - lastMousePos!.x.toDouble();
      double deltaY = event.client.y.toDouble() - lastMousePos!.y.toDouble();
      
      setState(() {
        rotationY += deltaX * 0.01;
        rotationX += deltaY * 0.01;
        rotationX = rotationX.clamp(-math.pi/2, math.pi/2);
      });
      
      lastMousePos = event.client;
      render();
    }
  }

  void _onMouseUp(html.MouseEvent event) {
    isDragging = false;
    lastMousePos = null;
  }

  void _onWheel(html.WheelEvent event) {
    setState(() {
      zoom *= (1 - event.deltaY * 0.001);
      zoom = zoom.clamp(0.1, 5.0);
    });
    render();
  }

  void render() {
    if (!mounted) return;
    
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
      // 안내 텍스트
      ctx.fillStyle = '#ffffff';
      ctx.font = '16px Arial';
      ctx.textAlign = 'center';
      ctx.fillText('라이다 데이터 대기 중...', canvas.width! / 2, canvas.height! / 2);
      return;
    }
    
    // 화면 중심
    double centerX = canvas.width! / 2;
    double centerY = canvas.height! / 2;
    
    // 거리 범위 계산
    double minDistance = allPoints.map((p) => p.distance).reduce(math.min);
    double maxDistance = allPoints.map((p) => p.distance).reduce(math.max);
    
    // 포인트 렌더링
    for (var point in allPoints) {
      // 3D 회전 변환
      Point3D rotated = rotatePoint(point, rotationX, rotationY);
      
      // 카메라 앞쪽으로 이동 (모든 포인트가 보이도록)
      rotated = Point3D(
        x: rotated.x,
        y: rotated.y, 
        z: rotated.z + 200, // Z축을 더 앞으로 이동
        distance: rotated.distance,
        channel: rotated.channel,
        intensity: rotated.intensity,
        pointIndex: rotated.pointIndex,
        verticalAngle: rotated.verticalAngle,
      );
      
      // 카메라 뒤쪽 포인트는 렌더링하지 않음
      if (rotated.z <= 50.0) continue;
      
      // 원근 투영 (스케일 대폭 증가)
      double scale = zoom * 1000 / rotated.z;
      double screenX = centerX + rotated.x * scale;
      double screenY = centerY - rotated.y * scale;
      
      // 화면 범위 체크 (여유있게)
      if (screenX >= -100 && screenX < canvas.width! + 100 && 
          screenY >= -100 && screenY < canvas.height! + 100) {
        
        // 색상 계산
        String color = getPointColor(point, minDistance, maxDistance);
        
        // 포인트 크기 (훨씬 더 크게)
        double pointRadius = math.max(widget.pointSize * 2.0, 0.1); // 최소 0.1픽셀
        
        // 포인트 그리기
        ctx.fillStyle = color;
        ctx.beginPath();
        ctx.arc(screenX, screenY, pointRadius, 0, 2 * math.pi);
        ctx.fill();
      }
    }
    
    // 좌표축 그리기
    drawAxes(centerX, centerY);
    
    // 거리 그리드 그리기
    if (widget.showGrid) {
      double maxRange = 50.0;
      if (widget.channels.isNotEmpty) {
        maxRange = widget.channels.values.first.maxRange;
      }
      drawDistanceGrid(centerX, centerY, maxRange, widget.gridStep);
    }
    
    // 디버그 정보 표시 제거
  }

  Point3D rotatePoint(Point3D point, double rotX, double rotY) {
    // Y축 회전
    double cosY = math.cos(rotY);
    double sinY = math.sin(rotY);
    double x1 = point.x * cosY + point.z * sinY;
    double z1 = -point.x * sinY + point.z * cosY;
    
    // X축 회전
    double cosX = math.cos(rotX);
    double sinX = math.sin(rotX);
    double y2 = point.y * cosX - z1 * sinX;
    double z2 = point.y * sinX + z1 * cosX;
    
    return Point3D(
      x: x1,
      y: y2,
      z: z2,
      distance: point.distance,
      channel: point.channel,
      intensity: point.intensity,
      pointIndex: point.pointIndex,
      verticalAngle: point.verticalAngle,
    );
  }

  String getPointColor(Point3D point, double minDistance, double maxDistance) {
    switch (widget.colorMode) {
      case 'distance':
        // 거리 기반 색상 (가까우면 빨강, 멀면 파랑) - 더 밝게
        double normalized = maxDistance > minDistance 
            ? (point.distance - minDistance) / (maxDistance - minDistance)
            : 0.0;
        int red = ((1.0 - normalized) * 255).round();
        int blue = (normalized * 255).round();
        int green = 50; // 약간의 초록 추가로 더 밝게
        return 'rgb($red, $green, $blue)';
        
      case 'channel':
        // 채널 기반 색상 - 더 밝게
        int hue = (point.channel * 60) % 360;
        return 'hsl($hue, 100%, 70%)'; // 70% 밝기
        
      case 'intensity':
        // 강도 기반 색상 (그레이스케일) - 더 밝게
        int gray = math.max((point.intensity * 255).round(), 100); // 최소 100
        return 'rgb($gray, $gray, $gray)';
        
      case 'vertical_angle':
        // 수직 각도 기반 색상 - 더 밝게
        double normalizedAngle = (point.verticalAngle + 90) / 180; 
        int red = math.max(((1.0 - normalizedAngle) * 255).round(), 50);
        int green = math.max((normalizedAngle * 255).round(), 50);
        return 'rgb($red, $green, 100)'; // 파란색도 추가
        
      default:
        return 'rgb(255, 255, 255)'; // 순백색
    }
  }

  void drawAxes(double centerX, double centerY) {
    double axisLength = 30;
    
    // 3개 축 모두 3D 회전 변환 적용 (원점은 고정!)
    Point3D xAxisEnd = Point3D(
      x: axisLength, y: 0, z: 0,  // Z=0으로 통일
      distance: 0, channel: 0, intensity: 0, pointIndex: 0, verticalAngle: 0,
    );
    Point3D yAxisEnd = Point3D(
      x: 0, y: axisLength, z: 0,  // Z=0으로 통일
      distance: 0, channel: 0, intensity: 0, pointIndex: 0, verticalAngle: 0,
    );
    Point3D zAxisEnd = Point3D(
      x: 0, y: 0, z: axisLength,  // Z만 다름
      distance: 0, channel: 0, intensity: 0, pointIndex: 0, verticalAngle: 0,
    );
    
    // 모든 축에 회전 변환 적용
    Point3D xAxis = rotatePoint(xAxisEnd, rotationX, rotationY);
    Point3D yAxis = rotatePoint(yAxisEnd, rotationX, rotationY);
    Point3D zAxis = rotatePoint(zAxisEnd, rotationX, rotationY);
    
    // 원점은 화면 중심에 고정
    double originX = centerX;
    double originY = centerY;
    
    // 직교 투영 사용 (원근 효과 없이 일정한 스케일)
    double orthographicScale = zoom * 3;  // 일정한 스케일
    
    // X축 (빨강)
    double xEndX = centerX + xAxis.x * orthographicScale;
    double xEndY = centerY - xAxis.y * orthographicScale;
    
    ctx.strokeStyle = '#ff0000';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(originX, originY);
    ctx.lineTo(xEndX, xEndY);
    ctx.stroke();
    
    // Y축 (초록)
    double yEndX = centerX + yAxis.x * orthographicScale;
    double yEndY = centerY - yAxis.y * orthographicScale;
    
    ctx.strokeStyle = '#00ff00';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(originX, originY);
    ctx.lineTo(yEndX, yEndY);
    ctx.stroke();
    
    // Z축 (파랑)
    double zEndX = centerX + zAxis.x * orthographicScale;
    double zEndY = centerY - zAxis.y * orthographicScale;
    
    ctx.strokeStyle = '#0000ff';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(originX, originY);
    ctx.lineTo(zEndX, zEndY);
    ctx.stroke();
    
    // 축 라벨
    ctx.fillStyle = '#ffffff';
    ctx.font = '12px Arial';
    ctx.fillText('X', xEndX + 3, xEndY + 3);
    ctx.fillText('Y', yEndX + 3, yEndY - 3);
    ctx.fillText('Z', zEndX + 3, zEndY + 3);
  }

  void drawDistanceGrid(double centerX, double centerY, double maxRange, double gridStep) {
    if (maxRange <= 0 || gridStep <= 0) return;
    
    ctx.strokeStyle = '#444444'; // 조금 더 밝은 회색으로 변경
    ctx.lineWidth = 1;
    ctx.setLineDash([3, 3]); // 점선
    
    // 동심원 그리드 그리기 (gridStep 간격으로)
    for (double distance = gridStep; distance <= maxRange; distance += gridStep) {
      drawDistanceCircle(centerX, centerY, distance);
    }
    
    // 방사형 그리드 그리기 (8방향)
    ctx.strokeStyle = '#333333'; // 방사선은 더 어둡게
    for (int i = 0; i < 8; i++) {
      double angle = (i * 45.0) * (math.pi / 180); // 45도씩
      drawRadialLine(centerX, centerY, angle, maxRange);
    }
    
    ctx.setLineDash([]); // 점선 해제
    
    // 거리 라벨 표시
    drawDistanceLabels(centerX, centerY, gridStep, maxRange, gridStep);
  }

  void drawDistanceCircle(double centerX, double centerY, double distance) {
    List<Point3D> circlePoints = [];
    
    // 원을 그리기 위한 포인트들 생성 (XY 평면)
    for (int i = 0; i <= 36; i++) {
      double angle = (i * 10.0) * (math.pi / 180); // 10도씩
      Point3D point = Point3D(
        x: distance * math.cos(angle),
        y: distance * math.sin(angle),
        z: 0, // XY 평면
        distance: distance,
        channel: 0,
        intensity: 0,
        pointIndex: i,
        verticalAngle: 0,
      );
      circlePoints.add(point);
    }
    
    // 회전 변환 및 화면 투영
    ctx.beginPath();
    bool firstPoint = true;
    
    for (var point in circlePoints) {
      Point3D rotated = rotatePoint(point, rotationX, rotationY);
      rotated = Point3D(
        x: rotated.x,
        y: rotated.y,
        z: rotated.z + 150, // Z 오프셋
        distance: rotated.distance,
        channel: rotated.channel,
        intensity: rotated.intensity,
        pointIndex: rotated.pointIndex,
        verticalAngle: rotated.verticalAngle,
      );
      
      if (rotated.z <= 10.0) continue;
      
      double scale = zoom * 500 / rotated.z;
      double screenX = centerX + rotated.x * scale;
      double screenY = centerY - rotated.y * scale;
      
      if (firstPoint) {
        ctx.moveTo(screenX, screenY);
        firstPoint = false;
      } else {
        ctx.lineTo(screenX, screenY);
      }
    }
    
    ctx.stroke();
  }

  void drawRadialLine(double centerX, double centerY, double angle, double maxDistance) {
    // 중심에서 최대 거리까지 직선
    Point3D startPoint = Point3D(
      x: 0, y: 0, z: 0,
      distance: 0, channel: 0, intensity: 0, pointIndex: 0, verticalAngle: 0,
    );
    
    Point3D endPoint = Point3D(
      x: maxDistance * math.cos(angle),
      y: maxDistance * math.sin(angle),
      z: 0,
      distance: maxDistance, channel: 0, intensity: 0, pointIndex: 0, verticalAngle: 0,
    );
    
    // 회전 변환
    Point3D rotatedStart = rotatePoint(startPoint, rotationX, rotationY);
    Point3D rotatedEnd = rotatePoint(endPoint, rotationX, rotationY);
    
    // Z 오프셋 적용
    rotatedStart = Point3D(
      x: rotatedStart.x, y: rotatedStart.y, z: rotatedStart.z + 150,
      distance: rotatedStart.distance, channel: rotatedStart.channel,
      intensity: rotatedStart.intensity, pointIndex: rotatedStart.pointIndex,
      verticalAngle: rotatedStart.verticalAngle,
    );
    
    rotatedEnd = Point3D(
      x: rotatedEnd.x, y: rotatedEnd.y, z: rotatedEnd.z + 150,
      distance: rotatedEnd.distance, channel: rotatedEnd.channel,
      intensity: rotatedEnd.intensity, pointIndex: rotatedEnd.pointIndex,
      verticalAngle: rotatedEnd.verticalAngle,
    );
    
    if (rotatedStart.z <= 10.0 || rotatedEnd.z <= 10.0) return;
    
    // 화면 투영
    double startScale = zoom * 500 / rotatedStart.z;
    double endScale = zoom * 500 / rotatedEnd.z;
    
    double startX = centerX + rotatedStart.x * startScale;
    double startY = centerY - rotatedStart.y * startScale;
    double endX = centerX + rotatedEnd.x * endScale;
    double endY = centerY - rotatedEnd.y * endScale;
    
    ctx.beginPath();
    ctx.moveTo(startX, startY);
    ctx.lineTo(endX, endY);
    ctx.stroke();
  }

  void drawDistanceLabels(double centerX, double centerY, double gridStep, double maxRange, double stepSize) {
    ctx.fillStyle = '#aaaaaa'; // 더 밝은 회색으로 변경
    ctx.font = '12px Arial'; // 폰트 크기 증가
    ctx.textAlign = 'center';
    
    for (double distance = gridStep; distance <= maxRange; distance += stepSize) {
      // X축 방향에 라벨 표시
      Point3D labelPoint = Point3D(
        x: distance, y: 0, z: 0,
        distance: distance, channel: 0, intensity: 0, pointIndex: 0, verticalAngle: 0,
      );
      
      Point3D rotated = rotatePoint(labelPoint, rotationX, rotationY);
      rotated = Point3D(
        x: rotated.x, y: rotated.y, z: rotated.z + 150,
        distance: rotated.distance, channel: rotated.channel,
        intensity: rotated.intensity, pointIndex: rotated.pointIndex,
        verticalAngle: rotated.verticalAngle,
      );
      
      if (rotated.z <= 10.0) continue;
      
      double scale = zoom * 500 / rotated.z;
      double screenX = centerX + rotated.x * scale;
      double screenY = centerY - rotated.y * scale;
      
      // 라벨 텍스트 개선
      String label = distance < 1.0 
          ? '${(distance * 1000).toInt()}cm' 
          : '${distance.toInt()}m';
      ctx.fillText(label, screenX, screenY + 15);
    }
  }

  void drawDebugInfo() {
    // 디버그 정보 표시 기능 비활성화
    // 필요시 다시 활성화할 수 있도록 함수는 유지
  }

  @override
  void didUpdateWidget(Simple3DViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channels != widget.channels ||
        oldWidget.colorMode != widget.colorMode ||
        oldWidget.pointSize != widget.pointSize) {
      render();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
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
                const Text('3D View (마우스 드래그: 회전, 휠: 줌)', 
                           style: TextStyle(color: Colors.white, fontSize: 12)),
                const Spacer(),
              ],
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
              child: HtmlElementView(viewType: viewId),
            ),
          ),
        ],
      ),
    );
  }
}