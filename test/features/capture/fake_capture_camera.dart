import 'package:body_frame/features/capture/camera/capture_camera_controller.dart';
import 'package:flutter/widgets.dart';

/// 위젯 테스트용 [CaptureCameraController] 대역.
///
/// `camera` 패키지는 실기기 하드웨어에 의존하므로 촬영 화면을 검증하는 테스트는
/// 모두 이 대역을 `captureCameraControllerFactoryProvider`로 주입한다.
/// 초기화 호출 수, 해제 호출 수, 촬영 호출 수와 마지막으로 요청된 렌즈를 기록해
/// 렌즈 전환·생명주기 동작을 실기기 없이 확인할 수 있게 한다.
class FakeCaptureCameraController implements CaptureCameraController {
  final bool initializeShouldFail;

  /// [initialize]가 던질 예외. 지정하면 [initializeShouldFail]보다 우선한다.
  ///
  /// 권한 거부처럼 화면이 오류 종류에 따라 다르게 반응해야 하는 경우에 쓴다.
  /// 테스트 중에 바꿀 수 있게 열어 두었다. 권한을 허용하고 돌아온 상황은
  /// "거부로 실패한 뒤 같은 컨트롤러가 성공하는" 흐름으로만 재현할 수 있다.
  Object? initializeError;

  /// 전면/후면이 모두 있는 기기를 흉내낼지. 기본은 전환 불가.
  @override
  final bool canSwitchLens;

  /// 센서 종횡비(가로 ÷ 세로). 실기기처럼 **가로 기준** 값을 준다.
  ///
  /// 기본값은 흔한 4:3 센서다. 16:9(1.78)나 1:1처럼 다른 비율을 주어 프레임이
  /// 센서 비율에 흔들리지 않는지 확인할 수 있다.
  final double sensorAspect;

  final String capturedPath = '/tmp/fake_capture.jpg';

  bool _initialized = false;
  bool _isFrontLens = false;
  int initializeCalls = 0;
  int disposeCalls = 0;
  int takePictureCalls = 0;

  /// [initialize]에 전달된 렌즈 요청 이력(호출 순서대로).
  final List<bool> requestedFrontLens = [];

  FakeCaptureCameraController({
    this.initializeShouldFail = false,
    this.initializeError,
    this.canSwitchLens = false,
    this.sensorAspect = 4 / 3,
  });

  @override
  double get aspectRatio => sensorAspect;

  @override
  bool get isInitialized => _initialized;

  @override
  bool get isFrontLens => _isFrontLens;

  @override
  Future<void> initialize({bool useFrontLens = false}) async {
    initializeCalls += 1;
    requestedFrontLens.add(useFrontLens);
    final error = initializeError;
    if (error != null) throw error;
    if (initializeShouldFail) {
      throw StateError('카메라를 사용할 수 없습니다(테스트).');
    }
    // 전환할 수 없는 기기는 어떤 요청에도 후면으로 남는다.
    _isFrontLens = canSwitchLens && useFrontLens;
    _initialized = true;
  }

  @override
  Widget buildPreview() => const SizedBox(key: ValueKey('fake.camera.preview'));

  @override
  Future<String> takePicture() async {
    takePictureCalls += 1;
    return capturedPath;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    _initialized = false;
  }
}
