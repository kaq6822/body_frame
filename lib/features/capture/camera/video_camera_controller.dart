import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

import 'capture_camera_controller.dart';

/// 레슨 동영상 촬영 화면이 의존하는 카메라 경계.
///
/// 사진 카메라([CaptureCameraController])와 같은 이유로 `camera` 패키지를 직접
/// 쓰지 않고 이 인터페이스 뒤에 둔다. 테스트는
/// `videoCameraControllerFactoryProvider`를 가짜 구현으로 바꾼다.
abstract class VideoCameraController {
  bool get isInitialized;

  /// 센서 종횡비(가로 기준). 화면에서는 `previewAspectFor`로 방향을 맞춘다.
  double get aspectRatio;

  bool get isFrontLens;

  bool get canSwitchLens;

  /// 소리를 함께 녹화하는지. 마이크 권한이 없으면 false로 내려 소리 없이 녹화한다.
  bool get audioEnabled;

  bool get isRecording;

  /// 카메라를 연다. 마이크가 거부되면 소리 없이 다시 열고 [audioEnabled]를
  /// false로 둔다. 카메라 거부는 예외로 던진다([isCameraPermissionError]).
  ///
  /// [tryAudio]가 false면 마이크를 요청하지 않고 소리 없이 연다. Android는
  /// 오디오를 켠 채 열 때마다 권한 창을 다시 띄우므로, 이번 세션에 이미 거부된
  /// 마이크를 복귀·렌즈 전환 때마다 다시 묻지 않으려고 쓴다.
  Future<void> initialize({bool useFrontLens = false, bool tryAudio = true});

  Widget buildPreview();

  Future<void> startRecording();

  /// 녹화를 끝내고 임시 파일의 절대경로를 반환한다. 파일은 앱 저장소로
  /// 무변형 복사한 뒤 정리한다.
  Future<String> stopRecording();

  Future<void> dispose();
}

/// 마이크 권한 때문에 막혔는지. 카메라 권한 오류와 구분한다.
///
/// 플러그인은 Android `AudioAccessDenied`, iOS에서는 여기에
/// `...WithoutPrompt`/`AudioAccessRestricted`를 쓴다.
bool isAudioPermissionError(Object error) {
  if (error is! CameraException) return false;
  final code = error.code;
  return code.startsWith('Audio') &&
      (code.contains('AccessDenied') || code.contains('AccessRestricted'));
}

/// 동영상은 사진보다 해상도를 낮춰도 동작 확인에 충분하고 파일이 훨씬 커진다.
/// 1080p부터 시도하고 실패하면 한 단계씩 낮춘다.
const List<ResolutionPreset> kVideoResolutionFallbackChain = [
  ResolutionPreset.veryHigh,
  ResolutionPreset.high,
  ResolutionPreset.medium,
];

class DeviceVideoCameraController implements VideoCameraController {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isFrontLens = false;
  bool _audioEnabled = true;

  @override
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  @override
  double get aspectRatio => _controller?.value.aspectRatio ?? (16 / 9);

  @override
  bool get isFrontLens => _isFrontLens;

  @override
  bool get audioEnabled => _audioEnabled;

  @override
  bool get isRecording => _controller?.value.isRecordingVideo ?? false;

  @override
  bool get canSwitchLens {
    final cameras = _cameras;
    if (cameras == null) return false;
    return cameras.any((c) => c.lensDirection == CameraLensDirection.front) &&
        cameras.any((c) => c.lensDirection == CameraLensDirection.back);
  }

  @override
  Future<void> initialize({
    bool useFrontLens = false,
    bool tryAudio = true,
  }) async {
    final previous = _controller;
    _controller = null;
    await previous?.dispose();

    var cameras = _cameras;
    if (cameras == null || cameras.isEmpty) {
      cameras = await availableCameras();
      if (cameras.isNotEmpty) _cameras = cameras;
    }
    if (cameras.isEmpty) {
      throw StateError('사용 가능한 카메라를 찾을 수 없습니다.');
    }
    final wanted = useFrontLens
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    final description = cameras.firstWhere(
      (c) => c.lensDirection == wanted,
      orElse: () => cameras!.first,
    );
    _isFrontLens = description.lensDirection == CameraLensDirection.front;
    _audioEnabled = tryAudio;

    await selectWorkingPreset(
      presets: kVideoResolutionFallbackChain,
      attempt: (preset) => _initializeWith(description, preset),
      onFailure: (preset, error) {
        debugPrint('video.camera.preset.fallback: ${preset.name} 실패');
      },
      isUnrecoverable: isCameraPermissionError,
    );
  }

  Future<void> _initializeWith(
    CameraDescription description,
    ResolutionPreset preset,
  ) async {
    if (_audioEnabled) {
      try {
        await _open(description, preset, enableAudio: true);
        return;
      } catch (error) {
        if (!isAudioPermissionError(error)) rethrow;
        _audioEnabled = false;
      }
    }
    await _open(description, preset, enableAudio: false);
  }

  Future<void> _open(
    CameraDescription description,
    ResolutionPreset preset, {
    required bool enableAudio,
  }) async {
    final controller = CameraController(
      description,
      preset,
      enableAudio: enableAudio,
    );
    try {
      await controller.initialize();
    } catch (_) {
      await controller.dispose();
      rethrow;
    }
    _controller = controller;
  }

  CameraController _ready() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw StateError('카메라가 초기화되지 않았습니다.');
    }
    return controller;
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
  Future<void> startRecording() async {
    final controller = _ready();
    await controller.prepareForVideoRecording();
    await controller.startVideoRecording();
  }

  @override
  Future<String> stopRecording() async {
    final file = await _ready().stopVideoRecording();
    return file.path;
  }

  @override
  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}
