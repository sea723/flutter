// color_utils.dart - 통합 색상 계산 유틸리티
import 'dart:math' as math;
import '../lidar.dart';

class ColorUtils {
  // 색상 모드 상수
  static const String COLOR_DISTANCE = 'distance';
  static const String COLOR_CHANNEL = 'channel';

  /// 🎨 통일된 포인트 색상 계산 (RGB 0.0~1.0 범위)
  static List<double> getPointColor(
    Point3D point, 
    double minDistance, 
    double maxDistance, 
    String colorMode
  ) {
    switch (colorMode) {
      case COLOR_DISTANCE:
        return _getDistanceColor(point, minDistance, maxDistance);
        
      case COLOR_CHANNEL:
        return _getChannelColor(point);
        
      default:
        return [1.0, 1.0, 1.0]; // 기본 흰색
    }
  }

  /// 거리 기반 색상 (빨강 → 보라)
  static List<double> _getDistanceColor(Point3D point, double minDistance, double maxDistance) {
    double normalized = maxDistance > minDistance 
        ? (point.distance - minDistance) / (maxDistance - minDistance)
        : 0.0;
    
    // 빨강(1,0,0) → 보라(1,0,1)
    return [1.0, 0.0, normalized];
  }

  /// 채널 기반 색상 (무지개 7색)
  static List<double> _getChannelColor(Point3D point) {
    double hue = (point.channel * 51.4) % 360; // 7색 균등 분배 (360/7 ≈ 51.4)
    return hsvToRgb(hue, 1.0, 1.0); // 채도 100%, 밝기 100%
  }

  /// HSV to RGB 변환
  static List<double> hsvToRgb(double h, double s, double v) {
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

  /// RGB를 CSS 색상으로 변환 (Canvas 2D용)
  static String rgbToCssColor(List<double> rgb) {
    int r = (rgb[0] * 255).round().clamp(0, 255);
    int g = (rgb[1] * 255).round().clamp(0, 255);
    int b = (rgb[2] * 255).round().clamp(0, 255);
    return 'rgb($r, $g, $b)';
  }

  /// 🔧 기존 point_renderer.dart용 색상 계산 (호환성)
  static String getPointColorForRenderer(Point3D point, double minDistance, double maxDistance, String colorMode) {
    List<double> rgb = getPointColor(point, minDistance, maxDistance, colorMode);
    return rgbToCssColor(rgb);
  }
}