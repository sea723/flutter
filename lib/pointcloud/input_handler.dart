// input_handler.dart - 마우스/키보드 입력 처리
import 'dart:html' as html;
import 'dart:math' as math;
import 'dart:async';
import 'coordinate_transform.dart';
import '../lidar.dart';

class InputHandler {
  // 마우스 상태
  bool isDragging = false;
  bool isPanning = false;
  bool isZRotating = false;
  html.Point? lastMousePos;
  
  // 키보드 상태
  bool isShiftPressed = false;
  bool isCtrlPressed = false;
  bool isMiddleButtonPressed = false;

  // 회전 상태 추적
  bool isRotating = false;
  DateTime? lastRotationTime;
  Timer? rotationStopTimer;

  // 콜백 함수들
  Function(double, double, double)? onRotationChanged;
  Function(double, double)? onPanChanged;
  Function(double)? onZoomChanged;
  Function(Point3D)? onCoordinateClicked;
  Function()? onRenderRequested;
  Function(bool)? onRotationStateChanged;

  late html.CanvasElement canvas;
  late html.CanvasRenderingContext2D ctx;

  InputHandler({
    this.onRotationChanged,
    this.onPanChanged,
    this.onZoomChanged,
    this.onCoordinateClicked,
    this.onRenderRequested,
    this.onRotationStateChanged,
  });

  /// 캔버스에 이벤트 리스너 등록
  void setupEventListeners(html.CanvasElement canvas, html.CanvasRenderingContext2D ctx) {
    this.canvas = canvas;
    this.ctx = ctx;

    canvas.onMouseDown.listen(_onMouseDown);
    canvas.onMouseMove.listen(_onMouseMove);
    canvas.onMouseUp.listen(_onMouseUp);
    canvas.onWheel.listen(_onWheel);
    canvas.onContextMenu.listen((e) => e.preventDefault());
    canvas.onKeyDown.listen(_onKeyDown);
    canvas.onKeyUp.listen(_onKeyUp);
    canvas.onClick.listen((_) => canvas.focus());
  }

  /// 키보드 눌림 처리
  void _onKeyDown(html.KeyboardEvent event) {
    switch (event.code) {
      case 'ShiftLeft':
      case 'ShiftRight':
        isShiftPressed = true;
        break;
      case 'ControlLeft':
      case 'ControlRight':
        isCtrlPressed = true;
        break;
    }
    _updateCursor();
  }

  /// 키보드 뗌 처리
  void _onKeyUp(html.KeyboardEvent event) {
    switch (event.code) {
      case 'ShiftLeft':
      case 'ShiftRight':
        isShiftPressed = false;
        break;
      case 'ControlLeft':
      case 'ControlRight':
        isCtrlPressed = false;
        break;
    }
    _updateCursor();
  }

  /// 커서 스타일 업데이트
  void _updateCursor() {
    if (isShiftPressed) {
      canvas.style.cursor = 'move';
    } else if (isCtrlPressed) {
      canvas.style.cursor = 'alias';
    } else {
      canvas.style.cursor = 'grab';
    }
  }

  /// 마우스 버튼 눌림 처리
  void _onMouseDown(html.MouseEvent event) {
    lastMousePos = event.client;
    canvas.focus();
    
    // 🎯 좌클릭 시 좌표 출력 (수정자 키 없을 때)
    if (event.button == 0 && !isShiftPressed && !isCtrlPressed) {
      _handleCoordinateClick(event);
    }
    
    if (event.button == 1) {
      isMiddleButtonPressed = true;
      isPanning = true;
      canvas.style.cursor = 'move';
    } else if (event.button == 0) {
      if (isShiftPressed) {
        isPanning = true;
        canvas.style.cursor = 'move';
      } else if (isCtrlPressed) {
        isZRotating = true;
        canvas.style.cursor = 'alias';
      } else {
        isDragging = true;
        canvas.style.cursor = 'grabbing';
      }
    }
    event.preventDefault();
  }

  /// 마우스 이동 처리
  void _onMouseMove(html.MouseEvent event) {
    if (lastMousePos == null) return;
    
    double deltaX = event.client.x.toDouble() - lastMousePos!.x.toDouble();
    double deltaY = event.client.y.toDouble() - lastMousePos!.y.toDouble();

    if (isPanning) {
      double panSensitivity = 0.5;
      double newPanX = deltaX * panSensitivity;
      double newPanY = deltaY * panSensitivity;
      onPanChanged?.call(newPanX, newPanY);
    } else if (isZRotating || isDragging) {
      
      // 🎯 회전 시작 감지
      if (!isRotating) {
        isRotating = true;
        onRotationStateChanged?.call(true);
        print('🔄 회전 시작 - 포인트 렌더링 최적화 모드');
      }
      
      // 🔧 마우스가 눌려있는 동안은 타이머 취소 (계속 최적화 모드 유지)
      rotationStopTimer?.cancel();
      lastRotationTime = DateTime.now();
      
      if (isZRotating) {
        double rotationSensitivity = 0.01;
        double deltaRotZ = deltaX * rotationSensitivity;
        onRotationChanged?.call(0, 0, deltaRotZ);
      } else if (isDragging) {
        double rotationSensitivity = 0.01;
        double deltaRotY = deltaX * rotationSensitivity;
        double deltaRotX = deltaY * rotationSensitivity;
        onRotationChanged?.call(deltaRotX, deltaRotY, 0);
      }
    }
    
    lastMousePos = event.client;
    onRenderRequested?.call();
  }

  /// 마우스 버튼 뗌 처리
  void _onMouseUp(html.MouseEvent event) {
    isDragging = false;
    isPanning = false;
    isZRotating = false;
    isMiddleButtonPressed = false;
    lastMousePos = null;

    // 🎯 마우스 뗄 때 즉시 회전 상태 해제 (타이머 없이 바로)
    if (isRotating) {
      rotationStopTimer?.cancel();
      isRotating = false;
      onRotationStateChanged?.call(false);
      print('✅ 마우스 업 - 풀 품질 렌더링 즉시 재개');
    }

    _updateCursor();
  }

  /// 마우스 휠 처리
  void _onWheel(html.WheelEvent event) {
    double zoomFactor = (1 - event.deltaY * 0.001);
    onZoomChanged?.call(zoomFactor);
    onRenderRequested?.call();
    event.preventDefault();
  }

  /// 좌표 클릭 처리 (원시 데이터 디버깅용)
  void _handleCoordinateClick(html.MouseEvent event) {
    print('=== 🖱️ 마우스 클릭 원시 데이터 분석 ===');
    
    // 1. 순수 마우스 이벤트 정보
    print('📍 event.client: (${event.client.x}, ${event.client.y})');
    print('📍 event.offset: (${event.offset.x}, ${event.offset.y})');
    print('📍 event.page: (${event.page.x}, ${event.page.y})');
    print('📍 event.screen: (${event.screen.x}, ${event.screen.y})');
    
    // 2. 캔버스 정보
    var canvasRect = canvas.getBoundingClientRect();
    print('🖼️ canvas.getBoundingClientRect():');
    print('   left: ${canvasRect.left}, top: ${canvasRect.top}');
    print('   width: ${canvasRect.width}, height: ${canvasRect.height}');
    print('   right: ${canvasRect.right}, bottom: ${canvasRect.bottom}');
    
    // 3. 🔧 정확한 캔버스 내부 좌표 계산
    double canvasX = (event.client.x - canvasRect.left).toDouble();
    double canvasY = (event.client.y - canvasRect.top).toDouble();
    print('📐 캔버스 내부 좌표: (${canvasX.toStringAsFixed(1)}, ${canvasY.toStringAsFixed(1)})');
    
    // 4. 캔버스 실제 크기와 CSS 크기 비교
    print('🎨 canvas.width: ${canvas.width}, canvas.height: ${canvas.height}');
    print('🎨 canvas.style.width: ${canvas.style.width}, canvas.style.height: ${canvas.style.height}');
    print('🎨 canvasRect.width: ${canvasRect.width}, canvasRect.height: ${canvasRect.height}');
    
    // 5. 🔧 DPI 스케일링 보정
    double devicePixelRatio = (html.window.devicePixelRatio ?? 1.0).toDouble();
    print('📱 devicePixelRatio: $devicePixelRatio');
    
    // CSS 크기와 실제 캔버스 크기가 다를 수 있으므로 보정
    double scaleX = canvas.width! / canvasRect.width;
    double scaleY = canvas.height! / canvasRect.height;
    print('📏 스케일 팩터: scaleX=$scaleX, scaleY=$scaleY');
    
    // 스케일 보정된 캔버스 좌표
    double scaledCanvasX = canvasX * scaleX;
    double scaledCanvasY = canvasY * scaleY;
    print('📐 스케일 보정 후: (${scaledCanvasX.toStringAsFixed(1)}, ${scaledCanvasY.toStringAsFixed(1)})');
    
    // 6. 정규화된 좌표들
    double normalizedX = scaledCanvasX / canvas.width!;
    double normalizedY = scaledCanvasY / canvas.height!;
    print('🎯 정규화 좌표 (0~1): (${normalizedX.toStringAsFixed(3)}, ${normalizedY.toStringAsFixed(3)})');
    
    double centeredX = (normalizedX * 2.0) - 1.0;
    double centeredY = (normalizedY * 2.0) - 1.0;
    print('🎪 중심 기준 좌표 (-1~1): (${centeredX.toStringAsFixed(3)}, ${centeredY.toStringAsFixed(3)})');
    
    // 7. Y축 뒤집기 (화면 좌표 → 3D 좌표)
    double flippedY = -centeredY;
    print('🔄 Y축 뒤집기 후: (${centeredX.toStringAsFixed(3)}, ${flippedY.toStringAsFixed(3)})');
    
    // 8. 🔧 간단한 월드 좌표 추정 (검증용)
    double estimatedWorldX = centeredX * 25.0; // 가정: 화면 가장자리 = ±25m
    double estimatedWorldY = flippedY * 25.0;
    print('🧮 간단한 월드 좌표 추정: (${estimatedWorldX.toStringAsFixed(1)}, ${estimatedWorldY.toStringAsFixed(1)})');
    
    print('===========================================\n');
    
    // 9. 🎯 정확한 픽셀 좌표를 좌표 변환 함수에 전달
    // 이제 스케일 보정된 캔버스 좌표를 전달
    onCoordinateClicked?.call(Point3D(
      x: scaledCanvasX, // 스케일 보정된 픽셀 좌표
      y: scaledCanvasY,
      z: 0,
      distance: 0, channel: 0, pointIndex: 0, verticalAngle: 0,
    ));
  }

  /// 좌표 마커 표시 (디버깅 개선)
  void showCoordinateMarker(double screenX, double screenY, Point3D worldCoord) {
    print('🖱️ 입력 화면 좌표: (${screenX.toStringAsFixed(1)}, ${screenY.toStringAsFixed(1)})');
    print('🌍 변환된 월드 좌표: (${worldCoord.x.toStringAsFixed(2)}, ${worldCoord.y.toStringAsFixed(2)}, ${worldCoord.z.toStringAsFixed(2)})');
    
    // 🔧 마커를 정확히 클릭한 위치에 표시 (캔버스 좌표 기준)
    ctx.fillStyle = '#ff0000';
    ctx.beginPath();
    ctx.arc(screenX, screenY, 8, 0, 2 * math.pi); // 약간 더 큰 마커
    ctx.fill();
    
    // 십자선 표시
    ctx.strokeStyle = '#ffff00';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(screenX - 15, screenY);
    ctx.lineTo(screenX + 15, screenY);
    ctx.moveTo(screenX, screenY - 15);
    ctx.lineTo(screenX, screenY + 15);
    ctx.stroke();
    
    // 좌표 텍스트 (배경 추가)
    String coordText = '(${worldCoord.x.toStringAsFixed(1)}, ${worldCoord.y.toStringAsFixed(1)})';
    String pixelText = 'px:(${screenX.toStringAsFixed(0)}, ${screenY.toStringAsFixed(0)})';
    
    ctx.font = '12px Arial';
    var textMetrics = ctx.measureText(coordText);
    double textWidth = math.max((textMetrics.width ?? 0).toDouble(), 120);
    
    // 배경 박스 (두 줄)
    ctx.fillStyle = 'rgba(0, 0, 0, 0.8)';
    ctx.fillRect(screenX + 20, screenY - 25, textWidth + 8, 32);
    
    // 텍스트
    ctx.fillStyle = '#ffffff';
    ctx.fillText(coordText, screenX + 24, screenY - 8);
    ctx.fillStyle = '#aaaaaa';
    ctx.font = '10px Arial';
    ctx.fillText(pixelText, screenX + 24, screenY + 8);
    
    // 🔧 역변환 검증
    _verifyCoordinateTransform(screenX, screenY, worldCoord);
  }
  
  /// 🔍 좌표 변환 검증 (디버깅용)
  void _verifyCoordinateTransform(double originalScreenX, double originalScreenY, Point3D worldCoord) {
    print('🔍 === 변환 검증 시작 ===');
    print('🔍 원본 화면 좌표: (${originalScreenX.toStringAsFixed(1)}, ${originalScreenY.toStringAsFixed(1)})');
    print('🔍 변환된 월드 좌표: (${worldCoord.x.toStringAsFixed(2)}, ${worldCoord.y.toStringAsFixed(2)})');
    
    // 이 함수는 뷰어에서 현재 변환 파라미터를 받아서 역변환을 수행해야 함
    // 현재는 정보만 출력
    print('🔍 역변환 검증은 뷰어 레벨에서 수행 필요');
    print('🔍 ============================');
  }

  /// 입력 상태 초기화
  void reset() {
    isDragging = false;
    isPanning = false;
    isZRotating = false;
    isShiftPressed = false;
    isCtrlPressed = false;
    isMiddleButtonPressed = false;
    lastMousePos = null;
  }

  /// 현재 입력 상태 정보
  Map<String, dynamic> getInputState() {
    return {
      'isDragging': isDragging,
      'isPanning': isPanning,
      'isZRotating': isZRotating,
      'isShiftPressed': isShiftPressed,
      'isCtrlPressed': isCtrlPressed,
      'isMiddleButtonPressed': isMiddleButtonPressed,
    };
  }
}