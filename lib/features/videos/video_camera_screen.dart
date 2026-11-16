import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/korean_text.dart';
import '../../core/photo_frame.dart';
import '../../core/providers.dart';
import '../../core/services/app_logger.dart';
import '../../core/services/photo_storage_service.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_confirm_dialog.dart';
import '../capture/camera/capture_camera_controller.dart';
import '../capture/camera/video_camera_controller.dart';
import '../capture/camera_permission_guide.dart';
import '../capture/providers/capture_providers.dart';
import '../capture/utils/temporary_capture.dart';
import '../capture/widgets/camera_notice_card.dart';
import '../members/member_providers.dart';
import '../members/ui.dart' show mark;
import 'video_providers.dart';

/// 레슨 동영상 촬영 화면.
///
/// 한 번에 한 개를 녹화하고, 녹화본을 [RecordedVideo]로 레슨 편집에 돌려준다.
/// 시간 제한은 없고 녹화 중 경과 시간을 보여 준다. 사진 카메라처럼 세로로
/// 고정하고 미리보기는 잘라내지 않고(contain) 보여 준다.
class VideoCameraScreen extends ConsumerStatefulWidget {
  static const screenId = 'screen.video.camera';
  const VideoCameraScreen({super.key});

  @override
  ConsumerState<VideoCameraScreen> createState() => _VideoCameraScreenState();
}

enum _Status { initializing, ready, error, permissionDenied }

class _VideoCameraScreenState extends ConsumerState<VideoCameraScreen>
    with WidgetsBindingObserver {
  late final VideoCameraController _controller;
  late final PhotoStorageService _storage;
  late final AppLogger _logger;
  late final ScreenOrientationLock _orientationLock;

  /// dispose 뒤에도 정지 작업이 시각을 읽으므로 initState에서 잡아 둔다.
  late final DateTime Function() _clock;
  Future<void> _ops = Future<void>.value();
  _Status _status = _Status.initializing;
  bool _useFrontLens = false;
  bool _suspended = false;
  bool _disposed = false;
  bool _permissionDenied = false;
  bool _openedSettings = false;

  /// 이번 세션에 마이크가 거부됐는지. Android는 오디오를 켠 채 열 때마다 권한
  /// 창을 다시 띄우므로, 사용자가 설정을 다녀오기 전에는 다시 묻지 않는다.
  bool _micDenied = false;

  bool _recording = false;

  /// 녹화 시작·정지가 진행 중인지. 이 사이에 화면을 닫으면 녹화본이 남는다.
  bool _busy = false;
  DateTime? _startedAt;
  Timer? _ticker;

  /// 녹화를 마쳤지만 아직 편집 화면에 넘기지 않은 임시 녹화본.
  RecordedVideo? _result;
  bool _returned = false;
  String? _error;

  Duration get _elapsed {
    final started = _startedAt;
    if (started == null) return Duration.zero;
    final d = _clock().difference(started);
    return d.isNegative ? Duration.zero : d;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = ref.read(videoCameraControllerFactoryProvider)();
    _storage = ref.read(photoStorageServiceProvider);
    _logger = ref.read(appLoggerProvider);
    _clock = ref.read(clockProvider);
    _orientationLock = ref.read(screenOrientationLockProvider);
    unawaited(
      _orientationLock.lockPortrait().catchError((Object _) {
        _logger.warn('video.orientation.lock.failure');
      }),
    );
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _suspended = lifecycle == AppLifecycleState.paused;
    if (!_suspended) unawaited(_enqueue(_initNow));
  }

  Future<void> _enqueue(Future<void> Function() op) {
    final next = _ops.then((_) => op());
    _ops = next.catchError((Object _, StackTrace _) {});
    return next;
  }

  Future<void> _initNow() async {
    if (_disposed || _suspended) return;
    setState(() => _status = _Status.initializing);
    final tryAudio = !_micDenied;
    try {
      await _controller.initialize(
        useFrontLens: _useFrontLens,
        tryAudio: tryAudio,
      );
      _permissionDenied = false;
      if (tryAudio && !_controller.audioEnabled) _micDenied = true;
      if (!mounted || _disposed || _suspended) return;
      setState(() {
        _useFrontLens = _controller.isFrontLens;
        _status = _Status.ready;
      });
      _logger.phase('video.camera.init', LogPhase.success);
    } catch (error) {
      _permissionDenied = isCameraPermissionError(error);
      if (!mounted || _disposed || _suspended) return;
      setState(
        () => _status = _permissionDenied
            ? _Status.permissionDenied
            : _Status.error,
      );
      _logger.phase('video.camera.init', LogPhase.failure);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    if (state == AppLifecycleState.resumed) {
      if (!_suspended) return;
      _suspended = false;
      if (_openedSettings) {
        // 설정을 다녀왔다. 카메라·마이크를 켰을 수 있으니 한 번 다시 묻는다.
        _openedSettings = false;
        _permissionDenied = false;
        _micDenied = false;
      } else if (_permissionDenied) {
        if (mounted) setState(() => _status = _Status.permissionDenied);
        return;
      }
      unawaited(_enqueue(_initNow));
      return;
    }
    // 알림창·권한 창(inactive)에서는 녹화를 끊지 않는다. 실제로 백그라운드로
    // 갔을 때만 녹화를 끝내 파일을 살리고 카메라를 놓는다.
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached) {
      return;
    }
    if (_suspended) return;
    _suspended = true;
    _ticker?.cancel();
    _ticker = null;
    // 시작이 진행 중이어도 큐 순서상 시작 → 정지 → 해제로 처리된다.
    unawaited(_enqueue(_stopNow));
    if (mounted && _status != _Status.permissionDenied) {
      setState(() => _status = _Status.initializing);
    }
    unawaited(_enqueue(_disposeCamera));
  }

  Future<void> _disposeCamera() async {
    try {
      await _controller.dispose();
    } catch (_) {
      // 다음 initialize에서 다시 정리한다.
    }
  }

  void _openSettings() {
    _openedSettings = true;
    unawaited(
      ref.read(openAppSettingsProvider)().catchError((Object _) {
        _logger.phase('video.camera.settings.open', LogPhase.failure);
      }),
    );
  }

  void _retry() {
    _permissionDenied = false;
    unawaited(_enqueue(_initNow));
  }

  void _switchLens() {
    if (_recording || _busy || !_controller.canSwitchLens) return;
    _useFrontLens = !_useFrontLens;
    unawaited(_enqueue(_initNow));
  }

  Future<void> _start() async {
    if (_status != _Status.ready || _recording || _busy || _result != null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await _enqueue(() async {
      try {
        await _controller.startRecording();
      } catch (_) {
        _logger.phase('video.record.start', LogPhase.failure);
        if (mounted) setState(() => _error = '녹화를 시작하지 못했어요. 다시 시도해주세요.');
        return;
      }
      // 시작이 끝나기 전에 화면이 닫히거나 백그라운드로 갔어도 녹화는 이미 돌고
      // 있다. 상태를 먼저 맞춰야 뒤이은 정지가 파일을 회수한다.
      _recording = true;
      _startedAt = _clock();
      if (_disposed) {
        await _stopNow(discard: true);
        return;
      }
      if (_suspended) {
        await _stopNow();
        return;
      }
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      if (mounted) setState(() {});
    });
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _stop() async {
    if (!_recording || _busy) return;
    setState(() => _busy = true);
    await _enqueue(_stopNow);
    if (mounted) setState(() => _busy = false);
  }

  /// 녹화를 끝낸다. [discard]면 녹화본을 넘기지 않고 임시 파일을 지운다.
  Future<void> _stopNow({bool discard = false}) async {
    if (!_recording) return;
    _ticker?.cancel();
    _ticker = null;
    // 길이는 초 단위 타이머가 아니라 시작·정지 시각 차이로 잰다.
    final duration = _elapsed;
    try {
      final path = await _controller.stopRecording();
      final result = RecordedVideo(
        path: path,
        duration: duration,
        capturedAt: _startedAt ?? _clock(),
      );
      if (discard || _disposed) {
        _result = result;
        _discardResult();
      } else {
        _result = result;
      }
      _logger.phase('video.record', LogPhase.success);
    } catch (_) {
      _logger.phase('video.record.stop', LogPhase.failure);
      _error = '녹화를 마치지 못했어요. 다시 녹화해주세요.';
    } finally {
      _recording = false;
      _startedAt = null;
      if (mounted && !_disposed) setState(() {});
    }
  }

  void _discardResult() {
    final result = _result;
    _result = null;
    if (result != null) {
      unawaited(
        deleteTemporaryCaptureBestEffort(
          result.path,
          storage: _storage,
          logger: _logger,
        ),
      );
    }
  }

  /// 녹화본이 있으면 버릴지 묻는다. 버려도 되면 true.
  Future<bool> _confirmDiscard() async {
    if (_result == null) return true;
    final ok = await showAppConfirm(
      context,
      title: '녹화한 동영상을 버릴까요?',
      body: '버린 동영상은 되돌릴 수 없어요. 작성 중인 일지는 그대로 남아요.',
      cancelLabel: '계속 촬영',
      confirmLabel: '동영상 버리기',
      icon: Icons.delete_outline,
      destructive: true,
      preferCancel: true,
      dialogKey: 'video.camera.discard.dialog',
      cancelKey: 'video.camera.discard.keep.button',
      confirmKey: 'video.camera.discard.confirm.button',
    );
    return ok && mounted;
  }

  Future<void> _retake() async {
    if (!await _confirmDiscard()) return;
    setState(_discardResult);
  }

  void _use() {
    final result = _result;
    if (result == null) return;
    _returned = true;
    Navigator.of(context).pop(result);
  }

  Future<void> _requestLeave() async {
    // 시작·정지가 끝나기 전에는 녹화본을 확정할 수 없어 닫지 않는다.
    if (_busy) return;
    if (_recording) await _stop();
    if (!mounted || !await _confirmDiscard()) return;
    _discardResult();
    _returned = true;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _disposed = true;
    _suspended = true;
    _ticker?.cancel();
    if (!_returned) _discardResult();
    WidgetsBinding.instance.removeObserver(this);
    // 녹화 중에 닫히면(라우트 강제 제거 등) 녹화를 끝내고 파일은 버린다.
    // 시작이 진행 중이면 그 작업이 _disposed를 보고 같은 처리를 한다.
    unawaited(_enqueue(() => _stopNow(discard: true)));
    unawaited(_enqueue(_disposeCamera));
    unawaited(
      _orientationLock.restore().catchError((Object _) {
        _logger.warn('video.orientation.restore.failure');
      }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = context.photoColors;
    final onChrome = photo.onChrome;
    final ready = _status == _Status.ready;
    return mark(
      VideoCameraScreen.screenId,
      PopScope(
        canPop: !_recording && !_busy && _result == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_requestLeave());
        },
        child: Scaffold(
          backgroundColor: photo.viewfinder,
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sp2,
                    vertical: AppSpacing.sp1,
                  ),
                  child: Row(
                    children: [
                      mark(
                        'video.camera.close.button',
                        IconButton(
                          onPressed: _busy ? null : _requestLeave,
                          tooltip: '닫기',
                          icon: Icon(Icons.close, color: onChrome),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '레슨 동영상',
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.titleMedium?.copyWith(
                            color: onChrome,
                          ),
                        ),
                      ),
                      if (_recording || _result != null)
                        mark(
                          'video.camera.elapsed.value',
                          Semantics(
                            label: _recording ? '녹화 중' : '녹화 길이',
                            value: formatVideoDuration(
                              _result?.duration ?? _elapsed,
                            ),
                            liveRegion: false,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sp3,
                                vertical: AppSpacing.sp1,
                              ),
                              decoration: BoxDecoration(
                                color: _recording
                                    ? context.colors.error
                                    : photo.hudSurface,
                                borderRadius: AppRadius.fullAll,
                              ),
                              child: ExcludeSemantics(
                                child: Text(
                                  formatVideoDuration(
                                    _result?.duration ?? _elapsed,
                                  ),
                                  style: context.numericTexts.bodySmall
                                      .copyWith(
                                        color: _recording
                                            ? context.colors.onError
                                            : onChrome,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      mark(
                        'video.camera.lens.button',
                        IconButton(
                          onPressed:
                              ready &&
                                  !_recording &&
                                  !_busy &&
                                  _result == null &&
                                  _controller.canSwitchLens
                              ? _switchLens
                              : null,
                          tooltip: _useFrontLens ? '후면 카메라로 전환' : '전면 카메라로 전환',
                          icon: Icon(
                            Icons.cameraswitch_outlined,
                            color: onChrome,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _cameraArea()),
                if (ready && !_controller.audioEnabled) _muteNotice(),
                if (_error != null)
                  mark(
                    'video.camera.error',
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.sp3),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          keepPhrasesWhole(_error!),
                          textAlign: TextAlign.center,
                          style: context.texts.bodyMedium?.copyWith(
                            color: onChrome,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (ready) _controls(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cameraArea() => switch (_status) {
    _Status.initializing => const Center(
      child: CameraNoticeCard(
        statusId: 'screen.video.camera.status',
        tone: CameraNoticeTone.busy,
        title: '카메라를 준비하고 있어요.',
      ),
    ),
    _Status.error => Center(
      child: CameraNoticeCard(
        statusId: 'screen.video.camera.status',
        tone: CameraNoticeTone.failure,
        title: '카메라를 사용할 수 없어요.',
        description: '다시 시도해도 열리지 않으면 앱을 다시 실행해보세요.',
        onRetry: _retry,
      ),
    ),
    _Status.permissionDenied => Center(
      child: CameraNoticeCard(
        statusId: 'screen.video.camera.status',
        tone: CameraNoticeTone.actionNeeded,
        title: '카메라 권한이 필요해요.',
        description: '동영상을 촬영하려면 카메라 접근을 허용해주세요.',
        onOpenSettings: _openSettings,
        onRetry: _retry,
        settingsPath: cameraPermissionSettingsPath(),
        settingsPathHint: cameraPermissionSettingsHint,
      ),
    ),
    _Status.ready => LayoutBuilder(
      builder: (context, constraints) {
        final aspect = previewAspectFor(
          sensorAspect: _controller.aspectRatio,
          orientation: MediaQuery.orientationOf(context),
        );
        return ColoredBox(
          color: context.photoColors.backdrop,
          child: Center(
            // 미리보기는 잘라내지 않는다. 녹화되는 화각과 화면을 같게 둔다.
            child: AspectRatio(
              key: const ValueKey('video.camera.preview'),
              aspectRatio: aspect,
              child: _controller.buildPreview(),
            ),
          ),
        );
      },
    ),
  };

  Widget _muteNotice() {
    final photo = context.photoColors;
    return mark(
      'video.camera.mute.notice',
      Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(
          AppSpacing.sp3,
          AppSpacing.sp2,
          AppSpacing.sp3,
          0,
        ),
        padding: const EdgeInsets.all(AppSpacing.sp3),
        decoration: BoxDecoration(
          color: photo.panel,
          borderRadius: AppRadius.lgAll,
          border: Border.all(color: photo.hudOutline),
        ),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sp2,
          runSpacing: AppSpacing.sp1,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mic_off_outlined, size: 18, color: photo.warning),
                const SizedBox(width: AppSpacing.sp2),
                Flexible(
                  child: Text(
                    keepPhrasesWhole('소리 없이 녹화돼요'),
                    semanticsLabel: '마이크 권한이 없어 소리 없이 녹화돼요',
                    style: context.texts.bodyMedium?.copyWith(
                      color: photo.onChrome,
                    ),
                  ),
                ),
              ],
            ),
            mark(
              'video.camera.mute.settings.button',
              TextButton(
                onPressed: _openSettings,
                style: TextButton.styleFrom(foregroundColor: photo.measure),
                child: const Text('설정 열기'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls() {
    final photo = context.photoColors;
    if (_result != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.sp4),
        child: Row(
          children: [
            Expanded(
              child: mark(
                'video.camera.retake.button',
                OutlinedButton.icon(
                  onPressed: _retake,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: photo.onChrome,
                    side: BorderSide(color: photo.controlOutline),
                  ),
                  icon: const Icon(Icons.replay),
                  label: const Text('다시 녹화'),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sp3),
            Expanded(
              child: mark(
                'video.camera.use.button',
                FilledButton.icon(
                  onPressed: _use,
                  icon: const Icon(Icons.check),
                  label: const Text('이 동영상 쓰기'),
                ),
              ),
            ),
          ],
        ),
      );
    }
    final id = _recording
        ? 'video.camera.stop.button'
        : 'video.camera.record.button';
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sp4),
      child: mark(
        id,
        Semantics(
          button: true,
          label: _recording ? '녹화 정지' : '녹화 시작',
          child: ExcludeSemantics(
            child: InkResponse(
              onTap: _busy ? null : (_recording ? _stop : _start),
              radius: 40,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: photo.onChrome, width: 4),
                ),
                alignment: Alignment.center,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: _recording ? 28 : 56,
                  height: _recording ? 28 : 56,
                  decoration: BoxDecoration(
                    color: context.colors.error,
                    borderRadius: _recording
                        ? AppRadius.smAll
                        : AppRadius.fullAll,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
