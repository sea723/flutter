// grid_renderer.dart - 그리드 렌더링 및 컬링 로직
import 'dart:html' as html;
import 'dart:math' as math;
import 'coordinate_transform.dart';
import '../lidar.dart';

class GridRenderer {  
  /// 그리드 스타일 설정
  static void setGridStyle(html.CanvasRenderingContext2D ctx, String type) {
    switch (type) {
      case 'square':
        ctx.strokeStyle = '#444444';
        ctx.lineWidth = 0.5;
        ctx.setLineDash([4, 2]);
        break;
      case 'circle':
        ctx.strokeStyle = '#666666';
        ctx.lineWidth = 0.6;
        ctx.setLineDash([3, 3]);
        break;
      case 'radial':
        ctx.strokeStyle = '#888888';
        ctx.lineWidth = 0.7;
        ctx.setLineDash([]);
        break;
      default:
        ctx.strokeStyle = '#555555';
        ctx.lineWidth = 0.6;
        ctx.setLineDash([3, 3]);
    }
  }

  /// 라인 가시성 체크 (컬링용)
  static bool isLineVisible(
    Point3D start, 
    Point3D end, 
    Map<String, double> screenBounds,
    double rotationX,
    double rotationY,
    double rotationZ,
    double zoom,
    int canvasWidth,
    int canvasHeight,
  ) {
    // 3D 회전 적용
    Point3D rotatedStart = CoordinateTransform.rotatePoint(start, rotationX, rotationY, rotationZ);
    Point3D rotatedEnd = CoordinateTransform.rotatePoint(end, rotationX, rotationY, rotationZ);
    
    // Z 오프셋 적용 (그리드용)
    rotatedStart = Point3D(
      x: rotatedStart.x, y: rotatedStart.y, z: rotatedStart.z + 150,
      distance: rotatedStart.distance, channel: rotatedStart.channel,
      pointIndex: rotatedStart.pointIndex, verticalAngle: rotatedStart.verticalAngle,
    );
    
    rotatedEnd = Point3D(
      x: rotatedEnd.x, y: rotatedEnd.y, z: rotatedEnd.z + 150,
      distance: rotatedEnd.distance, channel: rotatedEnd.channel,
      pointIndex: rotatedEnd.pointIndex, verticalAngle: rotatedEnd.verticalAngle,
    );
    
    // Z 좌표가 너무 가까우면 렌더링하지 않음
    if (rotatedStart.z <= 10.0 || rotatedEnd.z <= 10.0) return false;
    
    // 화면 투영
    double startScale = zoom * 500 / rotatedStart.z;
    double endScale = zoom * 500 / rotatedEnd.z;
    
    double startX = screenBounds['centerX']! + rotatedStart.x * startScale;
    double startY = screenBounds['centerY']! - rotatedStart.y * startScale;
    double endX = screenBounds['centerX']! + rotatedEnd.x * endScale;
    double endY = screenBounds['centerY']! - rotatedEnd.y * endScale;
    
    // 라인 경계 상자 계산
    double minX = math.min(startX, endX);
    double maxX = math.max(startX, endX);
    double minY = math.min(startY, endY);
    double maxY = math.max(startY, endY);
    
    // 더 엄격한 컬링 조건
    double margin = 10.0;
    return !(maxX < -margin || 
             minX > canvasWidth + margin ||
             maxY < -margin || 
             minY > canvasHeight + margin);
  }

  /// 원형 그리드 가시성 체크
  static bool isCircleVisible(
    double radius, 
    Map<String, double> screenBounds,
    double zoom,
    double panX,
    double panY,
    int canvasWidth,
    int canvasHeight,
  ) {
    double projectedRadius = radius * zoom * 500 / 150;
    if (projectedRadius < 0.5) return false;
    
    double screenDiagonal = math.sqrt(canvasWidth * canvasWidth + canvasHeight * canvasHeight);
    if (projectedRadius > screenDiagonal * 3) return false;
    
    return true;
  }

  /// 바둑판 그리드 그리기
  static void drawSquareGrid(
    html.CanvasRenderingContext2D ctx,
    double centerX,
    double centerY,
    double maxRange,
    double gridStep,
    double zoom,
    double rotationX,
    double rotationY,
    double rotationZ,
    int canvasWidth,
    int canvasHeight,
    double panX,
    double panY,
  ) {
    setGridStyle(ctx, 'square');
    
    // 화면 경계 계산
    Map<String, double> screenBounds = CoordinateTransform.getScreenBounds(
      canvasWidth, canvasHeight, panX, panY, zoom
    );
    
    int drawnLines = 0;
    int culledLines = 0;
    
    // 적응형 그리드 스텝
    double adaptiveGridStep = gridStep;
    if (zoom > 5.0) {
      adaptiveGridStep = gridStep * 2.0;
    } else if (zoom > 10.0) {
      adaptiveGridStep = gridStep * 4.0;
    }
    
    // X축 평행선들
    for (double x = -maxRange; x <= maxRange; x += adaptiveGridStep) {
      if (x.abs() < 0.01) continue;
      
      Point3D startPoint = Point3D(x: x, y: -maxRange, z: 0, distance: 0, channel: 0, pointIndex: 0, verticalAngle: 0);
      Point3D endPoint = Point3D(x: x, y: maxRange, z: 0, distance: 0, channel: 0, pointIndex: 0, verticalAngle: 0);
      
      if (isLineVisible(startPoint, endPoint, screenBounds, rotationX, rotationY, rotationZ, zoom, canvasWidth, canvasHeight)) {
        _drawGridLine(ctx, centerX, centerY, startPoint, endPoint, rotationX, rotationY, rotationZ, zoom);
        drawnLines++;
      } else {
        culledLines++;
      }
    }
    
    // Y축 평행선들
    for (double y = -maxRange; y <= maxRange; y += adaptiveGridStep) {
      if (y.abs() < 0.01) continue;
      
      Point3D startPoint = Point3D(x: -maxRange, y: y, z: 0, distance: 0, channel: 0, pointIndex: 0, verticalAngle: 0);
      Point3D endPoint = Point3D(x: maxRange, y: y, z: 0, distance: 0, channel: 0, pointIndex: 0, verticalAngle: 0);
      
      if (isLineVisible(startPoint, endPoint, screenBounds, rotationX, rotationY, rotationZ, zoom, canvasWidth, canvasHeight)) {
        _drawGridLine(ctx, centerX, centerY, startPoint, endPoint, rotationX, rotationY, rotationZ, zoom);
        drawnLines++;
      } else {
        culledLines++;
      }
    }
    
    // 디버깅 정보 (가끔씩만)
    if (DateTime.now().millisecondsSinceEpoch % 3000 < 100) {
      print('Square Grid - Drawn: $drawnLines, Culled: $culledLines (Step: ${adaptiveGridStep.toStringAsFixed(1)})');
    }
    
    ctx.setLineDash([]);
  }

  /// 원형 그리드 그리기
  static void drawCircularGrid(
    html.CanvasRenderingContext2D ctx,
    double centerX,
    double centerY,
    double maxRange,
    double gridStep,
    double zoom,
    double rotationX,
    double rotationY,
    double rotationZ,
    int canvasWidth,
    int canvasHeight,
    double panX,
    double panY,
  ) {
    setGridStyle(ctx, 'circle');
    
    Map<String, double> screenBounds = CoordinateTransform.getScreenBounds(
      canvasWidth, canvasHeight, panX, panY, zoom
    );
    
    int drawnCircles = 0;
    int culledCircles = 0;
    
    for (double distance = gridStep; distance <= maxRange; distance += gridStep) {
      if (isCircleVisible(distance, screenBounds, zoom, panX, panY, canvasWidth, canvasHeight)) {
        _drawDistanceCircle(ctx, centerX, centerY, distance, rotationX, rotationY, rotationZ, zoom);
        drawnCircles++;
      } else {
        culledCircles++;
      }
    }
    
    if (DateTime.now().millisecondsSinceEpoch % 3000 < 100) {
      print('Circular Grid - Drawn: $drawnCircles, Culled: $culledCircles');
    }
    
    ctx.setLineDash([]);
  }

  /// 방사형 그리드 그리기
  static void drawRadialGrid(
    html.CanvasRenderingContext2D ctx,
    double centerX,
    double centerY,
    double maxRange,
    double hfov,
    double zoom,
    double rotationX,
    double rotationY,
    double rotationZ,
    int canvasWidth,
    int canvasHeight,
    double panX,
    double panY,
  ) {
    setGridStyle(ctx, 'radial');
    
    Map<String, double> screenBounds = CoordinateTransform.getScreenBounds(
      canvasWidth, canvasHeight, panX, panY, zoom
    );
    
    List<double> angles = [0.0, 90.0, 180.0, 270.0];
    angles.add(hfov/2);
    angles.add(-hfov/2);
    
    int drawnRadials = 0;
    int culledRadials = 0;
    
    for (double angleDegree in angles) {
      double angle = angleDegree * (math.pi / 180);
      
      Point3D startPoint = Point3D(x: 0, y: 0, z: 0, distance: 0, channel: 0, pointIndex: 0, verticalAngle: 0);
      Point3D endPoint = Point3D(
        x: maxRange * math.sin(angle), y: maxRange * math.cos(angle), z: 0,
        distance: maxRange, channel: 0, pointIndex: 0, verticalAngle: 0,
      );
      
      if (isLineVisible(startPoint, endPoint, screenBounds, rotationX, rotationY, rotationZ, zoom, canvasWidth, canvasHeight)) {
        _drawRadialLine(ctx, centerX, centerY, angle, maxRange, rotationX, rotationY, rotationZ, zoom);
        drawnRadials++;
      } else {
        culledRadials++;
      }
    }
    
    if (DateTime.now().millisecondsSinceEpoch % 3000 < 100) {
      print('Radial Grid - Drawn: $drawnRadials, Culled: $culledRadials');
    }
  }

  /// 거리 라벨 그리기
  static void drawDistanceLabels(
    html.CanvasRenderingContext2D ctx,
    double centerX,
    double centerY,
    double labelStep,
    double maxRange,
    double rotationX,
    double rotationY,
    double rotationZ,
    double zoom,
  ) {
    ctx.fillStyle = '#888888';
    ctx.font = '10px Arial';
    ctx.textAlign = 'center';
    
    for (double distance = labelStep; distance <= maxRange; distance += labelStep) {
      Point3D labelPoint = Point3D(x: 0, y: distance, z: 0, distance: distance, channel: 0, pointIndex: 0, verticalAngle: 0);
      
      Point3D rotated = CoordinateTransform.rotatePoint(labelPoint, rotationX, rotationY, rotationZ);
      rotated = Point3D(x: rotated.x, y: rotated.y, z: rotated.z + 150, distance: rotated.distance, channel: rotated.channel, pointIndex: rotated.pointIndex, verticalAngle: rotated.verticalAngle);
      
      if (rotated.z <= 10.0) continue;
      
      double scale = zoom * 500 / rotated.z;
      double screenX = centerX + rotated.x * scale;
      double screenY = centerY - rotated.y * scale;
      
      if(labelStep < 1.0) {
        ctx.fillText('${distance.toStringAsFixed(1)}m', screenX, screenY - 5);
      } else {
        ctx.fillText('${distance.toStringAsFixed(0)}m', screenX, screenY - 5);
      }
    }
  }

  // === 내부 헬퍼 함수들 ===

  /// 그리드 라인 그리기 헬퍼
  static void _drawGridLine(
    html.CanvasRenderingContext2D ctx,
    double centerX,
    double centerY,
    Point3D start,
    Point3D end,
    double rotationX,
    double rotationY,
    double rotationZ,
    double zoom,
  ) {
    Point3D rotatedStart = CoordinateTransform.rotatePoint(start, rotationX, rotationY, rotationZ);
    Point3D rotatedEnd = CoordinateTransform.rotatePoint(end, rotationX, rotationY, rotationZ);
    
    // Z 오프셋 적용
    rotatedStart = Point3D(
      x: rotatedStart.x, y: rotatedStart.y, z: rotatedStart.z + 150,
      distance: rotatedStart.distance, channel: rotatedStart.channel,
      pointIndex: rotatedStart.pointIndex, verticalAngle: rotatedStart.verticalAngle,
    );
    
    rotatedEnd = Point3D(
      x: rotatedEnd.x, y: rotatedEnd.y, z: rotatedEnd.z + 150,
      distance: rotatedEnd.distance, channel: rotatedEnd.channel,
      pointIndex: rotatedEnd.pointIndex, verticalAngle: rotatedEnd.verticalAngle,
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

  /// 거리 원형 그리기 헬퍼
  static void _drawDistanceCircle(
    html.CanvasRenderingContext2D ctx,
    double centerX,
    double centerY,
    double distance,
    double rotationX,
    double rotationY,
    double rotationZ,
    double zoom,
  ) {
    List<Point3D> circlePoints = [];
    
    for (int i = 0; i <= 36; i++) {
      double angle = (i * 10.0) * (math.pi / 180);
      Point3D point = Point3D(
        x: distance * math.sin(angle), y: distance * math.cos(angle), z: 0,
        distance: distance, channel: 0, pointIndex: i, verticalAngle: 0,
      );
      circlePoints.add(point);
    }
    
    ctx.beginPath();
    bool firstPoint = true;
    
    for (var point in circlePoints) {
      Point3D rotated = CoordinateTransform.rotatePoint(point, rotationX, rotationY, rotationZ);
      rotated = Point3D(
        x: rotated.x, y: rotated.y, z: rotated.z + 150,
        distance: rotated.distance, channel: rotated.channel,
        pointIndex: rotated.pointIndex, verticalAngle: rotated.verticalAngle,
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

  /// 방사형 라인 그리기 헬퍼
  static void _drawRadialLine(
    html.CanvasRenderingContext2D ctx,
    double centerX,
    double centerY,
    double angle,
    double maxDistance,
    double rotationX,
    double rotationY,
    double rotationZ,
    double zoom,
  ) {
    Point3D startPoint = Point3D(x: 0, y: 0, z: 0, distance: 0, channel: 0, pointIndex: 0, verticalAngle: 0);
    Point3D endPoint = Point3D(
      x: maxDistance * math.sin(angle), y: maxDistance * math.cos(angle), z: 0,
      distance: maxDistance, channel: 0, pointIndex: 0, verticalAngle: 0,
    );
    
    Point3D rotatedStart = CoordinateTransform.rotatePoint(startPoint, rotationX, rotationY, rotationZ);
    Point3D rotatedEnd = CoordinateTransform.rotatePoint(endPoint, rotationX, rotationY, rotationZ);
    
    rotatedStart = Point3D(
      x: rotatedStart.x, y: rotatedStart.y, z: rotatedStart.z + 150,
      distance: rotatedStart.distance, channel: rotatedStart.channel,
      pointIndex: rotatedStart.pointIndex, verticalAngle: rotatedStart.verticalAngle,
    );
    
    rotatedEnd = Point3D(
      x: rotatedEnd.x, y: rotatedEnd.y, z: rotatedEnd.z + 150,
      distance: rotatedEnd.distance, channel: rotatedEnd.channel,
      pointIndex: rotatedEnd.pointIndex, verticalAngle: rotatedEnd.verticalAngle,
    );
    
    if (rotatedStart.z <= 10.0 || rotatedEnd.z <= 10.0) return;
    
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
}