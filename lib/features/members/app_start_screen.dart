import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import '../settings/providers/settings_providers.dart';

/// 앱 시작 화면.
///
/// 로그인이나 회원가입 없이 곧바로 회원 목록으로 진입한다.
class AppStartScreen extends ConsumerWidget {
  static const screenId = 'screen.app.start';

  const AppStartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsControllerProvider);
    final noticeAcknowledged =
        settings.valueOrNull?.dataNoticeAcknowledged ?? false;
    final settingsReady = settings.hasValue;

    return Semantics(
      identifier: screenId,
      container: true,
      label: '앱 시작',
      child: Scaffold(
        key: const ValueKey(screenId),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '체형 변화 기록',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (!noticeAcknowledged) ...[
                const SizedBox(height: 24),
                Semantics(
                  identifier: 'app.start.dataNotice',
                  container: true,
                  label: '데이터 보관 안내',
                  child: Container(
                    key: const ValueKey('app.start.dataNotice'),
                    constraints: const BoxConstraints(maxWidth: 440),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      '회원 정보와 체형 사진은 이 기기의 앱 전용 저장소에 보관됩니다. '
                      '앱을 삭제하면 데이터가 함께 삭제될 수 있으므로 기기 변경이나 '
                      '재설치 전에는 백업을 만들어 주세요.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Semantics(
                identifier: 'app.start.enter.button',
                button: true,
                label: '시작하기',
                child: FilledButton(
                  key: const ValueKey('app.start.enter.button'),
                  onPressed: !settingsReady
                      ? null
                      : () async {
                          if (!noticeAcknowledged) {
                            await ref
                                .read(appSettingsControllerProvider.notifier)
                                .updateSettings(
                                  (current) => current.copyWith(
                                    dataNoticeAcknowledged: true,
                                  ),
                                );
                          }
                          if (context.mounted) {
                            context.goNamed(AppRoutes.membersList);
                          }
                        },
                  child: Text(noticeAcknowledged ? '시작하기' : '안내를 확인하고 시작'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
