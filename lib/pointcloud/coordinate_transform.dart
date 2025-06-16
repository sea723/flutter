// coordinate_transform.dart - 3D/2D 좌표 변환 로직
import 'dart:math' as math;
import '../lidar.dart';

class CoordinateTransform {
  
  /// 3D 포인트를 회전 변환하는 함수
  static Point3D rotatePoint(Point3D point, double rotX, double rotY, double rotZ) {
    double x = point.x;
    double y = point.y; 
    double z = point.z;
    
    if (rotZ != 0) {
      double cosZ = math.cos(rotZ);
      double sinZ = math.sin(rotZ);
      double x1 = x * cosZ - y * sinZ;
      double y1 = x * sinZ + y * cosZ;
      x = x1;
      y = y1;
    }
    
    if (rotY != 0) {
      double cosY = math.cos(rotY);
      double sinY = math.sin(rotY);
      double x2 = x * cosY + z * sinY;
      double z2 = -x * sinY + z * cosY;
      x = x2;
      z = z2;
    }
    
    if (rotX != 0) {
      double cosX = math.cos(rotX);
      double sinX = math.sin(rotX);
      double y3 = y * cosX - z * sinX;
      double z3 = y * sinX + z * cosX;
      y = y3;
      z = z3;
    }
    
    return Point3D(
      x: x, y: y, z: z,
      distance: point.distance, channel: point.channel,
      pointIndex: point.pointIndex, verticalAngle: point.verticalAngle,
    );
  }

  /// 마우스 좌표를 3D 월드 좌표로 변환 (실용적 근사 방법)
  static Point3D? getWorldCoordinateFromMouse(
    double mouseX, 
    double mouseY,
    int canvasWidth,
    int canvasHeight,
    double panX,
    double panY,
    double zoom,
    double rotationX,
    double rotationY,
    double rotationZ,
  ) {
    try {
      print('🔍 좌표 변환 시작: mouseX=$mouseX, mouseY=$mouseY');
      
      double centerX = canvasWidth / 2 + panX;
      double centerY = canvasHeight / 2 + panY;
      double relativeX = mouseX - centerX;
      double relativeY = mouseY - centerY;
      
      // 🔧 간단한 역변환 시도
      double zOffset = 150.0;
      double scale = zoom * 500 / zOffset;
      
      // 여러 회전 보정 시도
      List<Map<String, dynamic>> tests = [
        {'name': '기본', 'rotY': 0.0, 'rotZ': 0.0},
        {'name': 'Y180도보정', 'rotY': -math.pi, 'rotZ': 0.0},
        {'name': 'Z90도보정', 'rotY': 0.0, 'rotZ': -math.pi/2},
      ];
      
      Point3D? bestResult;
      double bestError = double.infinity;
      
      for (var test in tests) {
        double worldX = relativeX / scale;
        double worldY = -relativeY / scale;
        
        Point3D rotatedPoint = Point3D(
          x: worldX, y: worldY, z: 0,
          distance: 0, channel: 0, pointIndex: 0, verticalAngle: 0
        );
        
        Point3D worldPoint = inverseRotatePoint(
          rotatedPoint, 
          rotationX, 
          rotationY + test['rotY'], 
          rotationZ + test['rotZ']
        );
        
        // 검증
        Map<String, double>? verification = projectToScreen(
          worldPoint, centerX, centerY, zoom, rotationX, rotationY, rotationZ, zOffset: 150
        );
        
        if (verification != null) {
          double error = math.sqrt(
            math.pow(verification['x']! - mouseX, 2) + 
            math.pow(verification['y']! - mouseY, 2)
          );
          
          print('${test['name']}: (${worldPoint.x.toStringAsFixed(1)}, ${worldPoint.y.toStringAsFixed(1)}) 오차=${error.toStringAsFixed(1)}px');
          
          if (error < bestError) {
            bestError = error;
            bestResult = Point3D(
              x: worldPoint.x, y: worldPoint.y, z: 0,
              distance: math.sqrt(worldPoint.x * worldPoint.x + worldPoint.y * worldPoint.y),
              channel: 0, pointIndex: 0, verticalAngle: 0
            );
          }
        }
      }
      
      if (bestResult != null) {
        print('✅ 최종 결과: (${bestResult.x.toStringAsFixed(2)}, ${bestResult.y.toStringAsFixed(2)}) 오차=${bestError.toStringAsFixed(1)}px');
        return bestResult;
      }
      
      return null;
    } catch (e) {
      print('❌ 좌표 변환 오류: $e');
      return null;
    }
  }

  /// 🎯 직접 역변환 시도 (수학적 접근)
  static Point3D? _tryDirectInverseTransform(
    double screenX, double screenY, 
    double zoom, double rotX, double rotY, double rotZ
  ) {
    try {
      print('🧮 직접 역변환 시도...');
      
      // Z=0 평면이라고 가정하고 역변환
      double zOffset = 150.0; // 그리드 Z 오프셋
      double scale = zoom * 500 / zOffset;
      
      print('📊 투영 스케일: $scale');
      
      // 화면 좌표 → 회전된 3D 좌표
      double rotatedX = screenX / scale;
      double rotatedY = -screenY / scale; // Y축 뒤집기
      double rotatedZ = 0.0; // Z=0 평면 가정
      
      print('📊 역투영된 회전 좌표: ($rotatedX, $rotatedY, $rotatedZ)');
      
      // 회전 역변환 적용
      Point3D rotatedPoint = Point3D(
        x: rotatedX, y: rotatedY, z: rotatedZ,
        distance: 0, channel: 0, pointIndex: 0, verticalAngle: 0
      );
      
      Point3D worldPoint = inverseRotatePoint(rotatedPoint, rotX, rotY, rotZ);
      
      print('📊 월드 좌표: (${worldPoint.x.toStringAsFixed(2)}, ${worldPoint.y.toStringAsFixed(2)}, ${worldPoint.z.toStringAsFixed(2)})');
      
      // 검증: 다시 투영해보기
      Map<String, double>? verification = projectToScreen(
        worldPoint, 0, 0, zoom, rotX, rotY, rotZ, zOffset: 150
      );
      
      if (verification != null) {
        double errorX = verification['x']! - screenX;
        double errorY = verification['y']! - screenY;
        double error = math.sqrt(errorX * errorX + errorY * errorY);
        
        print('🔍 검증 오차: ${error.toStringAsFixed(2)}px');
        
        if (error < 5.0) { // 5픽셀 이내 오차면 성공
          return Point3D(
            x: worldPoint.x, y: worldPoint.y, z: 0,
            distance: math.sqrt(worldPoint.x * worldPoint.x + worldPoint.y * worldPoint.y),
            channel: 0, pointIndex: 0, verticalAngle: 0
          );
        }
      }
      
      return null;
    } catch (e) {
      print('❌ 직접 역변환 실패: $e');
      return null;
    }
  }

  /// 🎯 레이캐스팅 방법
  static Point3D? _tryRaycastMethod(
    double screenX, double screenY,
    double zoom, double rotX, double rotY, double rotZ
  ) {
    try {
      print('🚀 레이캐스팅 시도...');
      
      // Z=0 평면과의 교차점을 찾는 방법
      // 카메라에서 마우스 방향으로 레이를 쏴서 Z=0 평면과의 교차점 찾기
      
      double zOffset = 150.0;
      double scale = zoom * 500 / zOffset;
      
      // 레이 방향 계산 (정규화된 방향)
      double rayDirX = screenX / scale;
      double rayDirY = -screenY / scale;
      double rayDirZ = -zOffset; // 카메라에서 Z=0 평면 방향
      
      // 레이와 Z=0 평면의 교차점 계산
      // t = -rayOriginZ / rayDirZ (Z=0이 되는 t 값)
      double t = zOffset / zOffset; // = 1
      
      double intersectionX = rayDirX * t;
      double intersectionY = rayDirY * t;
      double intersectionZ = 0.0;
      
      print('📊 교차점 (회전된 좌표): ($intersectionX, $intersectionY, $intersectionZ)');
      
      // 회전 역변환
      Point3D intersectionPoint = Point3D(
        x: intersectionX, y: intersectionY, z: intersectionZ,
        distance: 0, channel: 0, pointIndex: 0, verticalAngle: 0
      );
      
      Point3D worldPoint = inverseRotatePoint(intersectionPoint, rotX, rotY, rotZ);
      
      return Point3D(
        x: worldPoint.x, y: worldPoint.y, z: 0,
        distance: math.sqrt(worldPoint.x * worldPoint.x + worldPoint.y * worldPoint.y),
        channel: 0, pointIndex: 0, verticalAngle: 0
      );
      
    } catch (e) {
      print('❌ 레이캐스팅 실패: $e');
      return null;
    }
  }

  /// 📦 백업용 그리드 검색 (기존 방법 개선)
  static Point3D? _fallbackGridSearch(
    double mouseX, double mouseY,
    int canvasWidth, int canvasHeight,
    double panX, double panY, double zoom,
    double rotX, double rotY, double rotZ
  ) {
    print('🔄 백업 그리드 검색...');
    
    double centerX = canvasWidth / 2 + panX;
    double centerY = canvasHeight / 2 + panY;
    
    double bestDistance = double.infinity;
    Point3D? bestPoint;
    
    // 더 정밀한 검색 (0.1 단위)
    for (double x = -25.0; x <= 25.0; x += 0.5) {
      for (double y = -25.0; y <= 25.0; y += 0.5) {
        Point3D candidate = Point3D(
          x: x, y: y, z: 0,
          distance: math.sqrt(x * x + y * y),
          channel: 0, pointIndex: 0, verticalAngle: 0
        );
        
        Map<String, double>? projection = projectToScreen(
          candidate, centerX, centerY, zoom, rotX, rotY, rotZ, zOffset: 150
        );
        
        if (projection != null) {
          double distance = math.sqrt(
            math.pow(projection['x']! - mouseX, 2) + 
            math.pow(projection['y']! - mouseY, 2)
          );
          
          if (distance < bestDistance) {
            bestDistance = distance;
            bestPoint = candidate;
          }
        }
      }
    }
    
    if (bestPoint != null) {
      print('📍 그리드 검색 결과: (${bestPoint.x.toStringAsFixed(1)}, ${bestPoint.y.toStringAsFixed(1)}) 오차: ${bestDistance.toStringAsFixed(1)}px');
    }
    
    return bestPoint;
  }

  /// 🔧 개선된 역회전 함수 (정확한 순서)
  static Point3D inverseRotatePoint(Point3D point, double rotX, double rotY, double rotZ) {
    double x = point.x;
    double y = point.y;
    double z = point.z;
    
    print('🔄 역회전 시작: ($x, $y, $z)');
    
    // 정방향이 Z -> Y -> X 순서였으므로, 역방향은 X -> Y -> Z 순서
    
    // X축 회전 역변환
    if (rotX != 0) {
      double cosX = math.cos(-rotX);
      double sinX = math.sin(-rotX);
      double y1 = y * cosX - z * sinX;
      double z1 = y * sinX + z * cosX;
      y = y1;
      z = z1;
      print('🔄 X축 역회전 후: ($x, $y, $z)');
    }
    
    // Y축 회전 역변환
    if (rotY != 0) {
      double cosY = math.cos(-rotY);
      double sinY = math.sin(-rotY);
      double x2 = x * cosY + z * sinY;
      double z2 = -x * sinY + z * cosY;
      x = x2;
      z = z2;
      print('🔄 Y축 역회전 후: ($x, $y, $z)');
    }
    
    // Z축 회전 역변환
    if (rotZ != 0) {
      double cosZ = math.cos(-rotZ);
      double sinZ = math.sin(-rotZ);
      double x3 = x * cosZ - y * sinZ;
      double y3 = x * sinZ + y * cosZ;
      x = x3;
      y = y3;
      print('🔄 Z축 역회전 후: ($x, $y, $z)');
    }
    
    return Point3D(
      x: x, y: y, z: z,
      distance: point.distance, channel: point.channel,
      pointIndex: point.pointIndex, verticalAngle: point.verticalAngle,
    );
  }

  /// 3D 포인트를 화면 좌표로 투영
  static Map<String, double>? projectToScreen(
    Point3D point,
    double centerX,
    double centerY,
    double zoom,
    double rotationX,
    double rotationY,
    double rotationZ,
    {double zOffset = 200}
  ) {
    // 회전 적용
    Point3D rotated = rotatePoint(point, rotationX, rotationY, rotationZ);
    
    // Z 오프셋 적용
    rotated = Point3D(
      x: rotated.x, y: rotated.y, z: rotated.z + zOffset,
      distance: rotated.distance, channel: rotated.channel,
      pointIndex: rotated.pointIndex, verticalAngle: rotated.verticalAngle,
    );
    
    // Z가 너무 가까우면 null 반환
    if (rotated.z <= 50.0) return null;
    
    // 원근 투영
    double scale = zoom * 500 / rotated.z;
    double screenX = centerX + rotated.x * scale;
    double screenY = centerY - rotated.y * scale;
    
    return {
      'x': screenX,
      'y': screenY,
      'z': rotated.z,
      'scale': scale,
    };
  }

  /// 화면 경계 계산 (컬링용)
  static Map<String, double> getScreenBounds(
    int canvasWidth,
    int canvasHeight,
    double panX,
    double panY,
    double zoom,
    {double margin = 100.0}
  ) {
    // 화면 픽셀 좌표
    double screenLeft = -margin;
    double screenRight = canvasWidth + margin;
    double screenTop = -margin;
    double screenBottom = canvasHeight + margin;
    
    // 화면 중심 기준으로 조정
    double centerX = canvasWidth / 2 + panX;
    double centerY = canvasHeight / 2 + panY;
    
    // 화면 좌표를 3D 공간 좌표로 변환 (대략적)
    double worldLeft = (screenLeft - centerX) / zoom;
    double worldRight = (screenRight - centerX) / zoom;
    double worldTop = (screenTop - centerY) / zoom;
    double worldBottom = (screenBottom - centerY) / zoom;
    
    return {
      'left': worldLeft,
      'right': worldRight,
      'top': worldTop,
      'bottom': worldBottom,
      'centerX': centerX,
      'centerY': centerY,
    };
  }

  /// 특정 좌표계 설정으로 변환 시도
  static Point3D? _testCoordinateSystem(
    double relativeX, double relativeY, double zoom,
    double rotX, double rotY, double rotZ
  ) {
    try {
      double zOffset = 150.0;
      double scale = zoom * 500 / zOffset;
      
      // 기본 역투영
      double worldX = relativeX / scale;
      double worldY = -relativeY / scale; // Y축 뒤집기
      
      // 회전 역변환
      Point3D rotatedPoint = Point3D(
        x: worldX, y: worldY, z: 0,
        distance: 0, channel: 0, pointIndex: 0, verticalAngle: 0
      );
      
      Point3D worldPoint = inverseRotatePoint(rotatedPoint, rotX, rotY, rotZ);
      
      return Point3D(
        x: worldPoint.x, y: worldPoint.y, z: 0,
        distance: math.sqrt(worldPoint.x * worldPoint.x + worldPoint.y * worldPoint.y),
        channel: 0, pointIndex: 0, verticalAngle: 0
      );
    } catch (e) {
      return null;
    }
  }
}

