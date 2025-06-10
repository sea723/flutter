// lidar.dart 전체 수정

import 'dart:math' as math;

class Point3D {
  final double x;
  final double y;
  final double z;
  final double distance;
  final int channel;
  final int pointIndex;
  final double verticalAngle;

  Point3D({
    required this.x,
    required this.y,
    required this.z,
    required this.distance,
    required this.channel,
    required this.pointIndex,
    required this.verticalAngle,
  });
}

class Lidar {
  final int channel;
  final double hfov;
  final double vfov;  // 🔧 단일값으로 변경 (채널별 고정값)
  final List<double> distances;
  final List<double> azimuth;
  final List<int> pointIndex;
  final double maxRange;

  Lidar({
    required this.channel,
    required this.hfov,
    required this.vfov,
    required this.distances,
    required this.azimuth,
    required this.pointIndex,
    required this.maxRange,
  });

  factory Lidar.fromJson(Map<String, dynamic> json) {
    return Lidar.fromJsonQuiet(json, verbose: true);
  }

  factory Lidar.fromJsonQuiet(Map<String, dynamic> json, {bool verbose = false}) {
    if (verbose) {
      print('=== Lidar.fromJson 시작 ===');
      print('Input JSON keys: ${json.keys.toList()}');
    }
    
    try {
      // 기본 데이터 파싱
      List<double> distances = List<double>.from(json['distances']?.map((x) => x.toDouble()) ?? []);
      double hfov = (json['hfov'] ?? 360.0).toDouble();
      int channel = json['channel'] ?? 0;
      double hresolution = (json['hresolution'] ?? 0.25).toDouble();
      
      // 🔧 vfov: 채널별 고정값 (단일 숫자)
      double vfov = 0.0;
      if (json['vfov'] is num) {
        vfov = (json['vfov'] as num).toDouble();
      } else if (json['vfov'] is List) {
        // 기존 호환성을 위해 배열도 지원
        List<double> vfovList = List<double>.from(json['vfov']?.map((x) => x.toDouble()) ?? []);
        vfov = (channel < vfovList.length) ? vfovList[channel] : 0.0;
      }
      
      if (verbose) {
        print('- 거리 데이터: ${distances.length}개');
        print('- HFOV: $hfov도, 해상도: $hresolution도');
        print('- 채널 $channel vfov: $vfov도 (고정값)');
      }
      
      // azimuth 계산
      List<double> azimuth = [];
      List<int> pointIndex = [];
      
      int totalPoints = distances.length;
      for (int i = 0; i < totalPoints; i++) {
        // 방위각: -HFOV/2부터 시작해서 hresolution씩 증가
        double currentAzimuth = -hfov/2 + (i * hresolution);
        azimuth.add(currentAzimuth);
        pointIndex.add(i);
      }
      
      if (verbose) {
        print('- 계산된 azimuth: ${azimuth.first.toStringAsFixed(1)}° ~ ${azimuth.last.toStringAsFixed(1)}°');
        print('- vfov: ${vfov}° (모든 포인트 동일)');
      }
      
      final lidar = Lidar(
        channel: channel,
        hfov: hfov,
        vfov: vfov,  // 단일값
        distances: distances,
        azimuth: azimuth,
        pointIndex: pointIndex,
        maxRange: (json['max'] ?? json['max_range'] ?? 100.0).toDouble(),
      );
      
      if (verbose) {
        print('✅ Lidar 객체 생성 완료');
        print('=== Lidar.fromJson 완료 ===');
      }
      
      return lidar;
      
    } catch (e, stackTrace) {
      print('❌ Lidar.fromJsonQuiet 에러:');
      print('  에러: $e');
      print('  JSON: $json');
      if (verbose) print('  스택: $stackTrace');
      rethrow;
    }
  }

  List<Point3D> to3DPoints() {
    List<Point3D> points = [];
    
    for (int i = 0; i < distances.length; i++) {
      // 🔧 azimuth 길이만 체크 (vfov는 단일값이므로 체크 불필요)
      if (i >= azimuth.length) continue;
      
      double distance = distances[i];
      double azimuthRad = azimuth[i] * (math.pi / 180);
      double verticalAngleRad = vfov * (math.pi / 180);  // 🔧 모든 포인트가 동일한 vfov 사용
      int pointIdx = i < pointIndex.length ? pointIndex[i] : i;
      
      // 구면 좌표계를 직교 좌표계로 변환
      double x = distance * math.cos(verticalAngleRad) * math.cos(azimuthRad);
      double y = distance * math.cos(verticalAngleRad) * math.sin(azimuthRad);
      double z = distance * math.sin(verticalAngleRad);
      
      points.add(Point3D(
        x: x,
        y: y,
        z: z,
        distance: distance,
        channel: channel,
        pointIndex: pointIdx,
        verticalAngle: vfov,  // 🔧 채널의 고정 vfov 사용
      ));
    }
    
    return points;
  }
}