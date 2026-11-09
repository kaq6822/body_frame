import 'dart:async';
import 'dart:io';

import '../members/member_providers.dart';
import '../../core/services/photo_storage_service.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:bodymark/core/models/models.dart';
import 'package:bodymark/core/photo_frame.dart';
import 'package:bodymark/core/providers.dart';
import 'package:bodymark/core/router/app_routes.dart';
import 'package:bodymark/core/services/app_logger.dart';
import 'package:bodymark/core/theme/app_tokens.dart';
import 'package:bodymark/features/records/providers/records_providers.dart';
import 'package:bodymark/features/settings/providers/settings_providers.dart';
import 'camera/capture_camera_controller.dart';
import 'camera_permission_guide.dart';
import 'providers/capture_providers.dart';
import 'providers/capture_session_provider.dart';
import 'utils/capture_guides.dart';
import 'utils/temporary_capture.dart';
import 'package:bodymark/core/widgets/async_status_indicator.dart';
import 'widgets/camera_notice_card.dart';
import 'widgets/capture_progress_bar.dart';
import 'widgets/grid_overlay.dart';
import 'widgets/grid_settings_panel.dart';
import 'widgets/frame_reference_lines.dart';
import 'widgets/level_indicator.dart';
import 'level/level_meter.dart';
import 'package:bodymark/core/widgets/status_pill.dart';

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
  bool _returnedDraft = false;
  bool _lessonCapture = false;
  List<CaptureShot> _draftShots = [];
  late final PhotoStorageService _draftStorage;
  late final AppLogger _draftLogger;

  bool _showQuickPanel = false;
  final ScrollController _quickPanelScroll = ScrollController();
  bool _cameraSuspended = false;
  bool _screenDisposed = false;

  /// 마지막 초기화가 권한 때문에 막혔는지.
  ///
  /// 화면 상태와 따로 둔다. 권한 창이 떠 있는 동안에는 앱이 정지 상태여서
  /// 실패를 화면에 반영하지 못하는데, 그 사실을 잊으면 복귀 직후 같은 초기화를
  /// 다시 시도해 무한히 반복된다.
  bool _permissionDenied = false;

  bool _showPreviousPhotoGuide = true;
  double _previousPhotoGuideOpacity = 0.3;
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
    _draftStorage = ref.read(photoStorageServiceProvider);
    _draftLogger = ref.read(appLoggerProvider);
    _lessonCapture = ref.read(lessonCaptureContextProvider) != null;
    ref.listenManual(
      captureSessionProvider,
      (_, next) => _draftShots = next.capturedShots,
      fireImmediately: true,
    );
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
    _showPreviousPhotoGuide = options.previousGuide;
    _previousPhotoGuideOpacity = options.guideOpacity;
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

  /// 복귀 시 재초기화. 거부 여부는 큐에서 차례가 왔을 때 다시 확인한다.
  ///
  /// 권한 창이 떠 있는 동안에는 초기화가 아직 끝나지 않았다. 거부하면 resumed가
  /// 그 실패보다 먼저 도착하므로, 큐에 넣는 시점에는 거부를 알 수 없다. 앞선
  /// 초기화가 실패를 기록한 뒤에 판단해야 방금 거부한 권한을 다시 요청하지 않는다.
  Future<void> _resumeCameraNow() async {
    if (_permissionDenied) {
      if (mounted && !_screenDisposed && !_cameraSuspended) {
        setState(() => _status = _CameraStatus.permissionDenied);
      }
      return;
    }
    await _initCameraNow();
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
      unawaited(_enqueueCameraOperation(_resumeCameraNow));
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
    _quickPanelScroll.dispose();
    if (_lessonCapture && !_returnedDraft) {
      for (final shot in _draftShots) {
        unawaited(
          deleteTemporaryCaptureBestEffort(
            shot.imagePath!,
            storage: _draftStorage,
            logger: _draftLogger,
          ),
        );
      }
    }
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
      final replaced = notifier.captureCurrent(
        path,
        gridSettings: grid,
        capturedAt: ref.read(clockProvider)(),
      );
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
        ).showSnackBar(const SnackBar(content: Text('촬영하지 못했어요. 다시 시도해주세요.')));
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  // --- 이동 ---

  Future<void> _goToReview() async {
    _stopCountdown();
    final result = await context.pushNamed<List<CaptureShot>>(
      AppRoutes.captureReview,
    );
    if (mounted &&
        result != null &&
        ref.read(lessonCaptureContextProvider) != null) {
      _returnedDraft = true;
      context.pop(result);
    }
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
        // 찍은 컷 없이 끝냈다. 레슨 촬영이면 일지로, 단독 촬영이면 기록으로 간다.
        if (ref.read(lessonCaptureContextProvider) != null) {
          context.pop();
        } else {
          _openRecords();
        }
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
    final ready = _status == _CameraStatus.ready;
    // 권한·오류 안내는 전용 화면처럼 보여준다. 쓸 수 없는 방향 탭·셔터를 함께
    // 늘어놓으면 무엇을 해야 하는지 흐려진다.
    final blocked =
        _status == _CameraStatus.permissionDenied ||
        _status == _CameraStatus.error;

    return Semantics(
      identifier: GridCameraScreen.screenId,
      container: true,
      label: '연속 촬영',
      // 열려 있는 임시 UI(패널·카운트다운)를 뒤로가기로 먼저 거둔다.
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
          backgroundColor: context.photoColors.viewfinder,
          body: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    _buildHeader(),
                    if (!blocked)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.sp2,
                          0,
                          AppSpacing.sp2,
                          AppSpacing.sp2,
                        ),
                        child: CaptureProgressBar(
                          shots: session.shots,
                          currentIndex: session.currentIndex,
                          onStepSelected: (index) => ref
                              .read(captureSessionProvider.notifier)
                              .goTo(index),
                        ),
                      ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) => Stack(
                          children: [
                            Positioned.fill(
                              child: _buildCameraArea(
                                gridAsync.value,
                                previousPhotoGuideAsync,
                                direction,
                              ),
                            ),
                            // 빠른 설정은 미리보기 위에 겹치는 시트다. 패널을 열어도
                            // 미리보기 크기(3:4 contain)는 바뀌지 않는다.
                            if (_showQuickPanel)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: _buildQuickPanel(
                                  previousPhotoGuideAsync,
                                  maxHeight: constraints.maxHeight * 0.7,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (ready) _buildHint(direction),
                    if (!blocked)
                      _buildToggleChips(
                        gridAsync.value,
                        previousPhotoGuideAsync,
                      ),
                    if (!blocked)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.sp4,
                          AppSpacing.sp2,
                          AppSpacing.sp4,
                          AppSpacing.sp3,
                        ),
                        child: _buildBottomBar(session),
                      ),
                  ],
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

  bool get _isLessonCapture => ref.watch(lessonCaptureContextProvider) != null;

  /// HUD 헤더: [닫기 | 기록] [회원 · 기준 2줄] [타이머][렌즈].
  Widget _buildHeader() {
    final photo = context.photoColors;
    final info = ref.watch(cameraHeaderInfoProvider).valueOrNull;
    final title = info?.title ?? '체형 사진 촬영';
    final subtitle = info?.subtitle;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp1,
        vertical: AppSpacing.sp1,
      ),
      child: Row(
        children: [
          if (_isLessonCapture)
            Semantics(
              identifier: 'capture.close.button',
              button: true,
              label: '촬영을 닫고 일지로 돌아가기',
              child: IconButton(
                key: const ValueKey('capture.close.button'),
                onPressed: () => context.pop(),
                icon: Icon(Icons.close, color: photo.onChrome),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sp1),
              child: _buildRecordsButton(),
            ),
          Expanded(
            child: Semantics(
              identifier: 'capture.header',
              container: true,
              child: Column(
                key: const ValueKey('capture.header'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: context.texts.titleMedium?.copyWith(
                      color: photo.onChrome,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: context.numericTexts.labelLarge.copyWith(
                        fontWeight: FontWeight.w500,
                        color: info!.hasBaseline
                            ? photo.measure
                            : photo.onChrome.withValues(alpha: 0.72),
                      ),
                    ),
                ],
              ),
            ),
          ),
          _buildTimerButton(),
          _buildLensButton(),
        ],
      ),
    );
  }

  /// 셔터 위 한 줄 안내. 자세한 내용은 촬영 가이드 화면에 있다.
  Widget _buildHint(BodyDirection direction) {
    final hint = captureHint(direction);
    return Semantics(
      identifier: 'capture.assist.panel',
      label: '촬영 보조 안내',
      value: hint,
      child: Padding(
        key: const ValueKey('capture.assist.panel'),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sp4,
          AppSpacing.sp2,
          AppSpacing.sp4,
          0,
        ),
        child: ExcludeSemantics(
          child: Text(
            hint,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: context.texts.bodyMedium?.copyWith(
              color: context.photoColors.onChrome,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  /// 격자·이전 사진 상태 칩과 빠른 설정 버튼.
  Widget _buildToggleChips(GridSettings? grid, AsyncValue<String?> guideAsync) {
    final path = guideAsync.asData?.value;
    final hasGuide = path != null && path != _failedPreviousPhotoGuidePath;
    final guideOn = hasGuide && _showPreviousPhotoGuide;
    final gridOn = grid?.visible ?? false;
    final percent = (_previousPhotoGuideOpacity * 100).round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sp4,
        AppSpacing.sp2,
        AppSpacing.sp4,
        0,
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: AppSpacing.sp2,
        runSpacing: AppSpacing.sp2,
        children: [
          _HudChip(
            id: 'capture.grid.chip',
            icon: Icons.grid_on,
            label: gridOn ? '격자 켜짐' : '격자 꺼짐',
            active: gridOn,
            semanticsLabel: '격자 표시',
            toggled: gridOn,
            onPressed: grid == null
                ? null
                : () => ref
                      .read(gridSettingsControllerProvider.notifier)
                      .update((s) => s.copyWith(visible: !s.visible)),
          ),
          _HudChip(
            id: 'capture.previousGuide.chip',
            icon: Icons.layers_outlined,
            label: !hasGuide
                ? '이전 사진 없음'
                : guideOn
                ? '이전 사진 켜짐 ($percent%)'
                : '이전 사진 꺼짐',
            active: guideOn,
            semanticsLabel: '이전 사진 표시 설정 열기',
            onPressed: () => setState(() => _showQuickPanel = true),
          ),
          _HudChip(
            id: 'capture.grid.settings.button',
            icon: Icons.tune,
            label: '설정',
            active: _showQuickPanel,
            semanticsLabel: '빠른 설정 패널 열기/닫기',
            onPressed: () => setState(() => _showQuickPanel = !_showQuickPanel),
          ),
        ],
      ),
    );
  }

  /// 안내 카드를 미리보기 자리 가운데 놓는다.
  ///
  /// 세로가 짧은 기기에서는 카드가 영역보다 높을 수 있다. 그때 잘려 버리면 재시도
  /// 버튼에 손이 닿지 않으므로 스크롤로 접근하게 한다.
  Widget _noticeArea(Widget card) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.sp4),
      child: card,
    ),
  );

  /// 카메라를 쓸 수 없을 때의 대체 동선.
  ///
  /// 레슨 촬영 중이면 일지로 돌아가게 하고(작성 내용은 일지 화면에 남아 있다),
  /// 단독 촬영이면 회원 기록을 보게 한다. 카드가 밝으므로 테마 기본 색을 쓴다.
  Widget _buildFallbackAction() {
    if (_isLessonCapture) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            identifier: 'capture.camera.lesson.back.button',
            button: true,
            label: '일지로 돌아가기',
            child: TextButton.icon(
              key: const ValueKey('capture.camera.lesson.back.button'),
              onPressed: () => context.pop(),
              icon: const Icon(Icons.edit_note_outlined),
              label: const Text('일지로 돌아가기'),
            ),
          ),
          Text(
            '입력 중인 레슨 일지 내용은 그대로 남아 있어요.',
            textAlign: TextAlign.center,
            style: context.texts.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      );
    }
    return Semantics(
      identifier: 'capture.camera.records.fallback.button',
      button: true,
      label: '회원 기록 보기',
      child: TextButton.icon(
        key: const ValueKey('capture.camera.records.fallback.button'),
        onPressed: _openRecords,
        icon: const Icon(Icons.photo_library_outlined),
        label: const Text('회원 기록 보기'),
      ),
    );
  }

  Widget _buildCameraArea(
    GridSettings? gridSettings,
    AsyncValue<String?> previousPhotoGuideAsync,
    BodyDirection direction,
  ) => switch (_status) {
    _CameraStatus.initializing => _noticeArea(
      const CameraNoticeCard(
        statusId: 'screen.capture.camera.status',
        tone: CameraNoticeTone.busy,
        title: '카메라를 준비하고 있어요.',
      ),
    ),
    // 카메라를 못 쓰면 재시도와 함께 빠져나가는 대체 동선을 항상 남긴다.
    _CameraStatus.error => _noticeArea(
      CameraNoticeCard(
        statusId: 'screen.capture.camera.status',
        tone: CameraNoticeTone.failure,
        title: '카메라를 사용할 수 없어요.',
        description: '다시 시도해도 열리지 않으면 앱을 다시 실행해보세요.',
        onRetry: _retryCamera,
        secondaryAction: _buildFallbackAction(),
      ),
    ),
    // 권한이 없으면 재시도해도 같은 거부가 돌아온다. 설정으로 곧바로 보내고,
    // 재시도는 권한을 켜고 돌아온 뒤 사용자가 직접 누르게 한다.
    _CameraStatus.permissionDenied => _noticeArea(
      CameraNoticeCard(
        statusId: 'screen.capture.camera.status',
        tone: CameraNoticeTone.actionNeeded,
        title: '카메라 권한이 필요해요.',
        description: '촬영을 시작하려면 카메라 접근을 허용해주세요.',
        onOpenSettings: _openAppSettings,
        onRetry: _retryCamera,
        secondaryAction: _buildFallbackAction(),
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
                    // 아래 레이어는 Flutter preview에만 그린다. 실제 촬영은
                    // CameraController.takePicture()의 원본 파일을 그대로 사용한다.
                    _buildPreviousPhotoGuide(
                      previousPhotoGuideAsync,
                      direction,
                    ),
                    if (gridSettings != null)
                      GridOverlay(settings: gridSettings),
                    if (gridSettings?.visible ?? false)
                      const FrameReferenceLines(),
                    // 센서가 없거나 실패하면 지표가 숨는다. 촬영은 막지 않는다.
                    if (_showLevel) const _LevelOverlay(),
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

  bool get _showLevel =>
      ref.watch(appSettingsControllerProvider).valueOrNull?.capture.showLevel ??
      CaptureOptions.defaults.showLevel;

  void _setShowLevel(bool value) {
    unawaited(
      ref
          .read(appSettingsControllerProvider.notifier)
          .updateSettings(
            (s) => s.copyWith(capture: s.capture.copyWith(showLevel: value)),
          ),
    );
  }

  Widget _buildPreviousPhotoGuideControls(AsyncValue<String?> guideAsync) {
    final photo = context.photoColors;
    final path = guideAsync.asData?.value;
    final imageFailed = path != null && path == _failedPreviousPhotoGuidePath;
    final hasGuide = path != null && !imageFailed;
    final effectiveVisible = hasGuide && _showPreviousPhotoGuide;
    final status = guideAsync.when(
      data: (value) {
        if (value == null) return '표시할 이전 사진이 없어요.';
        if (imageFailed) return '이전 사진 파일을 표시할 수 없어요.';
        return effectiveVisible ? '이전 사진 가이드 표시 중' : '이전 사진 가이드 꺼짐';
      },
      loading: () => '이전 사진을 확인하고 있어요.',
      error: (error, stackTrace) => '이전 사진을 불러오지 못했어요.',
    );
    final percent = (_previousPhotoGuideOpacity * 100).round();
    final caption = context.texts.bodySmall?.copyWith(
      color: photo.onChrome.withValues(alpha: 0.72),
    );

    return Padding(
      key: const ValueKey('capture.previousGuide.controls'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sp4,
        0,
        AppSpacing.sp4,
        AppSpacing.sp3,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sp2),
            decoration: BoxDecoration(
              color: photo.viewfinder.withValues(alpha: 0.6),
              borderRadius: AppRadius.mdAll,
              border: Border.all(color: photo.hudOutline),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: AppRadius.smAll,
                  child: SizedBox(
                    width: 36,
                    height: 48,
                    child: ColoredBox(
                      color: photo.backdrop,
                      child: hasGuide
                          ? Image.file(
                              File(path),
                              fit: BoxFit.contain,
                              cacheWidth: 120,
                              errorBuilder: (_, _, _) => const SizedBox(),
                            )
                          : Icon(
                              Icons.hide_image_outlined,
                              size: 18,
                              color: photo.onChrome.withValues(alpha: 0.6),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sp3),
                Expanded(
                  child: Semantics(
                    identifier: 'capture.previousGuide.status',
                    label: '이전 사진 가이드 상태',
                    value: status,
                    child: ExcludeSemantics(
                      child: Text(
                        status,
                        style: context.texts.bodyMedium?.copyWith(
                          color: photo.onChrome,
                        ),
                      ),
                    ),
                  ),
                ),
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
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sp3),
          Row(
            children: [
              Expanded(
                child: Text(
                  '이전 사진 진하기',
                  style: context.texts.bodyMedium?.copyWith(
                    color: photo.onChrome,
                  ),
                ),
              ),
              ExcludeSemantics(
                child: Text(
                  '$percent%',
                  style: context.numericTexts.labelLarge.copyWith(
                    color: photo.measure,
                  ),
                ),
              ),
            ],
          ),
          Semantics(
            identifier: 'capture.previousGuide.opacity.slider',
            label: '이전 사진 가이드 농도',
            enabled: hasGuide,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: photo.measure,
                thumbColor: photo.measure,
                inactiveTrackColor: photo.controlTrack,
              ),
              child: Slider(
                semanticFormatterCallback: (v) => '${(v * 100).round()}%',
                key: const ValueKey('capture.previousGuide.opacity.slider'),
                value: _previousPhotoGuideOpacity.clamp(0.0, 1.0),
                min: 0,
                max: 1,
                divisions: 20,
                onChanged: hasGuide
                    ? (value) =>
                          setState(() => _previousPhotoGuideOpacity = value)
                    : null,
              ),
            ),
          ),
          ExcludeSemantics(
            // 좁은 화면·큰 글꼴에서도 넘치지 않게 세 칸을 나눠 줄바꿈한다.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text('0%', style: caption)),
                Expanded(
                  flex: 2,
                  child: Text(
                    '권장 30%',
                    style: caption,
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: Text('100%', style: caption, textAlign: TextAlign.end),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelToggle() {
    final on = _showLevel;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '수평계 표시',
                  style: context.texts.bodyMedium?.copyWith(
                    color: context.photoColors.onChrome,
                  ),
                ),
                Text(
                  '센서가 없는 기기에서는 보이지 않아요.',
                  style: context.texts.bodySmall?.copyWith(
                    color: context.photoColors.onChrome.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
          Semantics(
            identifier: 'capture.level.toggle',
            label: '수평계 표시',
            toggled: on,
            child: Switch(
              key: const ValueKey('capture.level.toggle'),
              value: on,
              onChanged: _setShowLevel,
            ),
          ),
        ],
      ),
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

  /// 미리보기 아래쪽에 겹치는 빠른 설정 시트(HUD 표면).
  ///
  /// 레이아웃을 밀어내지 않고 겹치므로 열어도 미리보기 크기가 그대로다. 높이는
  /// 미리보기 영역의 [maxHeight]까지이고 넘치면 안쪽에서 스크롤한다. 이전 사진
  /// 설정을 맨 위에 둬 열자마자 보이게 한다. 조작은 즉시 반영된다. 격자는
  /// [GridSettingsPanel]이 바로 영속화하고, 수평계 표시는 촬영 설정에 저장하며,
  /// 이전 사진 가이드는 세션 상태다.
  Widget _buildQuickPanel(
    AsyncValue<String?> guideAsync, {
    required double maxHeight,
  }) {
    final photo = context.photoColors;
    return Semantics(
      identifier: 'capture.quick.panel',
      label: '빠른 설정',
      child: ConstrainedBox(
        key: const ValueKey('capture.quick.panel'),
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: photo.panel,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.lg),
            ),
            border: Border(top: BorderSide(color: photo.hudOutline)),
          ),
          child: _photoSurfaceStyling(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildQuickPanelHeader(),
                Flexible(
                  child: Scrollbar(
                    controller: _quickPanelScroll,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _quickPanelScroll,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildPreviousPhotoGuideControls(guideAsync),
                          Divider(height: 1, color: photo.hudOutline),
                          const SizedBox(height: AppSpacing.sp2),
                          _buildLevelToggle(),
                          const SizedBox(height: AppSpacing.sp2),
                          Divider(height: 1, color: photo.hudOutline),
                          const GridSettingsPanel(),
                          Divider(height: 1, color: photo.hudOutline),
                          _buildPanelLink(
                            id: 'capture.guide.link',
                            icon: Icons.help_outline,
                            label: '촬영 가이드',
                            onTap: _openGuide,
                          ),
                          _buildPanelLink(
                            id: 'capture.settings.link',
                            icon: Icons.settings_outlined,
                            label: '전체 설정',
                            semanticsLabel: '전체 설정 열기',
                            onTap: _openSettings,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPanelLink({
    required String id,
    required IconData icon,
    required String label,
    String? semanticsLabel,
    required VoidCallback onTap,
  }) {
    final onPhoto = context.photoColors.onChrome;
    return Semantics(
      identifier: id,
      button: true,
      label: semanticsLabel ?? label,
      // 패널 배경은 DecoratedBox가 그리므로 ListTile에 자기 Material을 준다.
      // 없으면 잉크 스플래시가 배경에 가려진다.
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          key: ValueKey(id),
          onTap: onTap,
          leading: Icon(icon, color: onPhoto),
          title: Text(label, style: TextStyle(color: onPhoto)),
          trailing: Icon(Icons.chevron_right, color: onPhoto),
        ),
      ),
    );
  }

  void _openGuide() {
    _stopCountdown();
    context.push('/capture-guide');
  }

  Widget _buildQuickPanelHeader() {
    final photo = context.photoColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sp4,
        AppSpacing.sp2,
        AppSpacing.sp2,
        AppSpacing.sp1,
      ),
      child: Row(
        children: [
          Icon(Icons.tune, size: 20, color: photo.measure),
          const SizedBox(width: AppSpacing.sp2),
          Expanded(
            child: Text(
              '촬영 보조 설정',
              style: context.texts.titleMedium?.copyWith(color: photo.onChrome),
            ),
          ),
          Semantics(
            identifier: 'capture.quick.panel.close.button',
            button: true,
            label: '촬영 보조 설정 닫기',
            child: TextButton.icon(
              key: const ValueKey('capture.quick.panel.close.button'),
              style: TextButton.styleFrom(
                foregroundColor: photo.onChrome,
                backgroundColor: photo.controlFill,
                shape: const StadiumBorder(),
                minimumSize: const Size(0, AppSpacing.minTouchTarget),
              ),
              onPressed: () => setState(() => _showQuickPanel = false),
              icon: const Icon(Icons.keyboard_arrow_down, size: 18),
              label: const Text('접기'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountdownOverlay(int remaining) {
    return Semantics(
      identifier: 'capture.countdown',
      button: true,
      liveRegion: true,
      label: '셀프 타이머 카운트다운, 탭하면 취소돼요',
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
                  '화면을 탭하면 취소돼요',
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

  /// 하단 조작: [건너뛰기] [셔터] [완료 n장]. 셔터가 주 동작이다.
  Widget _buildBottomBar(CaptureSessionState session) {
    final canLeaveStep = !_countingDown;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: _buildPillAction(
              id: 'capture.skip.button',
              label: '건너뛰기',
              semanticsLabel: '이 방향 건너뛰기',
              onPressed: canLeaveStep ? _onSkip : null,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp3),
          child: _buildShutterButton(),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: _buildPillAction(
              id: 'capture.finish.button',
              label: '완료 ${session.capturedCount}장',
              semanticsLabel: '촬영 마치고 확인, ${session.capturedCount}장',
              onPressed: session.hasAnyCapture && canLeaveStep
                  ? _goToReview
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  /// HUD 표면 위 알약 버튼. 글자가 길면 줄이지 않고 축소 배치한다.
  Widget _buildPillAction({
    required String id,
    required String label,
    required String semanticsLabel,
    required VoidCallback? onPressed,
  }) {
    final photo = context.photoColors;
    final enabled = onPressed != null;
    final color = enabled
        ? photo.onChrome
        : photo.onChrome.withValues(alpha: 0.38);
    return Semantics(
      identifier: id,
      button: true,
      enabled: enabled,
      label: semanticsLabel,
      excludeSemantics: true,
      child: TextButton(
        key: ValueKey(id),
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: color,
          backgroundColor: photo.hudSurface,
          disabledForegroundColor: color,
          minimumSize: const Size(
            AppSpacing.minTouchTarget,
            AppSpacing.minTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp4),
          shape: StadiumBorder(side: BorderSide(color: photo.hudOutline)),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: context.numericTexts.labelLarge.copyWith(color: color),
          ),
        ),
      ),
    );
  }

  /// 최근 기록 썸네일 + 기록 건수 배지(레슨 밖 단독 촬영일 때만).
  Widget _buildRecordsButton() {
    const size = 44.0;
    final entries = ref.watch(timelineProvider).asData?.value;
    final recordCount = entries?.length ?? 0;
    final thumbnail = _latestThumbnail(entries);
    // 작은 타일에 원본 풀사이즈를 디코딩하면 촬영 중 메모리가 급증한다.
    final cacheWidth = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final photo = context.photoColors;

    return Semantics(
      identifier: 'capture.records.button',
      button: true,
      label: recordCount > 0 ? '회원 기록 보기, $recordCount건' : '회원 기록 보기, 기록 없음',
      child: InkWell(
        key: const ValueKey('capture.records.button'),
        onTap: _openRecords,
        borderRadius: AppRadius.smAll,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: photo.hudSurface,
                    borderRadius: AppRadius.smAll,
                    border: Border.all(color: photo.hudOutline),
                  ),
                  child: ClipRRect(
                    borderRadius: AppRadius.smAll,
                    child: thumbnail == null
                        ? Center(
                            child: Icon(
                              Icons.photo_library_outlined,
                              size: 22,
                              color: photo.onChrome,
                            ),
                          )
                        : Image.file(
                            File(thumbnail.filePath),
                            fit: BoxFit.contain,
                            cacheWidth: cacheWidth,
                            errorBuilder: (_, _, _) => Center(
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                size: 20,
                                color: photo.onChrome,
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
                      color: photo.onChrome,
                      borderRadius: AppRadius.fullAll,
                    ),
                    child: Text(
                      '$recordCount',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: photo.backdrop,
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

  /// 동심원 셔터: 72dp 측정 시안 링 + 56dp 흰 원판.
  Widget _buildShutterButton() {
    final photo = context.photoColors;
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
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: enabled
                  ? photo.measure
                  : photo.onChrome.withValues(alpha: 0.38),
              width: 3,
            ),
          ),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled
                  ? photo.onChrome
                  : photo.onChrome.withValues(alpha: 0.38),
            ),
            child: _capturing
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: photo.viewfinder,
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

/// 수평계 오버레이. 판독값이 자주 바뀌므로 촬영 화면 전체가 아니라 이 위젯만
/// 다시 그린다. 센서가 없거나 오류면 아무것도 그리지 않는다.
///
/// 센서 구독은 이 위젯이 직접 잡고 놓는다. 가이드·설정이 위에 쌓여 이 라우트가
/// 현재 화면이 아니면 구독을 끊어 센서가 멈추고 보이지 않는 화면에서 햅틱이
/// 울리지 않는다. 화면이 회전하면 새 기준([ScreenFrame])으로 다시 구독한다.
class _LevelOverlay extends ConsumerStatefulWidget {
  const _LevelOverlay();

  @override
  ConsumerState<_LevelOverlay> createState() => _LevelOverlayState();
}

class _LevelOverlayState extends ConsumerState<_LevelOverlay> {
  StreamSubscription<LevelReading>? _subscription;
  ScreenFrame? _frame;
  LevelReading? _reading;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    final frame = MediaQuery.orientationOf(context) == Orientation.landscape
        ? ScreenFrame.landscape
        : ScreenFrame.portrait;
    if (!current) {
      _stop();
    } else if (_subscription == null || frame != _frame) {
      _start(frame);
    }
  }

  void _start(ScreenFrame frame) {
    _stop();
    _frame = frame;
    final stream = levelReadings(
      ref.read(levelSensorProvider).samples(),
      frame: frame,
      onLock: ref.read(levelLockFeedbackProvider),
    );
    _subscription = stream.listen(
      (reading) {
        if (mounted) setState(() => _reading = reading);
      },
      // 센서가 없거나 막히면 지표를 숨긴다. 촬영은 그대로다.
      onError: (Object _) {
        if (mounted) setState(() => _reading = null);
        _stop();
      },
    );
  }

  void _stop() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _reading = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reading = _reading;
    if (reading == null) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [
        LevelIndicator(reading: reading),
        if (reading.isLocked)
          const Positioned(
            top: AppSpacing.sp2,
            right: AppSpacing.sp2,
            child: StatusPill(
              identifier: 'capture.level.locked',
              label: '수평',
              tone: StatusPillTone.measure,
              icon: Icons.check,
            ),
          ),
      ],
    );
  }
}

/// 셔터 위 상태 칩(격자·이전 사진·설정). HUD 표면, 켜짐은 측정 시안 아이콘.
class _HudChip extends StatelessWidget {
  final String id;
  final IconData icon;
  final String label;
  final bool active;
  final String semanticsLabel;
  final bool? toggled;
  final VoidCallback? onPressed;

  const _HudChip({
    required this.id,
    required this.icon,
    required this.label,
    required this.active,
    required this.semanticsLabel,
    this.toggled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final photo = context.photoColors;
    return Semantics(
      identifier: id,
      button: true,
      enabled: onPressed != null,
      toggled: toggled,
      selected: toggled == null ? active : null,
      label: semanticsLabel,
      value: label,
      excludeSemantics: true,
      child: TextButton.icon(
        key: ValueKey(id),
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: photo.onChrome,
          disabledForegroundColor: photo.onChrome.withValues(alpha: 0.38),
          backgroundColor: photo.hudSurface,
          minimumSize: const Size(0, AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp3),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: StadiumBorder(
            side: BorderSide(color: active ? photo.measure : photo.hudOutline),
          ),
        ),
        icon: Icon(
          icon,
          size: 18,
          color: active ? photo.measure : photo.onChrome,
        ),
        // 테마 labelLarge에는 밝은 화면용 글자색이 들어 있어 foregroundColor를
        // 덮는다. HUD 위에서 보이도록 색을 직접 지정한다.
        label: Text(
          label,
          style: context.texts.labelLarge?.copyWith(
            color: onPressed == null
                ? photo.onChrome.withValues(alpha: 0.38)
                : photo.onChrome,
          ),
        ),
      ),
    );
  }
}
