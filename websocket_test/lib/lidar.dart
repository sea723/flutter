import 'dart:math' as math;

class Point3D {
  final double x;
  final double y;
  final double z;
  final double distance;
  final int channel;
  final double intensity;
  final int pointIndex;
  final double verticalAngle;

  Point3D({
    required this.x,
    required this.y,
    required this.z,
    required this.distance,
    required this.channel,
    required this.intensity,
    required this.pointIndex,
    required this.verticalAngle,
  });
}

class Lidar {
  final int channel;
  final double hfov;
  final List<double> vfov;
  final List<double> distances;
  final List<double> azimuth;
  final List<double> intensities;
  final List<int> pointIndex;
  final List<double> verticalAngle;
  final double maxRange; // 최대 거리 추가

  Lidar({
    required this.channel,
    required this.hfov,
    required this.vfov,
    required this.distances,
    required this.azimuth,
    required this.intensities,
    required this.pointIndex,
    required this.verticalAngle,
    required this.maxRange, // 생성자에 추가
  });

  factory Lidar.fromJson(Map<String, dynamic> json) {
    print('=== Lidar.fromJson 시작 ===');
    // print('Input JSON keys: ${json.keys.toList()}');
    
    try {
      // 거리 데이터 파싱
      List<double> distances = List<double>.from(json['distances']?.map((x) => x.toDouble()) ?? []);
      double hfov = (json['hfov'] ?? 360.0).toDouble();
      List<double> vfov = List<double>.from(json['vfov']?.map((x) => x.toDouble()) ?? []);
      int channel = json['channel'] ?? 0;
      
      // 방위각과 수직각 계산
      List<double> azimuth = [];
      List<double> verticalAngle = [];
      List<int> pointIndex = [];
      
      // 이 채널의 수직각 결정 (변수를 미리 선언)
      double thisChannelVerticalAngle = 0.0;
      if (vfov.isNotEmpty && channel < vfov.length) {
        thisChannelVerticalAngle = vfov[channel];
      }
      
      if (json.containsKey('azimuth') && json.containsKey('vertical_angle')) {
        // 서버에서 제공된 경우
        azimuth = List<double>.from(json['azimuth']?.map((x) => x.toDouble()) ?? []);
        verticalAngle = List<double>.from(json['vertical_angle']?.map((x) => x.toDouble()) ?? []);
        pointIndex = List<int>.from(json['point_index'] ?? []);
        print('서버에서 방위각/수직각 직접 제공');
      } else {
        // HFOV/VFOV로부터 계산
        print('HFOV/VFOV로부터 방위각/수직각 계산');
        print('- 채널: $channel');
        print('- HFOV: ${hfov}° (수평 시야각)');
        print('- VFOV: $vfov (수직 각도 레이어들)');
        print('- 이 채널의 거리 데이터: ${distances.length}개');
        
        print('- 이 채널(${channel})의 수직각: ${thisChannelVerticalAngle}°');
        
        // 각 거리 데이터에 대해 방위각 계산
        int totalPoints = distances.length;
        for (int i = 0; i < totalPoints; i++) {
          // 방위각: HFOV를 전체 포인트 수로 균등분할
          // 예: HFOV=100°이면 -50° ~ +50° 범위를 400개로 분할
          double azimuthStep = hfov / (totalPoints > 1 ? totalPoints - 1 : 1);
          double currentAzimuth = -hfov/2 + (i * azimuthStep);
          
          // 수직각: 이 채널에 해당하는 고정 수직각
          double currentVerticalAngle = thisChannelVerticalAngle;
          
          azimuth.add(currentAzimuth);
          verticalAngle.add(currentVerticalAngle);
          pointIndex.add(i);
        }
        
        // print('계산 완료:');
        // print('- 방위각 범위: ${azimuth.isEmpty ? 0 : azimuth.first.toStringAsFixed(1)}° ~ ${azimuth.isEmpty ? 0 : azimuth.last.toStringAsFixed(1)}°');
        // print('- 수직각: ${thisChannelVerticalAngle}° (고정)');
        // if (azimuth.length > 1) {
        //   print('- 방위각 스텝: ${(azimuth[1] - azimuth[0]).toStringAsFixed(3)}°');
        // }
      }
      
      final lidar = Lidar(
        channel: channel,
        hfov: hfov,
        vfov: vfov,
        distances: distances,
        azimuth: azimuth,
        intensities: List<double>.from(json['intensities']?.map((x) => x.toDouble()) ?? 
                      List.generate(distances.length, (_) => 128.0)), // 기본 강도값
        pointIndex: pointIndex,
        verticalAngle: verticalAngle,
        maxRange: (json['max'] ?? json['max_range'] ?? 100.0).toDouble(),
      );
      
      print('Lidar 객체 생성 성공:');
      print('- 채널: ${lidar.channel}');
      print('- 거리 데이터: ${lidar.distances.length}개');
      // print('- 방위각: ${lidar.azimuth.length}개');
      // print('- 수직각: ${lidar.verticalAngle.length}개 (모두 ${thisChannelVerticalAngle}°)');
      print('- 최대 거리: ${lidar.maxRange}m');
      print('=== Lidar.fromJson 완료 ===');
      
      return lidar;
    } catch (e) {
      print('Lidar.fromJson 에러: $e');
      // print('문제 JSON: $json');
      rethrow;
    }
  }

  List<Point3D> to3DPoints() {
    List<Point3D> points = [];
    
    for (int i = 0; i < distances.length; i++) {
      if (i >= azimuth.length || i >= verticalAngle.length) continue;
      
      double distance = distances[i];
      double azimuthRad = azimuth[i] * (math.pi / 180);
      double verticalAngleRad = verticalAngle[i] * (math.pi / 180);
      double intensity = i < intensities.length ? intensities[i] : 0.0;
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
        intensity: intensity,
        pointIndex: pointIdx,
        verticalAngle: verticalAngle[i],
      ));
    }
    
    return points;
  }
}