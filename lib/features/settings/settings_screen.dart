import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/providers.dart';
import '../../core/router/app_routes.dart';
import 'providers/settings_providers.dart';

/// 앱 설정 화면.
///
/// 기본 격자 설정과 저장 공간 관리로 진입하는 홈 화면.
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
  Future<void> _showDefaultGridDialog() async {
    final service = ref.read(gridSettingsServiceProvider);
    var current = await service.load();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('기본 격자 설정'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      key: const ValueKey('settings.grid.visible.switch'),
                      title: const Text('격자 표시'),
                      value: current.visible,
                      onChanged: (v) {
                        current = current.copyWith(visible: v);
                        setDialogState(() {});
                      },
                    ),
                    Text('투명도: ${current.opacity.toStringAsFixed(2)}'),
                    Slider(
                      key: const ValueKey('settings.grid.opacity.slider'),
                      value: current.opacity,
                      min: 0.1,
                      max: 1.0,
                      onChanged: (v) {
                        current = current.copyWith(opacity: v);
                        setDialogState(() {});
                      },
                    ),
                    Text('선 굵기: ${current.lineWidth.toStringAsFixed(1)}'),
                    Slider(
                      key: const ValueKey('settings.grid.lineWidth.slider'),
                      value: current.lineWidth,
                      min: 0.5,
                      max: 4.0,
                      onChanged: (v) {
                        current = current.copyWith(lineWidth: v);
                        setDialogState(() {});
                      },
                    ),
                    Text('간격: ${current.spacing.toStringAsFixed(0)}'),
                    Slider(
                      key: const ValueKey('settings.grid.spacing.slider'),
                      value: current.spacing,
                      min: 10,
                      max: 120,
                      onChanged: (v) {
                        current = current.copyWith(spacing: v);
                        setDialogState(() {});
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  key: const ValueKey('settings.grid.reset.button'),
                  onPressed: () async {
                    await service.reset();
                    current = GridSettings.defaults;
                    setDialogState(() {});
                  },
                  child: const Text('초기화'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('취소'),
                ),
                FilledButton(
                  key: const ValueKey('settings.grid.save.button'),
                  onPressed: () async {
                    await service.save(current);
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
                  child: const Text('저장'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        ListTile(
          key: const ValueKey('settings.grid.item'),
          leading: const Icon(Icons.grid_on),
          title: const Text('기본 격자 설정'),
          subtitle: const Text('촬영 화면의 기본 격자 표시/투명도/굵기/간격'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _showDefaultGridDialog,
        ),
        ListTile(
          key: const ValueKey('settings.storage.item'),
          leading: const Icon(Icons.storage_outlined),
          title: const Text('저장 공간 관리'),
          subtitle: const Text('사진 저장 용량 확인'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.pushNamed(AppRoutes.storage),
        ),
        const Divider(height: 32),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '기록은 이 기기의 앱 저장소에 보관되며, 새 기기로 옮길 때 시스템의 '
            '기기 간 전송으로 함께 이동합니다.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
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
