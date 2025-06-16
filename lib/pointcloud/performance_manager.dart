// performance_manager.dart - 성능 최적화 및 캐시 관리
import 'dart:html' as html;
import 'dart:math' as math;

class PerformanceManager {
  // 프레임 제한 관련
  static const int targetFPS = 20;
  static const int frameInterval = 1000 ~/ targetFPS;
  DateTime lastRender = DateTime.now();
  
  // 캐시 관련
  html.CanvasElement? gridCache;
  bool gridCacheInvalid = true;
  
  // 상태 추적 (캐시 무효화 판단용)
  double lastRotationX = 0.0;
  double lastRotationY = 0.0;
  double lastRotationZ = 0.0;
  double lastZoom = 0.0;
  double lastPanX = 0.0;
  double lastPanY = 0.0;
  
  // 성능 통계
  int frameCount = 0;
  DateTime lastFPSCheck = DateTime.now();
  double currentFPS = 0.0;
  List<double> frameTimes = [];
  
  // 렌더링 통계
  int lastRenderedPoints = 0;
  int lastCulledPoints = 0;
  int lastRenderedGrids = 0;
  int lastCulledGrids = 0;


  // 회전 감지
  bool isRotationDetected = false;
  DateTime lastRotationChange = DateTime.now();
  

  /// 그리드 캐시 초기화
  void initializeGridCache(int width, int height) {
    gridCache?.remove(); // 기존 캐시 정리
    gridCache = html.CanvasElement()
      ..width = width
      ..height = height;
    gridCacheInvalid = true;
  }

  /// 캐시 무효화 확인 (더 관대한 임계값)
  bool shouldInvalidateCache(
    double rotationX,
    double rotationY,
    double rotationZ,
    double zoom,
    double panX,
    double panY,
  ) {
    double rotationThreshold = 0.05; // 회전 임계값 증가
    double zoomThreshold = 0.1; // 줌 임계값 증가
    double panThreshold = 10.0; // 팬 임계값 증가
    
    return (rotationX - lastRotationX).abs() > rotationThreshold ||
           (rotationY - lastRotationY).abs() > rotationThreshold ||
           (rotationZ - lastRotationZ).abs() > rotationThreshold ||
           (zoom - lastZoom).abs() > zoomThreshold ||
           (panX - lastPanX).abs() > panThreshold ||
           (panY - lastPanY).abs() > panThreshold;
  }

  /// 현재 상태 저장
  void saveCurrentState(
    double rotationX,
    double rotationY,
    double rotationZ,
    double zoom,
    double panX,
    double panY,
  ) {
    lastRotationX = rotationX;
    lastRotationY = rotationY;
    lastRotationZ = rotationZ;
    lastZoom = zoom;
    lastPanX = panX;
    lastPanY = panY;
  }

  /// 프레임 제한 확인
  bool canRender() {
    DateTime now = DateTime.now();
    if (now.difference(lastRender).inMilliseconds < frameInterval) {
      return false;
    }
    lastRender = now;
    return true;
  }

  /// FPS 계산 및 업데이트
  void updateFPS() {
    frameCount++;
    DateTime now = DateTime.now();
    
    // 프레임 시간 기록
    if (frameTimes.length > 0) {
      double frameTime = now.difference(lastRender).inMicroseconds / 1000.0;
      frameTimes.add(frameTime);
      
      // 최근 60프레임만 유지
      if (frameTimes.length > 60) {
        frameTimes.removeAt(0);
      }
    }
    
    // 1초마다 FPS 계산
    if (now.difference(lastFPSCheck).inMilliseconds >= 1000) {
      currentFPS = frameCount * 1000.0 / now.difference(lastFPSCheck).inMilliseconds;
      frameCount = 0;
      lastFPSCheck = now;
    }
  }

  /// 평균 프레임 시간 계산
  double getAverageFrameTime() {
    if (frameTimes.isEmpty) return 0.0;
    return frameTimes.reduce((a, b) => a + b) / frameTimes.length;
  }

  /// 메모리 사용량 추정
  Map<String, dynamic> getMemoryUsage(int pointCount, int gridElements) {
    // 대략적인 메모리 사용량 계산 (바이트)
    int pointMemory = pointCount * 64; // Point3D 당 약 64바이트
    int gridMemory = gridElements * 32; // 그리드 요소 당 약 32바이트
    int cacheMemory = gridCache != null ? (gridCache!.width! * gridCache!.height! * 4) : 0; // RGBA 픽셀
    
    int totalMemory = pointMemory + gridMemory + cacheMemory;
    
    return {
      'pointMemory': pointMemory,
      'gridMemory': gridMemory,
      'cacheMemory': cacheMemory,
      'totalMemory': totalMemory,
      'totalMB': totalMemory / (1024 * 1024),
    };
  }

  /// 성능 통계 업데이트
  void updateRenderingStats({
    int renderedPoints = 0,
    int culledPoints = 0,
    int renderedGrids = 0,
    int culledGrids = 0,
  }) {
    lastRenderedPoints = renderedPoints;
    lastCulledPoints = culledPoints;
    lastRenderedGrids = renderedGrids;
    lastCulledGrids = culledGrids;
  }

  /// 상세 성능 디버깅 정보
  void debugPerformanceInfo({
    required double zoom,
    required double panX,
    required double panY,
    required int canvasWidth,
    required int canvasHeight,
    required double maxRange,
    required double gridStep,
  }) {
    if (DateTime.now().millisecondsSinceEpoch % 3000 < 100) { // 3초마다
      print('=== 성능 디버깅 정보 ===');
      print('FPS: ${currentFPS.toStringAsFixed(1)} (목표: $targetFPS)');
      print('평균 프레임 시간: ${getAverageFrameTime().toStringAsFixed(2)}ms');
      print('Zoom: ${zoom.toStringAsFixed(3)}');
      print('Pan: (${panX.toStringAsFixed(1)}, ${panY.toStringAsFixed(1)})');
      print('Canvas: ${canvasWidth}x${canvasHeight}');
      print('Grid 범위: ±${maxRange}m, 간격: ${gridStep}m');
      print('화면 대각선: ${math.sqrt(canvasWidth * canvasWidth + canvasHeight * canvasHeight).toStringAsFixed(1)}');
      print('중심 거리: ${math.sqrt(panX * panX + panY * panY).toStringAsFixed(1)}');
      print('캐시 무효화: $gridCacheInvalid');
      print('포인트 - 렌더링: $lastRenderedPoints, 컬링: $lastCulledPoints');
      print('그리드 - 렌더링: $lastRenderedGrids, 컬링: $lastCulledGrids');
      
      // 메모리 사용량
      var memUsage = getMemoryUsage(lastRenderedPoints + lastCulledPoints, lastRenderedGrids + lastCulledGrids);
      print('메모리 사용량: ${memUsage['totalMB'].toStringAsFixed(2)}MB');
      print('');
    }
  }

  /// 성능 최적화 제안
  List<String> getOptimizationSuggestions() {
    List<String> suggestions = [];
    
    if (currentFPS < targetFPS * 0.8) {
      suggestions.add('FPS가 낮습니다. 포인트 크기나 그리드 밀도를 줄여보세요.');
    }
    
    if (getAverageFrameTime() > frameInterval * 1.5) {
      suggestions.add('프레임 시간이 길어졌습니다. LOD 설정을 확인해보세요.');
    }
    
    var memUsage = getMemoryUsage(lastRenderedPoints + lastCulledPoints, lastRenderedGrids + lastCulledGrids);
    if (memUsage['totalMB'] > 100) {
      suggestions.add('메모리 사용량이 높습니다. 데이터 크기를 줄여보세요.');
    }
    
    double cullingRatio = lastCulledPoints / math.max(lastRenderedPoints + lastCulledPoints, 1);
    if (cullingRatio < 0.3) {
      suggestions.add('컬링 효율이 낮습니다. 뷰 영역을 조정해보세요.');
    }
    
    return suggestions;
  }

  /// 자동 성능 조정
  Map<String, dynamic> getAutoOptimizationSettings() {
    Map<String, dynamic> settings = {};
    
    // FPS 기반 자동 조정
    if (currentFPS < targetFPS * 0.6) {
      // 성능이 매우 나쁨
      settings['pointLOD'] = 4; // 4개 중 1개만 표시
      settings['gridStep'] = 2.0; // 그리드 간격 2배
      settings['enableCaching'] = true;
    } else if (currentFPS < targetFPS * 0.8) {
      // 성능이 나쁨
      settings['pointLOD'] = 2; // 2개 중 1개만 표시
      settings['gridStep'] = 1.5; // 그리드 간격 1.5배
      settings['enableCaching'] = true;
    } else {
      // 성능이 좋음
      settings['pointLOD'] = 1; // 모든 포인트 표시
      settings['gridStep'] = 1.0; // 기본 그리드 간격
      settings['enableCaching'] = true;
    }
    
    return settings;
  }

  /// 캐시 정리
  void clearCache() {
    gridCache?.remove();
    gridCache = null;
    gridCacheInvalid = true;
  }

  /// 성능 리셋
  void reset() {
    frameCount = 0;
    currentFPS = 0.0;
    frameTimes.clear();
    lastFPSCheck = DateTime.now();
    lastRender = DateTime.now();
    
    lastRenderedPoints = 0;
    lastCulledPoints = 0;
    lastRenderedGrids = 0;
    lastCulledGrids = 0;
  }

  /// 성능 통계 요약
  Map<String, dynamic> getPerformanceSummary() {
    return {
      'fps': currentFPS,
      'targetFPS': targetFPS,
      'avgFrameTime': getAverageFrameTime(),
      'renderedPoints': lastRenderedPoints,
      'culledPoints': lastCulledPoints,
      'renderedGrids': lastRenderedGrids,
      'culledGrids': lastCulledGrids,
      'cacheValid': !gridCacheInvalid,
      'memoryUsage': getMemoryUsage(lastRenderedPoints + lastCulledPoints, lastRenderedGrids + lastCulledGrids),
      'optimizationSuggestions': getOptimizationSuggestions(),
    };
  }

  /// 회전 감지 업데이트
  bool updateRotationState(
    double rotationX,
    double rotationY,
    double rotationZ,
  ) {
    double rotationThreshold = 0.01; // 더 민감하게
    
    bool hasRotationChange = 
      (rotationX - lastRotationX).abs() > rotationThreshold ||
      (rotationY - lastRotationY).abs() > rotationThreshold ||
      (rotationZ - lastRotationZ).abs() > rotationThreshold;
    
    if (hasRotationChange) {
      lastRotationChange = DateTime.now();
      isRotationDetected = true;
      return true;
    }
    
    // 200ms 동안 회전이 없으면 회전 완료로 간주
    if (DateTime.now().difference(lastRotationChange).inMilliseconds > 200) {
      isRotationDetected = false;
      return false;
    }
    
    return isRotationDetected;
  }

  /// 리소스 정리
  void dispose() {
    clearCache();
    frameTimes.clear();
  }
}