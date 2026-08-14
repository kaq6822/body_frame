import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/photo_frame.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/core/router/app_routes.dart';
import 'package:body_frame/core/services/app_logger.dart';
import 'package:body_frame/core/theme/app_tokens.dart';
import 'package:body_frame/features/records/providers/records_providers.dart';
import 'package:body_frame/features/settings/providers/settings_providers.dart';
import 'camera/capture_camera_controller.dart';
import 'camera_permission_guide.dart';
import 'providers/capture_providers.dart';
import 'providers/capture_session_provider.dart';
import 'utils/capture_guides.dart';
import 'utils/temporary_capture.dart';
import 'widgets/async_status_indicator.dart';
import 'widgets/camera_notice_card.dart';
import 'widgets/capture_progress_bar.dart';
import 'widgets/grid_overlay.dart';
import 'widgets/grid_settings_panel.dart';

/// 홈 = 연속 세션 촬영 화면.
///
/// 앱을 열면 곧바로 이 화면이다. 정면 → 좌측면 → 우측면 → 후면을 한 화면에서
/// 이어 찍고, 셔터를 누르면 화면을 벗어나지 않고 다음 방향으로 자동 전환된다.
/// 마지막 컷을 찍으면 리뷰 화면으로 이동해 한 번에 저장한다. 기록과 설정은
/// 이 화면에서 위로 쌓아 올린다.
///
/// 카메라 컨트롤러는 [captureCameraControllerFactoryProvider]로 주입한다.
/// 테스트에서는 `ProviderScope(overrides: [captureCameraControllerFactoryProvider
/// .overrideWithValue(() => FakeController())])`로 실기기 카메라 없이 검증한다.
class GridCameraScreen extends ConsumerStatefulWidget {
  static const screenId = 'screen.capture.camera';

  /// 셀프 타이머가 순환하는 값(초). 0은 끔.
  ///
  /// 설정 화면의 기본값 목록과 같은 원본을 쓴다.
  static const timerOptions = CaptureOptions.timerChoices;

  const GridCameraScreen({super.key});

  @override
  ConsumerState<GridCameraScreen> createState() => _GridCameraScreenState();
}

enum _CameraStatus { initializing, ready, error, permissionDenied }

class _GridCameraScreenState extends ConsumerState<GridCameraScreen>
    with WidgetsBindingObserver {
  late final CaptureCameraController _controller;
  Future<void> _cameraOperations = Future<void>.value();
  _CameraStatus _status = _CameraStatus.initializing;
  bool _capturing = false;
  bool _showQuickPanel = false;
  bool _cameraSuspended = false;
  bool _screenDisposed = false;

  /// 마지막 초기화가 권한 때문에 막혔는지.
  ///
  /// 화면 상태와 따로 둔다. 권한 창이 떠 있는 동안에는 앱이 정지 상태여서
  /// 실패를 화면에 반영하지 못하는데, 그 사실을 잊으면 복귀 직후 같은 초기화를
  /// 다시 시도해 무한히 반복된다.
  bool _permissionDenied = false;

  bool _showPreviousPhotoGuide = true;
  double _previousPhotoGuideOpacity = 0.35;
  String? _failedPreviousPhotoGuidePath;
  bool _useFrontLens = false;

  /// 셀프 타이머 설정값(초).
  ///
  /// 시작값은 설정의 기본값에서 온다. 여기서 바꾼 값은 이 세션에만 적용되고
  /// 영속화하지 않는다(설정 화면의 기본값이 다음 세션의 시작값이다).
  int _timerSeconds = 0;

  /// 설정 기본값을 이미 반영했는지. 설정이 늦게 로드되어도 한 번만 적용한다.
  bool _timerDefaultApplied = false;

  /// 카운트다운 중 남은 초. null이면 카운트다운 중이 아니다.
  int? _countdownRemaining;
  Timer? _countdownTimer;

  bool get _countingDown => _countdownRemaining != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = ref.read(captureCameraControllerFactoryProvider)();
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _cameraSuspended =
        lifecycleState != null && lifecycleState != AppLifecycleState.resumed;
    if (!_cameraSuspended) {
      unawaited(_initCamera());
    }
    // 설정의 셀프 타이머 기본값을 세션 시작값으로 가져온다. 설정은 비동기로
    // 로드되므로 값이 도착하는 시점에 한 번만 반영한다.
    ref.listenManual<AsyncValue<AppSettings>>(
      appSettingsControllerProvider,
      (previous, next) => _applyTimerDefault(next.valueOrNull?.capture),
      fireImmediately: true,
    );
  }

  void _applyTimerDefault(CaptureOptions? options) {
    if (options == null || _timerDefaultApplied) return;
    _timerDefaultApplied = true;
    final seconds = CaptureOptions.normalizeTimer(options.timerSeconds);
    if (seconds == _timerSeconds) return;
    if (!mounted) {
      _timerSeconds = seconds;
      return;
    }
    // initState에서 동기적으로 도착할 수 있어 첫 빌드 이후로 미룬다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _screenDisposed) return;
      setState(() => _timerSeconds = seconds);
    });
  }

  Future<void> _enqueueCameraOperation(Future<void> Function() operation) {
    final next = _cameraOperations.then((_) => operation());
    _cameraOperations = next.catchError(
      (Object error, StackTrace stackTrace) {},
    );
    return next;
  }

  Future<void> _initCamera() {
    return _enqueueCameraOperation(_initCameraNow);
  }

  Future<void> _initCameraNow() async {
    if (_screenDisposed || _cameraSuspended) return;
    setState(() => _status = _CameraStatus.initializing);
    final logger = ref.read(appLoggerProvider);
    logger.phase('capture.camera.init', LogPhase.start);
    try {
      await _controller.initialize(useFrontLens: _useFrontLens);
      _permissionDenied = false;
      if (!mounted || _screenDisposed || _cameraSuspended) return;
      setState(() {
        // 요청한 렌즈가 없으면 컨트롤러가 다른 렌즈로 대체한다. 버튼 상태를
        // 실제로 열린 렌즈에 맞춘다.
        _useFrontLens = _controller.isFrontLens;
        _status = _CameraStatus.ready;
      });
      logger.phase('capture.camera.init', LogPhase.success);
    } catch (error) {
      // 권한 창이 떠 있는 동안 실패하면 아래 setState까지 가지 못한다. 상태
      // 반영보다 먼저 기록해 복귀 시점에 자동 재시도를 막을 근거로 남긴다.
      _permissionDenied = isCameraPermissionError(error);
      if (!mounted || _screenDisposed || _cameraSuspended) return;
      // 카메라를 못 쓰는 상태에서 카운트다운이 계속 돌면 0초에 촬영이 실패한다.
      _stopCountdown();
      setState(() => _status = _failureStatus);
      logger.phase('capture.camera.init', LogPhase.failure);
    }
  }

  _CameraStatus get _failureStatus =>
      _permissionDenied ? _CameraStatus.permissionDenied : _CameraStatus.error;

  /// 이 앱의 시스템 설정 화면을 연다.
  ///
  /// 실패해도 화면 상태는 건드리지 않는다. 설정 앱이 없거나 열기가 막힌 기기에서도
  /// 카드에 남아 있는 경로 안내로 사용자가 직접 찾아갈 수 있다.
  void _openAppSettings() {
    unawaited(
      ref.read(openAppSettingsProvider)().catchError((Object error) {
        ref
            .read(appLoggerProvider)
            .phase('capture.camera.settings.open', LogPhase.failure);
      }),
    );
  }

  /// 안내를 보고 사용자가 직접 누르는 재시도.
  ///
  /// 권한을 켜고 돌아온 경우가 여기로 온다. 막혔던 기록을 지워 초기화를 처음부터
  /// 다시 진행한다.
  void _retryCamera() {
    _permissionDenied = false;
    unawaited(_initCamera());
  }

  Future<void> _disposeCamera() {
    return _enqueueCameraOperation(() async {
      try {
        await _controller.dispose();
      } catch (_) {
        // lifecycle 정리 실패는 다음 initialize에서 다시 정리한다.
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_screenDisposed) return;
    if (state == AppLifecycleState.resumed) {
      if (!_cameraSuspended) return;
      _cameraSuspended = false;
      if (_permissionDenied) {
        // 권한 창은 뜨고 닫힐 때마다 이 콜백을 흔든다. 그때마다 초기화를 다시
        // 걸면 거부된 권한을 향해 무한히 재시도한다. 안내를 띄우고 사용자의
        // 재시도를 기다린다.
        if (mounted) {
          setState(() => _status = _CameraStatus.permissionDenied);
        }
        return;
      }
      unawaited(_initCamera());
      return;
    }

    if (_cameraSuspended) return;
    _cameraSuspended = true;
    // 백그라운드로 넘어가면 카운트다운을 끝낸다. 기기를 거치해 두고 찍는
    // 화면이라 복귀 후 남은 카운트가 이어지면 의도하지 않은 촬영이 된다.
    _stopCountdown();
    if (mounted) {
      // 권한 안내는 유지한다. 준비 중으로 되돌리면 권한 창이 오갈 때마다
      // 안내가 사라져 사용자가 무엇을 해야 할지 알 수 없다.
      setState(() {
        if (_status != _CameraStatus.permissionDenied) {
          _status = _CameraStatus.initializing;
        }
      });
    }
    unawaited(_disposeCamera());
  }

  @override
  void dispose() {
    _screenDisposed = true;
    _cameraSuspended = true;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _countdownRemaining = null;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disposeCamera());
    super.dispose();
  }

  // --- 셀프 타이머 ---

  void _cycleTimer() {
    final options = GridCameraScreen.timerOptions;
    final next = options[(options.indexOf(_timerSeconds) + 1) % options.length];
    setState(() => _timerSeconds = next);
  }

  void _onShutterPressed() {
    if (_timerSeconds == 0) {
      unawaited(_takePicture());
      return;
    }
    _startCountdown();
  }

  void _startCountdown() {
    if (_countingDown) return;
    setState(() => _countdownRemaining = _timerSeconds);
    _playCountdownTick(_timerSeconds);
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _onCountdownTick(),
    );
  }

  void _onCountdownTick() {
    if (!mounted || _screenDisposed) {
      _stopCountdown();
      return;
    }
    final remaining = (_countdownRemaining ?? 0) - 1;
    if (remaining <= 0) {
      _stopCountdown();
      unawaited(_takePicture());
      return;
    }
    setState(() => _countdownRemaining = remaining);
    _playCountdownTick(remaining);
  }

  /// 카운트다운을 끝내고 [Timer]를 정리한다. 촬영은 하지 않는다.
  void _stopCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (_countdownRemaining == null) return;
    if (mounted && !_screenDisposed) {
      setState(() => _countdownRemaining = null);
    } else {
      _countdownRemaining = null;
    }
  }

  /// 매초 소리와 진동으로 남은 시간을 알린다. 마지막 2초는 진동을 강하게 준다.
  ///
  /// 화면을 보고 있지 않은 상태를 보조하는 장치라, 설정에서 끌 수 있다.
  void _playCountdownTick(int remaining) {
    final enabled =
        ref
            .read(appSettingsControllerProvider)
            .valueOrNull
            ?.capture
            .countdownFeedback ??
        true;
    if (!enabled) return;
    unawaited(SystemSound.play(SystemSoundType.click));
    unawaited(
      remaining <= 2
          ? HapticFeedback.heavyImpact()
          : HapticFeedback.selectionClick(),
    );
  }

  Future<void> _takePicture() async {
    if (_status != _CameraStatus.ready || _capturing) return;
    setState(() => _capturing = true);
    final logger = ref.read(appLoggerProvider);
    logger.phase('capture.shot', LogPhase.start);
    try {
      final path = await _controller.takePicture();
      final grid =
          ref.read(gridSettingsControllerProvider).value ??
          GridSettings.defaults;
      final notifier = ref.read(captureSessionProvider.notifier);
      final wasLastRemaining =
          ref.read(captureSessionProvider).nextUncapturedIndex == null;
      final replaced = notifier.captureCurrent(path, gridSettings: grid);
      if (replaced != null) {
        // 이미 찍은 단계를 다시 찍으면 밀려난 임시 파일은 아무도 참조하지 않는다.
        unawaited(
          deleteTemporaryCaptureBestEffort(
            replaced,
            storage: ref.read(photoStorageServiceProvider),
            logger: logger,
          ),
        );
      }
      logger.phase('capture.shot', LogPhase.success);
      if (!mounted) return;
      // 남은 단계가 없으면 세션을 끝내고 일괄 리뷰로 넘어간다.
      if (wasLastRemaining) {
        _goToReview();
      }
    } catch (_) {
      logger.phase('capture.shot', LogPhase.failure);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('촬영에 실패했습니다. 다시 시도해주세요.')));
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  // --- 이동 ---

  void _goToReview() {
    _stopCountdown();
    context.pushNamed(AppRoutes.captureReview);
  }

  void _openRecords() {
    _stopCountdown();
    context.pushNamed(AppRoutes.records);
  }

  void _openSettings() {
    _stopCountdown();
    context.pushNamed(AppRoutes.settings);
  }

  void _onSkip() {
    final session = ref.read(captureSessionProvider);
    if (session.nextUncapturedIndex == null) {
      // 마지막 남은 단계를 건너뛰는 경우. 찍은 컷이 있으면 리뷰로 보낸다.
      if (session.hasAnyCapture) {
        _goToReview();
      } else {
        // 홈에서는 돌아갈 화면이 없으므로 기록으로 안내한다.
        _openRecords();
      }
      return;
    }
    ref.read(captureSessionProvider.notifier).skipCurrent();
  }

  void _onLensSwitch() {
    if (!_controller.canSwitchLens) return;
    _stopCountdown();
    _useFrontLens = !_useFrontLens;
    // 재초기화는 기존 카메라 작업 큐를 통과해 직렬화된다.
    unawaited(_initCamera());
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(captureSessionProvider);
    final direction = session.current.direction;
    final gridAsync = ref.watch(gridSettingsControllerProvider);
    final previousPhotoGuideAsync = ref.watch(
      previousPhotoGuidePathProvider(direction),
    );
    final remaining = _countdownRemaining;

    return Semantics(
      identifier: GridCameraScreen.screenId,
      container: true,
      label: '연속 촬영',
      // 이 화면이 홈이라 뒤로가기는 앱을 닫는다. 그래서 열려 있는 임시 UI를 먼저
      // 거둔다. 패널을 열어 둔 채 뒤로가기를 누르면 앱이 종료돼 버리기 때문이다.
      child: PopScope(
        canPop: !_showQuickPanel && !_countingDown,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_countingDown) {
            _stopCountdown();
            return;
          }
          if (_showQuickPanel) {
            setState(() => _showQuickPanel = false);
          }
        },
        child: Scaffold(
          key: const ValueKey(GridCameraScreen.screenId),
          backgroundColor: context.photoColors.backdrop,
          body: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _buildCameraArea(
                    gridAsync.value,
                    previousPhotoGuideAsync,
                    direction,
                  ),
                ),
                Positioned(
                  top: AppSpacing.sp2,
                  left: AppSpacing.sp2,
                  right: AppSpacing.sp2,
                  child: _buildTopBar(session),
                ),
                Positioned(
                  left: AppSpacing.sp2,
                  right: AppSpacing.sp2,
                  bottom: 100,
                  child: switch (_status) {
                    _ when _showQuickPanel => _buildQuickPanel(
                      previousPhotoGuideAsync,
                    ),
                    // 미리보기가 없으면 "정면을 바라보고 서세요" 같은 안내는
                    // 따라 할 수 없다. 그 자리를 비워 안내 카드가 겹치지 않게
                    // 하고, 사용자가 지금 읽어야 할 것만 남긴다.
                    _CameraStatus.ready => _buildAssistPanel(direction),
                    _ => const SizedBox.shrink(),
                  },
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: AppSpacing.sp4,
                  child: _buildBottomBar(session),
                ),
                if (remaining != null)
                  Positioned.fill(child: _buildCountdownOverlay(remaining)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 안내 카드를 미리보기 자리 가운데 놓는다.
  ///
  /// 세로가 짧은 기기에서는 카드가 영역보다 높을 수 있다. 그때 잘려 버리면 재시도
  /// 버튼에 손이 닿지 않으므로 스크롤로 접근하게 한다.
  Widget _noticeArea(Widget card) =>
      Center(child: SingleChildScrollView(child: card));

  /// 안내 카드 안의 기록 화면 진입 버튼.
  ///
  /// 카드가 밝으므로 사진 위 컨트롤용 흰색(`photoColors.onChrome`)을 쓰지 않고
  /// 테마 기본 색을 그대로 둔다.
  Widget _buildRecordsFallbackButton() => Semantics(
    identifier: 'capture.camera.records.fallback.button',
    button: true,
    label: '기록 보기',
    child: TextButton.icon(
      key: const ValueKey('capture.camera.records.fallback.button'),
      onPressed: _openRecords,
      icon: const Icon(Icons.photo_library_outlined),
      label: const Text('기록 보기'),
    ),
  );

  Widget _buildCameraArea(
    GridSettings? gridSettings,
    AsyncValue<String?> previousPhotoGuideAsync,
    BodyDirection direction,
  ) => switch (_status) {
    _CameraStatus.initializing => _noticeArea(
      const CameraNoticeCard(
        statusId: 'screen.capture.camera.status',
        tone: CameraNoticeTone.busy,
        title: '카메라를 준비하는 중입니다.',
      ),
    ),
    // 홈이 카메라이므로 카메라를 못 쓰면 앱이 빈 화면이 된다. 재시도와 함께
    // 기록으로 빠져나가는 대체 동선을 항상 남긴다.
    _CameraStatus.error => _noticeArea(
      CameraNoticeCard(
        statusId: 'screen.capture.camera.status',
        tone: CameraNoticeTone.failure,
        title: '카메라를 사용할 수 없습니다.',
        description: '다시 시도해도 열리지 않으면 지난 기록을 먼저 확인해보세요.',
        onRetry: _retryCamera,
        secondaryAction: _buildRecordsFallbackButton(),
      ),
    ),
    // 권한이 없으면 재시도해도 같은 거부가 돌아온다. 설정으로 곧바로 보내고,
    // 재시도는 권한을 켜고 돌아온 뒤 사용자가 직접 누르게 한다.
    _CameraStatus.permissionDenied => _noticeArea(
      CameraNoticeCard(
        statusId: 'screen.capture.camera.status',
        tone: CameraNoticeTone.actionNeeded,
        title: '카메라 권한이 필요합니다.',
        description: '촬영을 시작하려면 카메라 접근을 허용해주세요.',
        onOpenSettings: _openAppSettings,
        onRetry: _retryCamera,
        secondaryAction: _buildRecordsFallbackButton(),
        // 버튼이 열리지 않는 기기도 있어 경로를 함께 남긴다. 플랫폼마다 메뉴
        // 구조가 달라 실행 중인 OS에 맞는 경로만 보여준다.
        settingsPath: cameraPermissionSettingsPath(),
        settingsPathHint: cameraPermissionSettingsHint,
      ),
    ),
    _CameraStatus.ready => Stack(
      children: [
        Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 프레임은 센서 비율과 무관하게 항상 3:4다. 비교 화면이 사진을
              // 같은 비율로 보여주므로, 격자가 두 화면에서 몸 대비 같은 자리에
              // 놓이려면 촬영 프레임도 같은 비율이어야 한다.
              final frame = fitPhotoFrame(constraints);
              final previewAspect = previewAspectFor(
                sensorAspect: _controller.aspectRatio,
                orientation: MediaQuery.orientationOf(context),
              );

              return SizedBox.fromSize(
                key: const ValueKey('capture.frame'),
                size: frame,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 센서 비율이 3:4가 아니면 여백이 남는다. 잘라내지 않는 것은
                    // 미리보기에 보이는 화각과 저장되는 원본을 같게 두기 위해서다.
                    ColoredBox(color: context.photoColors.backdrop),
                    Center(
                      child: AspectRatio(
                        aspectRatio: previewAspect,
                        child: _controller.buildPreview(),
                      ),
                    ),
                    // 이 레이어는 Flutter preview에만 그린다. 실제 촬영은
                    // CameraController.takePicture()의 원본 파일을 그대로 사용한다.
                    _buildPreviousPhotoGuide(
                      previousPhotoGuideAsync,
                      direction,
                    ),
                    if (gridSettings != null)
                      GridOverlay(settings: gridSettings),
                  ],
                ),
              );
            },
          ),
        ),
        const Positioned(
          bottom: 4,
          right: 4,
          child: AsyncStatusIndicator(
            statusId: 'screen.capture.camera.status',
            status: AsyncStatus.success,
          ),
        ),
      ],
    ),
  };

  Widget _buildPreviousPhotoGuide(
    AsyncValue<String?> guideAsync,
    BodyDirection direction,
  ) {
    final path = guideAsync.asData?.value;
    if (!_showPreviousPhotoGuide ||
        path == null ||
        path == _failedPreviousPhotoGuidePath) {
      return const SizedBox.shrink();
    }

    return Semantics(
      identifier: 'capture.previousGuide.image',
      image: true,
      label: '${direction.label} 이전 사진 반투명 가이드',
      child: IgnorePointer(
        child: Opacity(
          opacity: _previousPhotoGuideOpacity,
          child: Image.file(
            File(path),
            key: ValueKey('capture.previousGuide.image.$path'),
            fit: BoxFit.contain,
            gaplessPlayback: false,
            errorBuilder: (context, error, stackTrace) {
              _markPreviousPhotoGuideFailed(path);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }

  void _markPreviousPhotoGuideFailed(String path) {
    if (_failedPreviousPhotoGuidePath == path) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _failedPreviousPhotoGuidePath == path) return;
      setState(() => _failedPreviousPhotoGuidePath = path);
    });
  }

  Widget _buildPreviousPhotoGuideControls(AsyncValue<String?> guideAsync) {
    final path = guideAsync.asData?.value;
    final imageFailed = path != null && path == _failedPreviousPhotoGuidePath;
    final hasGuide = path != null && !imageFailed;
    final effectiveVisible = hasGuide && _showPreviousPhotoGuide;
    final status = guideAsync.when(
      data: (value) {
        if (value == null) return '표시할 이전 사진이 없습니다.';
        if (imageFailed) return '이전 사진 파일을 표시할 수 없습니다.';
        return effectiveVisible ? '이전 사진 가이드 표시 중' : '이전 사진 가이드 꺼짐';
      },
      loading: () => '이전 사진을 확인하는 중입니다.',
      error: (error, stackTrace) => '이전 사진을 불러오지 못했습니다.',
    );

    return Padding(
      key: const ValueKey('capture.previousGuide.controls'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sp4,
        0,
        AppSpacing.sp4,
        AppSpacing.sp2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Semantics(
                identifier: 'capture.previousGuide.toggle',
                label: '이전 사진 가이드 표시',
                enabled: hasGuide,
                toggled: effectiveVisible,
                child: Switch(
                  key: const ValueKey('capture.previousGuide.toggle'),
                  value: effectiveVisible,
                  onChanged: hasGuide
                      ? (value) =>
                            setState(() => _showPreviousPhotoGuide = value)
                      : null,
                ),
              ),
              const SizedBox(width: AppSpacing.sp1),
              Text(
                '이전 사진',
                style: TextStyle(
                  color: context.photoColors.onChrome,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: AppSpacing.sp1),
              Expanded(
                child: Semantics(
                  identifier: 'capture.previousGuide.opacity.slider',
                  label: '이전 사진 가이드 농도',
                  value: '${(_previousPhotoGuideOpacity * 100).round()}%',
                  enabled: hasGuide,
                  child: Slider(
                    key: const ValueKey('capture.previousGuide.opacity.slider'),
                    value: _previousPhotoGuideOpacity,
                    min: 0.1,
                    max: 0.7,
                    divisions: 12,
                    onChanged: hasGuide
                        ? (value) =>
                              setState(() => _previousPhotoGuideOpacity = value)
                        : null,
                  ),
                ),
              ),
            ],
          ),
          Semantics(
            identifier: 'capture.previousGuide.status',
            label: '이전 사진 가이드 상태',
            value: status,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                status,
                style: TextStyle(
                  color: context.photoColors.onChrome.withValues(alpha: 0.7),
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(CaptureSessionState session) {
    return Row(
      children: [
        Semantics(
          identifier: 'capture.grid.settings.button',
          button: true,
          label: '빠른 설정 패널 열기/닫기',
          selected: _showQuickPanel,
          child: IconButton(
            key: const ValueKey('capture.grid.settings.button'),
            onPressed: () => setState(() => _showQuickPanel = !_showQuickPanel),
            icon: Icon(Icons.tune, color: context.photoColors.onChrome),
          ),
        ),
        // 진행 칩은 상단 바 안에 머물러야 한다. 좁은 화면에서는 남는 폭만
        // 차지하고 CaptureProgressBar가 FittedBox로 축소한다.
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sp1,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: context.photoColors.chrome,
              borderRadius: AppRadius.smAll,
            ),
            child: CaptureProgressBar(
              shots: session.shots,
              currentIndex: session.currentIndex,
              foreground: context.photoColors.onChrome,
              onStepSelected: (index) =>
                  ref.read(captureSessionProvider.notifier).goTo(index),
            ),
          ),
        ),
        _buildTimerButton(),
        _buildLensButton(),
      ],
    );
  }

  Widget _buildTimerButton() {
    final on = _timerSeconds > 0;
    return Semantics(
      identifier: 'capture.timer.button',
      button: true,
      label: '셀프 타이머',
      value: on ? '$_timerSeconds초' : '끔',
      child: IconButton(
        key: const ValueKey('capture.timer.button'),
        onPressed: _cycleTimer,
        tooltip: on ? '셀프 타이머 $_timerSeconds초' : '셀프 타이머 끔',
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              on ? Icons.timer : Icons.timer_off_outlined,
              color: context.photoColors.onChrome,
            ),
            if (on)
              Positioned(
                right: -6,
                top: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  constraints: const BoxConstraints(minWidth: 14),
                  decoration: BoxDecoration(
                    color: context.photoColors.onChrome,
                    borderRadius: AppRadius.xsAll,
                  ),
                  child: Text(
                    '$_timerSeconds',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.photoColors.backdrop,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLensButton() {
    // 전면·후면이 모두 있는 기기에서만 의미가 있는 버튼이다.
    if (!_controller.canSwitchLens) return const SizedBox.shrink();
    return Semantics(
      identifier: 'capture.lens.button',
      button: true,
      label: '전면/후면 카메라 전환',
      value: _useFrontLens ? '전면' : '후면',
      child: IconButton(
        key: const ValueKey('capture.lens.button'),
        onPressed: _onLensSwitch,
        tooltip: _useFrontLens ? '후면 카메라로' : '전면 카메라로',
        icon: Icon(
          Icons.cameraswitch_outlined,
          color: context.photoColors.onChrome,
        ),
      ),
    );
  }

  Widget _buildAssistPanel(BodyDirection direction) {
    final messages = captureGuideMessages(direction);
    return Semantics(
      identifier: 'capture.assist.panel',
      label: '촬영 보조 안내',
      child: Container(
        key: const ValueKey('capture.assist.panel'),
        padding: const EdgeInsets.all(AppSpacing.sp3),
        decoration: BoxDecoration(
          color: context.photoColors.chrome,
          borderRadius: AppRadius.smAll,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: messages
              .map(
                (m) => Text(
                  m,
                  style: TextStyle(
                    color: context.photoColors.onChrome,
                    fontSize: 12,
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  /// 뷰파인더를 절반만 덮는 빠른 설정 패널.
  ///
  /// 조작은 저장/취소 없이 즉시 반영된다. 격자는 [GridSettingsPanel]이
  /// shared_preferences에 바로 영속화하고, 이전 사진 가이드는 세션 상태다.
  /// 사진 위 패널 안쪽의 색을 사진 서페이스 규칙에 맞춘다.
  ///
  /// `Theme()`만 감싸면 안 된다. 색 스킴은 바뀌지만 스타일을 명시하지 않은 [Text]는
  /// 이미 [Scaffold]의 [Material]이 바깥 테마(라이트)로 설정해 둔 [DefaultTextStyle]을
  /// 그대로 물려받아 어두운 글자로 그려진다. 그래서 텍스트·아이콘 색을 여기서
  /// 직접 덮어쓴다. 컨트롤도 브랜드 색이 아니라 고정 흰색을 쓴다.
  Widget _photoSurfaceStyling({required Widget child}) {
    final photo = context.photoColors;
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.dark(
          primary: photo.onChrome,
          onPrimary: photo.backdrop,
          secondary: photo.onChrome,
          surface: Colors.transparent,
          onSurface: photo.onChrome,
          onSurfaceVariant: photo.onChrome,
          outline: photo.controlOutline,
        ),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: photo.onChrome),
        child: IconTheme.merge(
          data: IconThemeData(color: photo.onChrome),
          child: child,
        ),
      ),
    );
  }

  Widget _buildQuickPanel(AsyncValue<String?> guideAsync) {
    return Semantics(
      identifier: 'capture.quick.panel',
      label: '빠른 설정',
      // 뷰파인더가 절반 이상 가려지면 구도를 잡을 수 없다.
      child: ConstrainedBox(
        key: const ValueKey('capture.quick.panel'),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.5,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.photoColors.panel,
            borderRadius: AppRadius.mdAll,
          ),
          child: _photoSurfaceStyling(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const GridSettingsPanel(),
                  Divider(height: 1, color: context.photoColors.controlOutline),
                  _buildPreviousPhotoGuideControls(guideAsync),
                  Divider(height: 1, color: context.photoColors.controlOutline),
                  Semantics(
                    identifier: 'capture.settings.link',
                    button: true,
                    label: '전체 설정 열기',
                    // 패널 배경은 DecoratedBox가 그리므로 ListTile에 자기
                    // Material을 준다. 없으면 잉크 스플래시가 배경에 가려진다.
                    child: Material(
                      type: MaterialType.transparency,
                      child: ListTile(
                        key: const ValueKey('capture.settings.link'),
                        onTap: _openSettings,
                        leading: Icon(
                          Icons.settings_outlined,
                          color: context.photoColors.onChrome,
                        ),
                        title: Text(
                          '전체 설정',
                          style: TextStyle(color: context.photoColors.onChrome),
                        ),
                        trailing: Icon(
                          Icons.chevron_right,
                          color: context.photoColors.onChrome,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCountdownOverlay(int remaining) {
    return Semantics(
      identifier: 'capture.countdown',
      button: true,
      liveRegion: true,
      label: '셀프 타이머 카운트다운, 탭하면 취소합니다',
      value: '$remaining초',
      child: GestureDetector(
        key: const ValueKey('capture.countdown'),
        behavior: HitTestBehavior.opaque,
        onTap: _stopCountdown,
        child: ColoredBox(
          color: context.photoColors.chrome,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$remaining',
                  style: TextStyle(
                    color: context.photoColors.onChrome,
                    fontSize: 96,
                    height: 1,
                    fontWeight: FontWeight.w300,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: AppSpacing.sp2),
                Text(
                  '화면을 탭하면 취소됩니다',
                  style: TextStyle(
                    color: context.photoColors.onChrome,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(CaptureSessionState session) {
    final canLeaveStep = !_countingDown;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildRecordsButton(),
        _buildCompactAction(
          id: 'capture.skip.button',
          icon: Icons.skip_next,
          label: '건너뛰기',
          semanticsLabel: '이 방향 건너뛰기',
          onPressed: canLeaveStep ? _onSkip : null,
        ),
        _buildShutterButton(),
        _buildCompactAction(
          id: 'capture.finish.button',
          icon: Icons.check,
          label: '완료 (${session.capturedCount})',
          semanticsLabel: '촬영 마치고 확인',
          onPressed: session.hasAnyCapture && canLeaveStep ? _goToReview : null,
        ),
      ],
    );
  }

  /// 하단 바에 4개가 나란히 들어가므로 아이콘 + 짧은 라벨의 세로 버튼으로 만든다.
  Widget _buildCompactAction({
    required String id,
    required IconData icon,
    required String label,
    required String semanticsLabel,
    required VoidCallback? onPressed,
  }) {
    final enabled = onPressed != null;
    final color = enabled
        ? context.photoColors.onChrome
        : context.photoColors.onChrome.withValues(alpha: 0.38);
    return Semantics(
      identifier: id,
      button: true,
      enabled: enabled,
      label: semanticsLabel,
      child: TextButton(
        key: ValueKey(id),
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: const Size(52, AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp1),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(color: color, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  /// 최근 기록 썸네일 + 기록 건수 배지. 기록 화면으로 가는 유일한 입구다.
  Widget _buildRecordsButton() {
    const size = 52.0;
    final entries = ref.watch(timelineProvider).asData?.value;
    final recordCount = entries?.length ?? 0;
    final thumbnail = _latestThumbnail(entries);
    // 52dp 타일에 원본 풀사이즈를 디코딩하면 촬영 중 메모리가 급증한다.
    final cacheWidth = (size * MediaQuery.devicePixelRatioOf(context)).round();

    return Semantics(
      identifier: 'capture.records.button',
      button: true,
      label: recordCount > 0 ? '내 기록 보기, $recordCount건' : '내 기록 보기, 기록 없음',
      child: InkWell(
        key: const ValueKey('capture.records.button'),
        onTap: _openRecords,
        borderRadius: AppRadius.mdAll,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.photoColors.chrome,
                    borderRadius: AppRadius.mdAll,
                    border: Border.all(
                      color: context.photoColors.onChrome,
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: AppRadius.mdAll,
                    child: thumbnail == null
                        ? Center(
                            child: Icon(
                              Icons.photo_library_outlined,
                              size: 24,
                              color: context.photoColors.onChrome,
                            ),
                          )
                        : Image.file(
                            File(thumbnail.filePath),
                            fit: BoxFit.cover,
                            cacheWidth: cacheWidth,
                            errorBuilder: (_, _, _) => Center(
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                size: 20,
                                color: context.photoColors.onChrome,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              if (recordCount > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    constraints: const BoxConstraints(minWidth: 18),
                    decoration: BoxDecoration(
                      color: context.photoColors.onChrome,
                      borderRadius: AppRadius.fullAll,
                    ),
                    child: Text(
                      '$recordCount',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.photoColors.backdrop,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        height: 1.6,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 가장 최근 기록의 대표 사진. 가능하면 정면을 쓴다.
  BodyPhoto? _latestThumbnail(List<RecordWithPhotos>? entries) {
    if (entries == null || entries.isEmpty) return null;
    final photos = entries.first.orderedPhotos;
    if (photos.isEmpty) return null;
    return photos.firstWhere(
      (p) => p.direction == BodyDirection.front,
      orElse: () => photos.first,
    );
  }

  Widget _buildShutterButton() {
    final enabled =
        _status == _CameraStatus.ready && !_capturing && !_countingDown;
    return Semantics(
      identifier: 'capture.shutter.button',
      button: true,
      enabled: enabled,
      label: _timerSeconds > 0 ? '$_timerSeconds초 후 촬영' : '촬영',
      child: GestureDetector(
        key: const ValueKey('capture.shutter.button'),
        onTap: enabled ? _onShutterPressed : null,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled
                ? context.photoColors.onChrome
                : context.photoColors.onChrome.withValues(alpha: 0.38),
            border: Border.all(
              color: context.photoColors.onChrome.withValues(alpha: 0.54),
              width: 4,
            ),
          ),
          child: _capturing
              ? const Padding(
                  padding: EdgeInsets.all(22),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
      ),
    );
  }
}
