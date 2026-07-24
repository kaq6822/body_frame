import 'dart:async';

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
import 'widgets/capture_member_banner.dart';
import 'widgets/grid_overlay.dart';
import 'widgets/grid_settings_panel.dart';

/// 7. 격자 카메라 화면. MVP.md 4.3 / 4.4.
///
/// 카메라 컨트롤러는 [captureCameraControllerFactoryProvider]로 주입한다.
/// 테스트에서는 `ProviderScope(overrides: [captureCameraControllerFactoryProvider
/// .overrideWithValue(() => FakeController())])`로 실기기 카메라 없이 검증한다.
class GridCameraScreen extends ConsumerStatefulWidget {
  static const screenId = 'screen.capture.camera';

  final String memberId;

  const GridCameraScreen({super.key, required this.memberId});

  @override
  ConsumerState<GridCameraScreen> createState() => _GridCameraScreenState();
}

enum _CameraStatus { initializing, ready, error }

class _GridCameraScreenState extends ConsumerState<GridCameraScreen> {
  late final CaptureCameraController _controller;
  _CameraStatus _status = _CameraStatus.initializing;
  bool _capturing = false;
  bool _showSettings = false;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(captureCameraControllerFactoryProvider)();
    unawaited(_initCamera());
  }

  Future<void> _initCamera() async {
    setState(() => _status = _CameraStatus.initializing);
    final logger = ref.read(appLoggerProvider);
    logger.phase('capture.camera.init', LogPhase.start);
    try {
      await _controller.initialize();
      if (!mounted) return;
      setState(() => _status = _CameraStatus.ready);
      logger.phase('capture.camera.init', LogPhase.success);
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _CameraStatus.error);
      logger.phase('capture.camera.init', LogPhase.failure);
    }
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  Future<void> _onShutterPressed() async {
    if (_status != _CameraStatus.ready || _capturing) return;
    setState(() => _capturing = true);
    final logger = ref.read(appLoggerProvider);
    logger.phase('capture.shot', LogPhase.start);
    try {
      final path = await _controller.takePicture();
      final grid = ref.read(gridSettingsControllerProvider).value ?? GridSettings.defaults;
      ref
          .read(captureSessionProvider(widget.memberId).notifier)
          .setCapturedImage(path, gridSettings: grid);
      logger.phase('capture.shot', LogPhase.success);
      if (!mounted) return;
      await context.pushNamed(
        AppRoutes.captureReview,
        pathParameters: {AppParams.memberId: widget.memberId},
      );
    } catch (_) {
      logger.phase('capture.shot', LogPhase.failure);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('촬영에 실패했습니다. 다시 시도해주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final memberAsync = ref.watch(memberByIdProvider(widget.memberId));
    final direction = ref.watch(
      captureSessionProvider(widget.memberId).select((s) => s.direction),
    );
    final gridAsync = ref.watch(gridSettingsControllerProvider);

    return Semantics(
      identifier: GridCameraScreen.screenId,
      container: true,
      label: '격자 카메라',
      child: Scaffold(
        key: const ValueKey(GridCameraScreen.screenId),
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(child: _buildCameraArea(gridAsync.value)),
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: _buildTopBar(memberAsync, direction),
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
                child: Center(child: _buildShutterButton()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraArea(GridSettings? gridSettings) => switch (_status) {
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

  Widget _buildTopBar(AsyncValue<Member?> memberAsync, BodyDirection direction) {
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
            child: memberAsync.maybeWhen(
              data: (member) => CaptureMemberBanner(
                memberName: member?.name ?? '',
                direction: direction,
                textColor: Colors.white,
              ),
              orElse: () => const SizedBox.shrink(),
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
              .map((m) => Text(
                    m,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ))
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
