import '../members/ui.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_info.dart';
import '../../core/korean_text.dart';
import '../../core/models/models.dart';
import '../../core/router/app_routes.dart';
import '../../core/services/settings_save_queue.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/async_status_indicator.dart';
import '../../core/widgets/status_pill.dart';
import '../capture/providers/capture_providers.dart';
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
  /// 저장 성공 알림은 잠깐만 보인다. 목록 아래쪽 항목을 가리지 않게 한다.
  static const successVisibleFor = Duration(seconds: 2);

  /// 이 화면에서 바꾼 저장이 막 성공해 알림을 보여 주는 중인지. 다른 화면
  /// (촬영 빠른 설정)에서 끝난 성공은 들어올 때 보여 주지 않는다.
  bool _showSuccess = false;
  Timer? _successTimer;

  @override
  void dispose() {
    _successTimer?.cancel();
    super.dispose();
  }

  void _onSaveStatus(SettingsSaveState? previous, SettingsSaveState next) {
    if (previous?.status == next.status) return;
    _successTimer?.cancel();
    if (next.status != SettingsSaveStatus.success) {
      if (_showSuccess) setState(() => _showSuccess = false);
      return;
    }
    setState(() => _showSuccess = true);
    _successTimer = Timer(successVisibleFor, () {
      if (mounted) setState(() => _showSuccess = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(appSettingsControllerProvider).valueOrNull ??
        AppSettings.defaults;
    final capture = settings.capture;
    // 저장 진행·실패는 값 상태와 분리해 알린다. 저장 중이어도 현재 값은 곧바로
    // 반영되므로 토글과 드롭다운이 손에 따라 움직인다. 격자 표시 기본값은
    // 촬영 화면과 같은 격자 저장소에 저장되므로 두 저장 상태를 함께 본다.
    final appSave = ref.watch(appSettingsSaveQueueProvider);
    final gridSave = ref.watch(gridSettingsSaveQueueProvider);
    ref.listen(appSettingsSaveQueueProvider, _onSaveStatus);
    ref.listen(gridSettingsSaveQueueProvider, _onSaveStatus);

    final failed = appSave.isFailure
        ? appSave
        : (gridSave.isFailure ? gridSave : null);
    final AsyncStatus status;
    if (failed != null) {
      status = AsyncStatus.failure;
    } else if (appSave.isSaving || gridSave.isSaving) {
      status = AsyncStatus.busy;
    } else if (_showSuccess) {
      status = AsyncStatus.success;
    } else {
      status = AsyncStatus.idle;
    }
    VoidCallback? retry;
    if (identical(failed, appSave) && appSave.canRetry) {
      retry = () =>
          ref.read(appSettingsControllerProvider.notifier).retrySave();
    } else if (identical(failed, gridSave) && gridSave.canRetry) {
      retry = () =>
          ref.read(gridSettingsControllerProvider.notifier).retrySave();
    }
    // 저장 상태는 목록 위에 떠 있는 알림으로 보여 준다. 목록 안에 칸을 두면
    // 평소엔 빈 칸이 남고, 칸이 생겼다 사라지면 아래 컨트롤이 밀려 엉뚱한 것을
    // 누를 수 있다. 성공 알림은 [successVisibleFor] 뒤 사라지고, 진행·실패는
    // 끝날 때까지 남는다(실패는 재시도 버튼).
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
                      onRetry: retry,
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
        const Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.sp4,
            AppSpacing.sp4,
            AppSpacing.sp4,
            0,
          ),
          child: _BrandCard(),
        ),
        const _SectionHeader('촬영'),
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
        _gridVisibleSwitch(),
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
          label: '이전 사진 기본 진하기',
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
                      const Expanded(child: Text('이전 사진 진하기')),
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
        _linkRecordsItem(),

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
                keepPhrasesWhole('격자 간격·굵기와 이전 사진 가이드는 촬영 화면에서 바로 조절해요.'),
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

  /// 촬영을 시작할 때 격자를 켜 둘지. 촬영 화면의 격자 버튼과 같은 값이다.
  Widget _gridVisibleSwitch() {
    final grid = ref.watch(gridSettingsControllerProvider).valueOrNull;
    final visible = grid?.visible ?? GridSettings.defaults.visible;
    return Semantics(
      identifier: 'settings.capture.grid.switch',
      child: SwitchListTile(
        key: const ValueKey('settings.capture.grid.switch'),
        secondary: const Icon(Icons.grid_on_outlined),
        title: const Text('격자 표시'),
        subtitle: Text(keepPhrasesWhole('촬영을 시작할 때 격자선을 켜 둬요')),
        value: visible,
        // 저장된 값을 읽기 전에는 바꾸지 않는다. 읽기 전 값으로 덮어쓰면 다른
        // 격자 값(간격·굵기)이 기본값으로 돌아간다.
        onChanged: grid == null
            ? null
            : (v) => unawaited(
                ref
                    .read(gridSettingsControllerProvider.notifier)
                    .update((s) => s.copyWith(visible: v)),
              ),
      ),
    );
  }

  /// 회원 없이 남은 기존 기록을 기록 탭의 '회원 미연결' 필터로 연다.
  Widget _linkRecordsItem() {
    final count = ref.watch(unlinkedRecordCountProvider);
    final subtitle = switch (count) {
      AsyncData(value: 0) => '연결할 기록 없음',
      AsyncData(:final value) => '회원 미연결 기록 $value개',
      _ => '회원이 연결되지 않은 기록 보기',
    };
    return Semantics(
      identifier: 'settings.linkRecords.item',
      child: ListTile(
        key: const ValueKey('settings.linkRecords.item'),
        leading: const Icon(Icons.link_outlined),
        title: const Text('기존 기록 연결'),
        subtitle: Text(
          keepPhrasesWhole(subtitle),
          key: const ValueKey('settings.linkRecords.subtitle'),
        ),
        trailing: const Icon(Icons.chevron_right),
        // go를 쓰면 카메라 위에서 연 설정일 때 촬영 흐름의 스택(촬영분, 작성 중
        // 일지)을 확인 없이 버린다. push로 열고, 돌아오면 개수를 다시 읽는다.
        onTap: () async {
          await context.push(
            Uri(
              path: '/records',
              queryParameters: {
                AppParams.memberFilter: AppParams.unlinkedMembers,
              },
            ).toString(),
          );
          if (mounted) ref.invalidate(unlinkedRecordCountProvider);
        },
      ),
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

/// 앱 이름·버전과 기기 보관 원칙을 한눈에 보여 주는 카드.
class _BrandCard extends StatelessWidget {
  const _BrandCard();

  @override
  Widget build(BuildContext context) {
    final muted = context.texts.bodySmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    return Semantics(
      identifier: 'settings.brand.card',
      container: true,
      child: Card(
        key: const ValueKey('settings.brand.card'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: AppSpacing.content,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(AppInfo.name, style: context.texts.titleLarge),
                  ),
                  const StatusPill(
                    label: 'v${AppInfo.version}',
                    identifier: 'settings.version.label',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sp1),
              Text(
                keepPhrasesWhole('강사를 위한 회원·레슨 기록'),
                style: context.texts.titleSmall,
              ),
              const SizedBox(height: AppSpacing.sp1),
              Text(
                keepPhrasesWhole('회원 정보와 사진 기록은 이 휴대폰에만 보관돼요.'),
                style: muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return SectionHeader(
      title: label,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sp4,
        AppSpacing.sp6,
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
