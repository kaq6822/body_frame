import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

/// 격자 카메라 화면이 의존하는 카메라 컨트롤러 추상 인터페이스.
///
/// `camera` 패키지의 [CameraController]는 실기기 카메라 하드웨어에 직접
/// 접근하므로 위젯 테스트에서 그대로 사용할 수 없다. 화면은 이 인터페이스에만
/// 의존하고, 테스트는 [captureCameraControllerFactoryProvider]를
/// `ProviderScope(overrides:)`로 교체해 가짜 구현을 주입한다.
abstract class CaptureCameraController {
  /// 카메라가 초기화되어 미리보기/촬영이 가능한 상태인지 여부.
  bool get isInitialized;

  /// 미리보기 화면비(가로/세로). 격자 오버레이 정렬에 사용한다.
  double get aspectRatio;

  /// 카메라를 초기화한다. 실패하면 예외를 던진다(권한 거부 포함).
  Future<void> initialize();

  /// 카메라 미리보기 위젯을 생성한다. 초기화 이후에만 유효한 프리뷰를 반환한다.
  Widget buildPreview();

  /// 사진을 촬영하고 임시 저장된 파일의 절대 경로를 반환한다.
  ///
  /// 반환된 경로는 [PhotoStorageService.saveOriginal]로 앱 저장소에
  /// 무변형 복사한다. 촬영 리뷰가 저장·재촬영·뒤로가기 시 임시 원본을 정리한다.
  Future<String> takePicture();

  /// 리소스를 해제한다.
  Future<void> dispose();
}

/// [CaptureCameraController]의 실기기 구현. `camera` 패키지를 래핑한다.
class DeviceCaptureCameraController implements CaptureCameraController {
  CameraController? _controller;

  @override
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  @override
  double get aspectRatio => _controller?.value.aspectRatio ?? (3 / 4);

  @override
  Future<void> initialize() async {
    final previous = _controller;
    _controller = null;
    await previous?.dispose();

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw StateError('사용 가능한 카메라를 찾을 수 없습니다.');
    }
    final description = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
    );
    _controller = controller;
    try {
      await controller.initialize();
    } catch (_) {
      if (identical(_controller, controller)) {
        _controller = null;
      }
      await controller.dispose();
      rethrow;
    }
  }

  @override
  Widget buildPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return CameraPreview(controller);
  }

  @override
  Future<String> takePicture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw StateError('카메라가 초기화되지 않았습니다.');
    }
    final file = await controller.takePicture();
    return file.path;
  }

  @override
  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}
