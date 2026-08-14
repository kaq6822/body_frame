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

  /// 센서 종횡비(가로 ÷ 세로). **가로 기준으로 보고한다**(4:3이면 약 1.33).
  ///
  /// 화면에 그릴 때는 방향에 맞춰 변환해야 한다. 세로로 든 화면에서 이 값을
  /// 그대로 쓰면 미리보기가 납작해지므로 `previewAspectFor`를 거친다.
  double get aspectRatio;

  /// 현재 전면 카메라를 쓰는 중인지.
  bool get isFrontLens;

  /// 전면/후면 전환이 가능한지. 초기화 이후에 유효하다.
  bool get canSwitchLens;

  /// 카메라를 초기화한다. 실패하면 예외를 던진다(권한 거부 포함).
  ///
  /// 요청한 렌즈가 없으면 사용 가능한 다른 렌즈로 대체하고 [isFrontLens]를
  /// 실제로 열린 렌즈에 맞춘다.
  Future<void> initialize({bool useFrontLens = false});

  /// 카메라 미리보기 위젯을 생성한다. 초기화 이후에만 유효한 프리뷰를 반환한다.
  Widget buildPreview();

  /// 사진을 촬영하고 임시 저장된 파일의 절대 경로를 반환한다.
  ///
  /// 반환된 경로는 [PhotoStorageService.saveOriginal]로 앱 저장소에
  /// 무변형 복사한다. 촬영 리뷰가 저장·재촬영·뒤로가기 시 임시 원본을 정리한다.
  /// 전면 카메라로 찍어도 파일을 좌우 반전하지 않는다(원본 무변형 불변식).
  Future<String> takePicture();

  /// 리소스를 해제한다.
  Future<void> dispose();
}

/// 시도할 해상도 프리셋. 높은 쪽부터 내려간다.
///
/// 체형 기록은 전신이 담겨야 해서 해상도가 낮으면 변화를 읽기 어렵다. 그래서
/// 가능한 큰 쪽을 먼저 시도한다. 다만 기기에 따라 높은 프리셋으로는 초기화가
/// 실패하는데, 홈이 카메라인 이 앱에서 그건 앱이 열리지 않는 것과 같다.
/// 그래서 실패하면 한 단계씩 낮춰 재시도한다.
///
/// `max`를 먼저 두는 이유가 하나 더 있다. 많은 기기의 최대 해상도가 4:3이고,
/// 세로로 들면 3:4가 되어 촬영 프레임([kPhotoFrameAspect])을 여백 없이 채운다.
const List<ResolutionPreset> kResolutionFallbackChain = [
  ResolutionPreset.max,
  ResolutionPreset.veryHigh,
  ResolutionPreset.high,
  ResolutionPreset.medium,
];

/// [presets]를 순서대로 시도해 처음 성공한 프리셋을 돌려준다.
///
/// 하나라도 성공하면 그 시점에 멈춘다. 전부 실패하면 **마지막 예외를 그대로**
/// 던져 호출부가 "카메라를 쓸 수 없다"를 기존과 같은 방식으로 다룰 수 있게 한다.
Future<ResolutionPreset> selectWorkingPreset({
  required List<ResolutionPreset> presets,
  required Future<void> Function(ResolutionPreset preset) attempt,
  void Function(ResolutionPreset preset, Object error)? onFailure,
}) async {
  assert(presets.isNotEmpty, '시도할 프리셋이 최소 하나는 있어야 합니다.');
  Object? lastError;
  StackTrace? lastStack;

  for (final preset in presets) {
    try {
      await attempt(preset);
      return preset;
    } catch (error, stack) {
      lastError = error;
      lastStack = stack;
      onFailure?.call(preset, error);
    }
  }

  Error.throwWithStackTrace(lastError!, lastStack!);
}

/// [CaptureCameraController]의 실기기 구현. `camera` 패키지를 래핑한다.
class DeviceCaptureCameraController implements CaptureCameraController {
  CameraController? _controller;

  /// `availableCameras()`는 플랫폼 채널 왕복이라 렌즈를 바꿀 때마다 다시
  /// 물어보면 전환이 느려진다. 기기의 카메라 목록은 앱 실행 중 바뀌지 않으므로
  /// 한 번 조회한 결과를 재사용한다.
  List<CameraDescription>? _cameras;

  bool _isFrontLens = false;

  @override
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  // 폴백도 가로 기준이다. 세로 값(3/4)을 두면 초기화 전후로 방향이 뒤집힌다.
  @override
  double get aspectRatio => _controller?.value.aspectRatio ?? (4 / 3);

  @override
  bool get isFrontLens => _isFrontLens;

  @override
  bool get canSwitchLens {
    final cameras = _cameras;
    if (cameras == null) return false;
    return cameras.any((c) => c.lensDirection == CameraLensDirection.front) &&
        cameras.any((c) => c.lensDirection == CameraLensDirection.back);
  }

  @override
  Future<void> initialize({bool useFrontLens = false}) async {
    final previous = _controller;
    _controller = null;
    await previous?.dispose();

    final cameras = await _loadCameras();
    if (cameras.isEmpty) {
      throw StateError('사용 가능한 카메라를 찾을 수 없습니다.');
    }
    final wanted = useFrontLens
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    final description = cameras.firstWhere(
      (c) => c.lensDirection == wanted,
      orElse: () => cameras.first,
    );
    _isFrontLens = description.lensDirection == CameraLensDirection.front;

    await selectWorkingPreset(
      presets: kResolutionFallbackChain,
      attempt: (preset) => _initializeWith(description, preset),
      onFailure: (preset, error) {
        // 어떤 프리셋에서 막혔는지는 기기별 문제를 좁히는 데 필요하다.
        // 예외 원문은 남기지 않는다(파일 경로 등이 섞일 수 있다).
        debugPrint('capture.camera.preset.fallback: ${preset.name} 실패');
      },
    );
  }

  /// 주어진 프리셋으로 컨트롤러를 만들고 초기화한다.
  ///
  /// 실패하면 만든 컨트롤러를 정리하고 예외를 넘긴다. 실패한 컨트롤러를 그대로
  /// 두면 다음 프리셋을 시도할 때 카메라 자원을 잡고 있어 또 실패한다.
  Future<void> _initializeWith(
    CameraDescription description,
    ResolutionPreset preset,
  ) async {
    final controller = CameraController(
      description,
      preset,
      enableAudio: false,
    );
    try {
      await controller.initialize();
    } catch (_) {
      await controller.dispose();
      rethrow;
    }
    _controller = controller;
  }

  Future<List<CameraDescription>> _loadCameras() async {
    final cached = _cameras;
    if (cached != null && cached.isNotEmpty) return cached;
    final cameras = await availableCameras();
    // 빈 목록은 캐시하지 않는다. 권한 승인 직후 재시도하면 채워질 수 있다.
    if (cameras.isNotEmpty) _cameras = cameras;
    return cameras;
  }

  @override
  Widget buildPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    // 좌우 반전을 직접 걸지 않는다. 플랫폼 프리뷰가 전면 카메라를 이미 미러링
    // 하는 경우가 있어 이중 반전이 된다.
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
