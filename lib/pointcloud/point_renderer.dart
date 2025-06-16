// point_renderer.dart - 라이다 포인트 렌더링 및 색상 관리
import 'dart:html' as html;
import 'dart:math' as math;
import 'coordinate_transform.dart';
import 'color_utils.dart';
import '../lidar.dart';

class PointRenderer {
  
  /// 포인트 색상 모드 열거형
  static const String COLOR_DISTANCE = 'distance';
  static const String COLOR_CHANNEL = 'channel';
  static const String COLOR_VERTICAL_ANGLE = 'vertical_angle';
  static const String COLOR_INTENSITY = 'intensity';

  /// 모든 포인트 렌더링 (메인 함수)
  static void renderPoints(
    html.CanvasRenderingContext2D ctx,
    List<Point3D> allPoints,
    double centerX,
    double centerY,
    double zoom,
    double rotationX,
    double rotationY,
    double rotationZ,
    int canvasWidth,
    int canvasHeight,
    String colorMode,
    double pointSize,
  ) {
    if (allPoints.isEmpty) return;

    // 거리 범위 계산 (색상 정규화용)
    double minDistance = allPoints.map((p) => p.distance).reduce(math.min);
    double maxDistance = allPoints.map((p) => p.distance).reduce(math.max);
    
    // 배치 렌더링을 위한 색상별 그룹화
    Map<String, List<Point3D>> colorGroups = {};
    int culledPoints = 0;
    int renderedPoints = 0;
    
    for (var point in allPoints) {
      // 3D → 화면 좌표 변환
      Map<String, double>? projection = CoordinateTransform.projectToScreen(
        point, centerX, centerY, zoom, rotationX, rotationY, rotationZ,
        zOffset: 200
      );
      
      if (projection == null) {
        culledPoints++;
        continue;
      }
      
      double screenX = projection['x']!;
      double screenY = projection['y']!;
      
      // 화면 밖 컬링
      if (screenX < -100 || screenX > canvasWidth + 100 || 
          screenY < -100 || screenY > canvasHeight + 100) {
        culledPoints++;
        continue;
      }
      
      // 색상 계산
      String color = getPointColor(point, minDistance, maxDistance, colorMode);
      
      if (!colorGroups.containsKey(color)) {
        colorGroups[color] = [];
      }
      
      // 화면 좌표를 저장
      colorGroups[color]!.add(Point3D(
        x: screenX, y: screenY, z: 0,
        distance: point.distance, channel: point.channel,
        pointIndex: point.pointIndex, verticalAngle: point.verticalAngle,
      ));
      
      renderedPoints++;
    }
    
    // 색상별 배치 렌더링
    _renderPointGroups(ctx, colorGroups, pointSize);
    
    // 성능 디버깅 (가끔씩만)
    if (DateTime.now().millisecondsSinceEpoch % 3000 < 100) {
      print('Points - Rendered: $renderedPoints, Culled: $culledPoints');
    }
  }

  /// 포인트 색상 계산
  static String getPointColor(Point3D point, double minDistance, double maxDistance, String colorMode) {
    return ColorUtils.getPointColorForRenderer(point, minDistance, maxDistance, colorMode);
  }

  /// 색상별 포인트 그룹 렌더링 (배치 처리)
  static void _renderPointGroups(
    html.CanvasRenderingContext2D ctx,
    Map<String, List<Point3D>> colorGroups,
    double pointSize,
  ) {
    double pointRadius = math.max(pointSize * 2.0, 0.1);
    
    colorGroups.forEach((color, points) {
      ctx.fillStyle = color;
      ctx.beginPath();
      
      for (var point in points) {
        ctx.moveTo(point.x + pointRadius, point.y);
        ctx.arc(point.x, point.y, pointRadius, 0, 2 * math.pi);
      }
      
      ctx.fill();
    });
  }

  /// 개별 포인트 렌더링 (디버깅용)
  static void renderSinglePoint(
    html.CanvasRenderingContext2D ctx,
    Point3D point,
    double centerX,
    double centerY,
    double zoom,
    double rotationX,
    double rotationY,
    double rotationZ,
    String color,
    double pointSize,
  ) {
    Map<String, double>? projection = CoordinateTransform.projectToScreen(
      point, centerX, centerY, zoom, rotationX, rotationY, rotationZ
    );
    
    if (projection == null) return;
    
    double screenX = projection['x']!;
    double screenY = projection['y']!;
    double pointRadius = math.max(pointSize * 2.0, 0.1);
    
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.arc(screenX, screenY, pointRadius, 0, 2 * math.pi);
    ctx.fill();
  }

  /// 포인트 하이라이트 (선택된 포인트 강조)
  static void highlightPoint(
    html.CanvasRenderingContext2D ctx,
    Point3D point,
    double centerX,
    double centerY,
    double zoom,
    double rotationX,
    double rotationY,
    double rotationZ,
    {String color = '#ffff00', double size = 8.0}
  ) {
    Map<String, double>? projection = CoordinateTransform.projectToScreen(
      point, centerX, centerY, zoom, rotationX, rotationY, rotationZ
    );
    
    if (projection == null) return;
    
    double screenX = projection['x']!;
    double screenY = projection['y']!;
    
    // 외곽 링
    ctx.strokeStyle = color;
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(screenX, screenY, size, 0, 2 * math.pi);
    ctx.stroke();
    
    // 내부 점
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.arc(screenX, screenY, size / 3, 0, 2 * math.pi);
    ctx.fill();
  }

  /// 포인트 클러스터링 (성능 최적화용)
  static Map<String, List<Point3D>> clusterPoints(
    List<Point3D> points,
    double clusterRadius,
  ) {
    Map<String, List<Point3D>> clusters = {};
    
    for (var point in points) {
      // 클러스터 키 생성 (그리드 기반)
      int gridX = (point.x / clusterRadius).floor();
      int gridY = (point.y / clusterRadius).floor();
      String clusterKey = '${gridX}_${gridY}';
      
      if (!clusters.containsKey(clusterKey)) {
        clusters[clusterKey] = [];
      }
      clusters[clusterKey]!.add(point);
    }
    
    return clusters;
  }

  /// LOD (Level of Detail) 포인트 필터링
  static List<Point3D> applyLOD(List<Point3D> points, double zoom) {
    if (zoom > 5.0) {
      // 확대 시: 모든 포인트 표시
      return points;
    } else if (zoom > 2.0) {
      // 중간 줌: 2개 중 1개씩 표시
      return points.where((point) => point.pointIndex % 2 == 0).toList();
    } else {
      // 축소 시: 4개 중 1개씩 표시
      return points.where((point) => point.pointIndex % 4 == 0).toList();
    }
  }

  /// 포인트 통계 정보 계산
  static Map<String, dynamic> getPointStatistics(List<Point3D> points) {
    if (points.isEmpty) {
      return {
        'count': 0,
        'minDistance': 0.0,
        'maxDistance': 0.0,
        'avgDistance': 0.0,
        'channels': <int>[],
      };
    }

    double minDistance = points.map((p) => p.distance).reduce(math.min);
    double maxDistance = points.map((p) => p.distance).reduce(math.max);
    double avgDistance = points.map((p) => p.distance).reduce((a, b) => a + b) / points.length;
    
    Set<int> uniqueChannels = points.map((p) => p.channel).toSet();
    
    return {
      'count': points.length,
      'minDistance': minDistance,
      'maxDistance': maxDistance,
      'avgDistance': avgDistance,
      'channels': uniqueChannels.toList()..sort(),
    };
  }

  /// 색상 범례 그리기
  static void drawColorLegend(
    html.CanvasRenderingContext2D ctx,
    String colorMode,
    double minValue,
    double maxValue,
    double x,
    double y,
    double width,
    double height,
  ) {
    // 범례 배경
    ctx.fillStyle = 'rgba(0, 0, 0, 0.7)';
    ctx.fillRect(x, y, width, height);
    
    // 색상 그라디언트
    var gradient = ctx.createLinearGradient(x, y, x, y + height);
    
    switch (colorMode) {
      case COLOR_DISTANCE:
        gradient.addColorStop(0, 'rgb(0, 50, 255)');    // 파랑 (먼 거리)
        gradient.addColorStop(1, 'rgb(255, 50, 0)');    // 빨강 (가까운 거리)
        break;
      case COLOR_VERTICAL_ANGLE:
        gradient.addColorStop(0, 'rgb(255, 50, 100)');  // 상단
        gradient.addColorStop(1, 'rgb(50, 255, 100)');  // 하단
        break;
      default:
        gradient.addColorStop(0, 'rgb(255, 255, 255)');
        gradient.addColorStop(1, 'rgb(0, 0, 0)');
    }
    
    ctx.fillStyle = gradient;
    ctx.fillRect(x + 5, y + 20, width - 10, height - 40);
    
    // 텍스트 라벨
    ctx.fillStyle = '#ffffff';
    ctx.font = '10px Arial';
    ctx.fillText(colorMode, x + 5, y + 15);
    ctx.fillText(maxValue.toStringAsFixed(1), x + 5, y + 35);
    ctx.fillText(minValue.toStringAsFixed(1), x + 5, y + height - 5);
  }
}