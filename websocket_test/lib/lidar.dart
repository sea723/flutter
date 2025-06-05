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
  final int? detection; // Kanavi 라이다의 Detection 데이터 추가

  Point3D({
    required this.x,
    required this.y,
    required this.z,
    required this.distance,
    required this.channel,
    required this.intensity,
    required this.pointIndex,
    required this.verticalAngle,
    this.detection, // 선택적 필드
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
  final double maxRange; // 최대 거리
  final String? model; // 라이다 모델명 추가
  final String? lidarId; // 라이다 ID 추가
  final List<int>? detectionData; // Kanavi Detection 데이터 추가

  Lidar({
    required this.channel,
    required this.hfov,
    required this.vfov,
    required this.distances,
    required this.azimuth,
    required this.intensities,
    required this.pointIndex,
    required this.verticalAngle,
    required this.maxRange,
    this.model, // 선택적 필드
    this.lidarId, // 선택적 필드
    this.detectionData, // 선택적 필드
  });

  factory Lidar.fromJson(Map<String, dynamic> json) {
    print('=== Lidar.fromJson 시작 ===');
    print('Input JSON keys: ${json.keys.toList()}');
    
    try {
      // 기본 데이터 파싱
      List<double> distances = List<double>.from(json['distances']?.map((x) => x.toDouble()) ?? []);
      double hfov = (json['hfov'] ?? 360.0).toDouble();
      int channel = json['channel'] ?? 0;
      
      // 라이다 모델 정보
      String? model = json['model']?.toString();
      String? lidarId = json['lidar_id']?.toString();
      
      print('모델: $model, 라이다 ID: $lidarId, 채널: $channel');
      
      // VFOV 처리 - Kanavi 서버는 고정 수직각 배열로 전송
      List<double> vfov = [];
      if (json.containsKey('vfov') && json['vfov'] is List) {
        vfov = List<double>.from(json['vfov']?.map((x) => x.toDouble()) ?? []);
      } else {
        // 모델별 기본 VFOV 설정
        if (model != null) {
          if (model.contains('VL-R4')) {
            vfov = [-1.5, -0.5, 0.5, 1.5]; // VL-R4: 4채널
          } else if (model.contains('VL-R2')) {
            vfov = [-0.5, 0.5]; // VL-R2: 2채널
          } else if (model.contains('VL-R270')) {
            vfov = [0.0]; // VL-R270: 1채널
          } else {
            vfov = [0.0]; // 기본값
          }
        } else {
          vfov = [0.0];
        }
      }
      
      // 방위각과 수직각 계산
      List<double> azimuth = [];
      List<double> verticalAngle = [];
      List<int> pointIndex = [];
      
      // 이 채널의 수직각 결정
      double thisChannelVerticalAngle = 0.0;
      if (vfov.isNotEmpty && channel < vfov.length) {
        thisChannelVerticalAngle = vfov[channel];
      } else if (json.containsKey('vertical_angle') && json['vertical_angle'] is List) {
        // Kanavi 서버에서 vertical_angle 배열로 전송하는 경우
        List<double> verticalAngles = List<double>.from(json['vertical_angle']?.map((x) => x.toDouble()) ?? []);
        if (verticalAngles.isNotEmpty) {
          thisChannelVerticalAngle = verticalAngles.first; // 첫 번째 값 사용 (고정값)
        }
      }
      
      if (json.containsKey('azimuth') && json.containsKey('vertical_angle')) {
        // 서버에서 방위각/수직각을 직접 제공하는 경우
        azimuth = List<double>.from(json['azimuth']?.map((x) => x.toDouble()) ?? []);
        
        // vertical_angle이 배열인지 단일값인지 확인
        if (json['vertical_angle'] is List) {
          verticalAngle = List<double>.from(json['vertical_angle']?.map((x) => x.toDouble()) ?? []);
        } else {
          // 단일값인 경우 모든 포인트에 동일한 수직각 적용
          double singleVerticalAngle = (json['vertical_angle'] ?? 0.0).toDouble();
          verticalAngle = List.generate(distances.length, (_) => singleVerticalAngle);
        }
        
        pointIndex = List<int>.from(json['point_index'] ?? 
                    List.generate(distances.length, (i) => i));
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
          double azimuthStep = hfov / (totalPoints > 1 ? totalPoints - 1 : 1);
          double currentAzimuth = -hfov/2 + (i * azimuthStep);
          
          // 수직각: 이 채널에 해당하는 고정 수직각
          double currentVerticalAngle = thisChannelVerticalAngle;
          
          azimuth.add(currentAzimuth);
          verticalAngle.add(currentVerticalAngle);
          pointIndex.add(i);
        }
        
        print('계산 완료:');
        print('- 방위각 범위: ${azimuth.isEmpty ? 0 : azimuth.first.toStringAsFixed(1)}° ~ ${azimuth.isEmpty ? 0 : azimuth.last.toStringAsFixed(1)}°');
        print('- 수직각: ${thisChannelVerticalAngle}° (고정)');
        if (azimuth.length > 1) {
          print('- 방위각 스텝: ${(azimuth[1] - azimuth[0]).toStringAsFixed(3)}°');
        }
      }
      
      // Kanavi Detection 데이터 처리
      List<int>? detectionData;
      if (json.containsKey('detection_data')) {
        detectionData = List<int>.from(json['detection_data']?.map((x) => x.toInt()) ?? []);
        print('Detection 데이터: ${detectionData?.length ?? 0}개');
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
        model: model, // 모델명 저장
        lidarId: lidarId, // 라이다 ID 저장
        detectionData: detectionData, // Detection 데이터 저장
      );
      
      print('Lidar 객체 생성 성공:');
      print('- 모델: ${lidar.model ?? "Unknown"}');
      print('- 라이다 ID: ${lidar.lidarId ?? "Unknown"}');
      print('- 채널: ${lidar.channel}');
      print('- 거리 데이터: ${lidar.distances.length}개');
      print('- 방위각: ${lidar.azimuth.length}개');
      print('- 수직각: ${lidar.verticalAngle.length}개 (모두 ${thisChannelVerticalAngle}°)');
      print('- 최대 거리: ${lidar.maxRange}m');
      if (detectionData != null) {
        print('- Detection 데이터: ${detectionData.length}개');
      }
      print('=== Lidar.fromJson 완료 ===');
      
      return lidar;
    } catch (e) {
      print('Lidar.fromJson 에러: $e');
      print('문제 JSON: $json');
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
      
      // Detection 데이터 (있는 경우)
      int? detection;
      if (detectionData != null && i < detectionData!.length) {
        detection = detectionData![i];
      }
      
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
        detection: detection, // Detection 데이터 추가
      ));
    }
    
    return points;
  }
  
  // Kanavi 라이다 특수 기능들
  
  /// Detection 비트 분석 (Kanavi 프로토콜 6페이지 참조)
  Map<String, bool> analyzeDetection(int detectionByte) {
    return {
      'isAreaSet': (detectionByte & 0x01) != 0,
      'outputPin1': (detectionByte & 0x02) != 0,
      'outputPin2': (detectionByte & 0x04) != 0,
      'areaDetect1': (detectionByte & 0x08) != 0,
      'areaDetect2': (detectionByte & 0x10) != 0,
      'areaDetect3': (detectionByte & 0x20) != 0,
      'areaDetect4': (detectionByte & 0x40) != 0,
      'areaDetect5': (detectionByte & 0x80) != 0,
    };
  }
  
  /// 모든 Detection 데이터 분석
  List<Map<String, bool>> getAllDetectionInfo() {
    if (detectionData == null) return [];
    
    return detectionData!.map((detection) => analyzeDetection(detection)).toList();
  }
  
  /// 감지된 영역이 있는 포인트들만 필터링
  List<Point3D> getDetectedPoints() {
    List<Point3D> allPoints = to3DPoints();
    List<Point3D> detectedPoints = [];
    
    for (int i = 0; i < allPoints.length; i++) {
      Point3D point = allPoints[i];
      if (point.detection != null) {
        Map<String, bool> detectionInfo = analyzeDetection(point.detection!);
        // 어떤 영역이라도 감지된 경우
        bool hasDetection = detectionInfo['areaDetect1']! || 
                           detectionInfo['areaDetect2']! ||
                           detectionInfo['areaDetect3']! ||
                           detectionInfo['areaDetect4']! ||
                           detectionInfo['areaDetect5']!;
        
        if (hasDetection) {
          detectedPoints.add(point);
        }
      }
    }
    
    return detectedPoints;
  }
}