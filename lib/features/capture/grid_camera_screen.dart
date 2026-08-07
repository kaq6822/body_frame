import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/core/router/app_routes.dart';
import 'package:body_frame/core/services/app_logger.dart';
import 'camera/capture_camera_controller.dart';
import 'providers/capture_providers.dart';
import 'providers/capture_session_provider.dart';
import 'utils/capture_guides.dart';
import 'widgets/async_status_indicator.dart';
import 'widgets/capture_progress_bar.dart';
import 'widgets/grid_overlay.dart';
import 'widgets/grid_settings_panel.dart';

/// 연속 세션 촬영 화면.
///
/// 정면 → 좌측면 → 우측면 → 후면을 한 화면에서 이어 찍는다. 셔터를 누르면
/// 화면을 벗어나지 않고 다음 방향으로 자동 전환되고, 마지막 컷을 찍으면
/// 리뷰 화면으로 이동해 한 번에 저장한다.
///
/// 카메라 컨트롤러는 [captureCameraControllerFactoryProvider]로 주입한다.
/// 테스트에서는 `ProviderScope(overrides: [captureCameraControllerFactoryProvider
/// .overrideWithValue(() => FakeController())])`로 실기기 카메라 없이 검증한다.
class GridCameraScreen extends ConsumerStatefulWidget {
  static const screenId = 'screen.capture.camera';

  const GridCameraScreen({super.key});

  @override
  ConsumerState<GridCameraScreen> createState() => _GridCameraScreenState();
}

enum _CameraStatus { initializing, ready, error }

class _GridCameraScreenState extends ConsumerState<GridCameraScreen>
    with WidgetsBindingObserver {
  late final CaptureCameraController _controller;
  Future<void> _cameraOperations = Future<void>.value();
  _CameraStatus _status = _CameraStatus.initializing;
  bool _capturing = false;
  bool _showSettings = false;
  bool _cameraSuspended = false;
  bool _screenDisposed = false;
  bool _showPreviousPhotoGuide = true;
  double _previousPhotoGuideOpacity = 0.35;
  String? _failedPreviousPhotoGuidePath;

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
      await _controller.initialize();
      if (!mounted || _screenDisposed || _cameraSuspended) return;
      setState(() => _status = _CameraStatus.ready);
      logger.phase('capture.camera.init', LogPhase.success);
    } catch (_) {
      if (!mounted || _screenDisposed || _cameraSuspended) return;
      setState(() => _status = _CameraStatus.error);
      logger.phase('capture.camera.init', LogPhase.failure);
    }
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
      unawaited(_initCamera());
      return;
    }

    if (_cameraSuspended) return;
    _cameraSuspended = true;
    if (mounted) {
      setState(() => _status = _CameraStatus.initializing);
    }
    unawaited(_disposeCamera());
  }

  @override
  void dispose() {
    _screenDisposed = true;
    _cameraSuspended = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disposeCamera());
    super.dispose();
  }

  Future<void> _onShutterPressed() async {
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
      notifier.captureCurrent(path, gridSettings: grid);
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

  void _goToReview() {
    context.pushNamed(AppRoutes.captureReview);
  }

  void _onSkip() {
    final session = ref.read(captureSessionProvider);
    if (session.nextUncapturedIndex == null) {
      // 마지막 남은 단계를 건너뛰는 경우. 찍은 컷이 있으면 리뷰로 보낸다.
      if (session.hasAnyCapture) {
        _goToReview();
      } else {
        context.pop();
      }
      return;
    }
    ref.read(captureSessionProvider.notifier).skipCurrent();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(captureSessionProvider);
    final direction = session.current.direction;
    final gridAsync = ref.watch(gridSettingsControllerProvider);
    final previousPhotoGuideAsync = ref.watch(
      previousPhotoGuidePathProvider(direction),
    );

    return Semantics(
      identifier: GridCameraScreen.screenId,
      container: true,
      label: '연속 촬영',
      child: Scaffold(
        key: const ValueKey(GridCameraScreen.screenId),
        backgroundColor: Colors.black,
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
                top: 8,
                left: 8,
                right: 8,
                child: _buildTopBar(session),
              ),
              Positioned(
                top: 96,
                left: 8,
                right: 8,
                child: Align(
                  alignment: Alignment.topRight,
                  child: _buildPreviousPhotoGuideControls(
                    previousPhotoGuideAsync,
                  ),
                ),
              ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 100,
                child: _showSettings
                    ? _buildSettingsCard()
                    : _buildAssistPanel(direction),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: _buildBottomBar(session),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraArea(
    GridSettings? gridSettings,
    AsyncValue<String?> previousPhotoGuideAsync,
    BodyDirection direction,
  ) => switch (_status) {
    _CameraStatus.initializing => const Center(
      child: AsyncStatusIndicator(
        statusId: 'screen.capture.camera.status',
        status: AsyncStatus.busy,
        busyLabel: '카메라를 준비하는 중입니다.',
      ),
    ),
    _CameraStatus.error => Center(
      child: AsyncStatusIndicator(
        statusId: 'screen.capture.camera.status',
        status: AsyncStatus.failure,
        failureMessage: '카메라를 사용할 수 없습니다. 권한을 확인해주세요.',
        onRetry: () => unawaited(_initCamera()),
      ),
    ),
    _CameraStatus.ready => Stack(
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: _controller.aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _controller.buildPreview(),
                // 이 레이어는 Flutter preview에만 그린다. 실제 촬영은
                // CameraController.takePicture()의 원본 파일을 그대로 사용한다.
                _buildPreviousPhotoGuide(previousPhotoGuideAsync, direction),
                if (gridSettings != null) GridOverlay(settings: gridSettings),
              ],
            ),
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

    return Container(
      key: const ValueKey('capture.previousGuide.controls'),
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(8),
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
              const SizedBox(width: 4),
              const Text(
                '이전 사진',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
              const SizedBox(width: 4),
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
                style: const TextStyle(color: Colors.white70, fontSize: 11),
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
          identifier: 'capture.camera.back.button',
          button: true,
          label: '뒤로 가기',
          child: IconButton(
            key: const ValueKey('capture.camera.back.button'),
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(8),
            ),
            child: CaptureProgressBar(
              shots: session.shots,
              currentIndex: session.currentIndex,
              onStepSelected: (index) =>
                  ref.read(captureSessionProvider.notifier).goTo(index),
            ),
          ),
        ),
        Semantics(
          identifier: 'capture.grid.settings.button',
          button: true,
          label: '격자 설정 패널 열기/닫기',
          selected: _showSettings,
          child: IconButton(
            key: const ValueKey('capture.grid.settings.button'),
            onPressed: () => setState(() => _showSettings = !_showSettings),
            icon: const Icon(Icons.tune, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildAssistPanel(BodyDirection direction) {
    final messages = captureGuideMessages(direction);
    return Semantics(
      identifier: 'capture.assist.panel',
      label: '촬영 보조 안내',
      child: Container(
        key: const ValueKey('capture.assist.panel'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: messages
              .map(
                (m) => Text(
                  m,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _buildSettingsCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Theme(
        data: ThemeData.dark(useMaterial3: true),
        child: const GridSettingsPanel(),
      ),
    );
  }

  Widget _buildBottomBar(CaptureSessionState session) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Semantics(
          identifier: 'capture.skip.button',
          button: true,
          label: '이 방향 건너뛰기',
          child: TextButton(
            key: const ValueKey('capture.skip.button'),
            onPressed: _onSkip,
            child: const Text('건너뛰기', style: TextStyle(color: Colors.white)),
          ),
        ),
        _buildShutterButton(),
        Semantics(
          identifier: 'capture.finish.button',
          button: true,
          enabled: session.hasAnyCapture,
          label: '촬영 마치고 확인',
          child: TextButton(
            key: const ValueKey('capture.finish.button'),
            onPressed: session.hasAnyCapture ? _goToReview : null,
            child: Text(
              '완료 (${session.capturedCount})',
              style: TextStyle(
                color: session.hasAnyCapture ? Colors.white : Colors.white38,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShutterButton() {
    final enabled = _status == _CameraStatus.ready && !_capturing;
    return Semantics(
      identifier: 'capture.shutter.button',
      button: true,
      enabled: enabled,
      label: '촬영',
      child: GestureDetector(
        key: const ValueKey('capture.shutter.button'),
        onTap: enabled ? _onShutterPressed : null,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled ? Colors.white : Colors.white38,
            border: Border.all(color: Colors.white54, width: 4),
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
