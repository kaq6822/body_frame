import '../members/ui.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/korean_text.dart';
import '../../core/models/models.dart';
import '../../core/router/app_routes.dart';
import '../../core/services/settings_save_queue.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/async_status_indicator.dart';
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
        appBar: AppBar(title: const Text('설정')),
        bottomNavigationBar: const MainNavigation(2),
        body: settingsAsync.when(
          data: (settings) => const _SettingsBody(),
          loading: () => const Center(
            key: ValueKey('screen.settings.status'),
            child: CircularProgressIndicator(),
          ),
          error: (e, st) => _ErrorRetry(
            message: '설정을 불러오지 못했어요',
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
    // 저장 진행·실패는 값 상태와 분리해 알린다. 저장 중이어도 현재 값은 곧바로
    // 반영되므로 토글과 드롭다운이 손에 따라 움직인다.
    final saveState = ref.watch(appSettingsSaveQueueProvider);

    final status = switch (saveState.status) {
      SettingsSaveStatus.idle => AsyncStatus.idle,
      SettingsSaveStatus.saving => AsyncStatus.busy,
      SettingsSaveStatus.success => AsyncStatus.success,
      SettingsSaveStatus.failure => AsyncStatus.failure,
    };
    // 저장 상태는 목록 위에 떠 있는 알림으로 보여 준다. 목록 안에 칸을 두면
    // 평소엔 빈 칸이 남고, 칸이 생겼다 사라지면 아래 컨트롤이 밀려 엉뚱한 것을
    // 누를 수 있다. 떠 있는 알림은 둘 다 피한다.
    return Stack(
      children: [
        _settingsList(context, capture),
        Positioned(
          left: AppSpacing.sp4,
          right: AppSpacing.sp4,
          bottom: AppSpacing.sp4,
          child: status == AsyncStatus.idle
              ? const SizedBox.shrink()
              : Material(
                  color: context.colors.surfaceContainerLowest,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.mdAll,
                    side: BorderSide(color: context.colors.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sp4,
                      vertical: AppSpacing.sp2,
                    ),
                    child: AsyncStatusIndicator(
                      statusId: 'screen.settings.save.status',
                      status: status,
                      busyLabel: '설정을 저장하고 있어요.',
                      successLabel: '설정을 저장했어요.',
                      failureMessage: '설정을 저장하지 못했어요. 다시 시도해주세요.',
                      // 실패해도 화면에 반영된 값은 그대로 두어 마지막 선택 의도를 보존한다.
                      onRetry: saveState.canRetry
                          ? () => ref
                                .read(appSettingsControllerProvider.notifier)
                                .retrySave()
                          : null,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _settingsList(BuildContext context, CaptureOptions capture) {
    return ListView(
      // 떠 있는 저장 알림이 마지막 항목을 가리지 않게 여유를 둔다.
      padding: const EdgeInsets.only(bottom: AppSpacing.sp8 + AppSpacing.sp7),
      children: [
        const _SectionHeader('촬영', first: true),
        Semantics(
          identifier: 'settings.capture.timer.field',
          label: '셀프 타이머 기본값',
          value: _timerLabel(capture.timerSeconds),
          child: ListTile(
            key: const ValueKey('settings.capture.timer.field'),
            leading: const Icon(Icons.timer_outlined),
            title: const Text('셀프 타이머 기본값'),
            subtitle: Text(keepPhrasesWhole('새 촬영 세션을 시작할 때의 값')),
            trailing: DropdownButton<int>(
              key: const ValueKey('settings.capture.timer.dropdown'),
              underline: const SizedBox.shrink(),
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
            subtitle: Text(keepPhrasesWhole('마지막 2초는 더 강하게 알려요')),
            value: capture.countdownFeedback,
            onChanged: (value) =>
                _updateCapture(capture.copyWith(countdownFeedback: value)),
          ),
        ),
        Semantics(
          identifier: 'settings.capture.guide.switch',
          child: SwitchListTile(
            key: const ValueKey('settings.capture.guide.switch'),
            secondary: const Icon(Icons.layers_outlined),
            title: const Text('이전 사진 표시 기본값'),
            subtitle: Text(keepPhrasesWhole('선택한 회원·같은 방향의 기준 사진')),
            value: capture.previousGuide,
            onChanged: (v) =>
                _updateCapture(capture.copyWith(previousGuide: v)),
          ),
        ),
        Semantics(
          identifier: 'settings.capture.level.switch',
          child: SwitchListTile(
            key: const ValueKey('settings.capture.level.switch'),
            secondary: const Icon(Icons.straighten_outlined),
            title: const Text('수평계 표시'),
            subtitle: Text(keepPhrasesWhole('기울기가 1° 안이면 선이 청록색으로 바뀌어요')),
            value: capture.showLevel,
            onChanged: (v) => _updateCapture(capture.copyWith(showLevel: v)),
          ),
        ),
        Semantics(
          identifier: 'settings.capture.opacity.slider',
          label: '이전 사진 기본 투명도',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Row(
                    children: [
                      // ListTile과 같은 아이콘 열(24 + 간격 16)을 두어 제목 시작선을 맞춘다.
                      Icon(
                        Icons.opacity_outlined,
                        color: context.colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.sp4),
                      const Expanded(child: Text('이전 사진 투명도')),
                      Text(
                        '${(capture.guideOpacity * 100).round()}%',
                        style: context.texts.labelMedium,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.sp7),
                  child: Slider(
                    key: const ValueKey('settings.capture.opacity.slider'),
                    value: capture.guideOpacity,
                    divisions: 20,
                    semanticFormatterCallback: (v) => '${(v * 100).round()}%',
                    onChanged: (v) =>
                        _updateCapture(capture.copyWith(guideOpacity: v)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const _SectionHeader('데이터'),
        ListTile(
          key: const ValueKey('settings.data.item'),
          leading: const Icon(Icons.phone_android_outlined),
          title: const Text('데이터 보관 안내'),
          subtitle: Text(keepPhrasesWhole('기록이 보관되는 방식')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/settings/data'),
        ),
        ListTile(
          key: const ValueKey('settings.privacy.item'),
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('개인정보 안내'),
          subtitle: Text(keepPhrasesWhole('회원 정보와 사진의 취급 원칙')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/settings/privacy'),
        ),

        ListTile(
          key: const ValueKey('settings.storage.item'),
          leading: const Icon(Icons.storage_outlined),
          title: const Text('저장 공간 관리'),
          subtitle: Text(keepPhrasesWhole('사진 저장 용량 확인')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.pushNamed(AppRoutes.storage),
        ),
        const _SectionHeader('정보'),
        ListTile(
          key: const ValueKey('settings.licenses.item'),
          leading: const Icon(Icons.description_outlined),
          title: const Text('오픈소스 라이선스'),
          subtitle: Text(keepPhrasesWhole('사용한 글꼴과 라이브러리의 라이선스')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              showLicensePage(context: context, applicationName: 'BodyMark'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sp4,
            AppSpacing.sp2,
            AppSpacing.sp4,
            AppSpacing.sp4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                keepPhrasesWhole(
                  '격자는 원본 사진에 저장되지 않아요. 촬영 후에도 사진마다 바꿀 수 있고, '
                  '내보내거나 공유할 때만 이미지에 합쳐져요.',
                ),
                style: context.texts.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sp2),
              Text(
                keepPhrasesWhole('격자 표시와 이전 사진 가이드는 촬영 화면에서 바로 조절해요.'),
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
    // 조작하는 즉시 반영하고, 저장은 큐가 순서대로 이어서 처리한다.
    // 실패하면 저장 상태가 별도로 알려 준다.
    unawaited(
      ref
          .read(appSettingsControllerProvider.notifier)
          .updateSettings((current) => current.copyWith(capture: next)),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final bool first;

  const _SectionHeader(this.label, {this.first = false});

  @override
  Widget build(BuildContext context) {
    return SectionHeader(
      title: label,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sp4,
        first ? AppSpacing.sp4 : AppSpacing.sp6,
        AppSpacing.sp4,
        AppSpacing.sp1,
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
          FilledButton(
            key: const ValueKey('settings.retry.button'),
            onPressed: onRetry,
            child: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }
}
