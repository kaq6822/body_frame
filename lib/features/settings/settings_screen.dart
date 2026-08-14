import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_tokens.dart';
import 'providers/settings_providers.dart';

/// 전체 설정 화면.
///
/// 격자와 이전 사진 가이드는 촬영 화면의 퀵 패널에서 뷰파인더를 보면서 바로
/// 조절한다. 이 화면에는 뷰파인더가 필요 없는 설정만 남는다.
class SettingsScreen extends ConsumerWidget {
  static const screenId = 'screen.settings.home';

  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsControllerProvider);

    return Semantics(
      identifier: screenId,
      container: true,
      label: '앱 설정',
      child: Scaffold(
        key: const ValueKey(screenId),
        appBar: AppBar(title: const Text('앱 설정')),
        body: settingsAsync.when(
          data: (settings) => const _SettingsBody(),
          loading: () => const Center(
            key: ValueKey('screen.settings.status'),
            child: CircularProgressIndicator(),
          ),
          error: (e, st) => _ErrorRetry(
            message: '설정을 불러오지 못했습니다',
            onRetry: () => ref.invalidate(appSettingsControllerProvider),
          ),
        ),
      ),
    );
  }
}

class _SettingsBody extends ConsumerStatefulWidget {
  const _SettingsBody();

  @override
  ConsumerState<_SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends ConsumerState<_SettingsBody> {
  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(appSettingsControllerProvider).valueOrNull ??
        AppSettings.defaults;
    final capture = settings.capture;

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.sp6),
      children: [
        const _SectionHeader('촬영'),
        Semantics(
          identifier: 'settings.capture.timer.field',
          label: '셀프 타이머 기본값',
          value: _timerLabel(capture.timerSeconds),
          child: ListTile(
            key: const ValueKey('settings.capture.timer.field'),
            leading: const Icon(Icons.timer_outlined),
            title: const Text('셀프 타이머 기본값'),
            subtitle: const Text('새 촬영 세션을 시작할 때의 값'),
            trailing: DropdownButton<int>(
              key: const ValueKey('settings.capture.timer.dropdown'),
              value: CaptureOptions.normalizeTimer(capture.timerSeconds),
              onChanged: (value) {
                if (value == null) return;
                _updateCapture(capture.copyWith(timerSeconds: value));
              },
              items: [
                for (final seconds in CaptureOptions.timerChoices)
                  DropdownMenuItem(
                    value: seconds,
                    child: Text(_timerLabel(seconds)),
                  ),
              ],
            ),
          ),
        ),
        Semantics(
          identifier: 'settings.capture.countdownFeedback.switch',
          label: '카운트다운 소리와 진동',
          value: capture.countdownFeedback ? '켜짐' : '꺼짐',
          child: SwitchListTile(
            key: const ValueKey('settings.capture.countdownFeedback.switch'),
            secondary: const Icon(Icons.volume_up_outlined),
            title: const Text('카운트다운 소리와 진동'),
            subtitle: const Text('마지막 2초는 더 강하게 알립니다'),
            value: capture.countdownFeedback,
            onChanged: (value) =>
                _updateCapture(capture.copyWith(countdownFeedback: value)),
          ),
        ),
        const _SectionHeader('데이터'),
        ListTile(
          key: const ValueKey('settings.storage.item'),
          leading: const Icon(Icons.storage_outlined),
          title: const Text('저장 공간 관리'),
          subtitle: const Text('사진 저장 용량 확인'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.pushNamed(AppRoutes.storage),
        ),
        const _SectionHeader('정보'),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sp4,
            0,
            AppSpacing.sp4,
            AppSpacing.sp4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '기록은 이 기기의 앱 저장소에 보관되며, 새 기기로 옮길 때 시스템의 '
                '기기 간 전송으로 함께 이동합니다.',
                style: context.texts.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sp2),
              Text(
                '격자는 원본 사진에 저장되지 않습니다. 촬영 후에도 사진마다 바꿀 수 있고, '
                '내보내거나 공유할 때만 이미지에 합쳐집니다.',
                style: context.texts.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sp2),
              Text(
                '격자 표시와 이전 사진 가이드는 촬영 화면에서 바로 조절합니다.',
                style: context.texts.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _timerLabel(int seconds) => seconds == 0 ? '끔' : '$seconds초';

  void _updateCapture(CaptureOptions next) {
    // 조작하는 즉시 저장한다. 저장 버튼을 따로 두지 않는다.
    unawaited(
      ref
          .read(appSettingsControllerProvider.notifier)
          .updateSettings((current) => current.copyWith(capture: next)),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sp4,
        AppSpacing.sp4,
        AppSpacing.sp4,
        AppSpacing.sp1,
      ),
      child: Text(
        label,
        style: context.texts.labelMedium?.copyWith(
          color: context.colors.primary,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('screen.settings.status'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: 8),
          ElevatedButton(
            key: const ValueKey('settings.retry.button'),
            onPressed: onRetry,
            child: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }
}
