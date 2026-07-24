import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/providers.dart';
import '../../core/router/app_routes.dart';
import 'providers/settings_providers.dart';

/// 앱 설정 화면.
///
/// 스튜디오명 설정, 기본 격자 설정, 앱 잠금/백업·복원/저장 공간/개인정보
/// 안내로 진입하는 홈 화면.
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
          data: (settings) => _SettingsBody(settings: settings),
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
  final AppSettings settings;

  const _SettingsBody({required this.settings});

  @override
  ConsumerState<_SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends ConsumerState<_SettingsBody> {
  late final TextEditingController _studioNameController;

  @override
  void initState() {
    super.initState();
    _studioNameController =
        TextEditingController(text: widget.settings.studioName ?? '');
  }

  @override
  void dispose() {
    _studioNameController.dispose();
    super.dispose();
  }

  Future<void> _saveStudioName() async {
    final value = _studioNameController.text.trim();
    await ref.read(appSettingsControllerProvider.notifier).updateSettings(
          (s) => s.copyWith(studioName: value.isEmpty ? '' : value),
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('스튜디오명을 저장했습니다')),
    );
  }

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
      padding: const EdgeInsets.all(16),
      children: [
        const Text('스튜디오명', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('settings.studioName.field'),
                controller: _studioNameController,
                decoration: const InputDecoration(
                  hintText: '비교 이미지에 표시할 스튜디오명(선택)',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _saveStudioName(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const ValueKey('settings.studioName.save.button'),
              onPressed: _saveStudioName,
              icon: const Icon(Icons.check),
              tooltip: '저장',
            ),
          ],
        ),
        const Divider(height: 32),
        ListTile(
          key: const ValueKey('settings.grid.item'),
          leading: const Icon(Icons.grid_on),
          title: const Text('기본 격자 설정'),
          subtitle: const Text('촬영 화면의 기본 격자 표시/투명도/굵기/간격'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _showDefaultGridDialog,
        ),
        ListTile(
          key: const ValueKey('settings.lock.item'),
          leading: const Icon(Icons.lock_outline),
          title: const Text('앱 잠금 설정'),
          subtitle: Text('현재: ${widget.settings.lockMode.label}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.goNamed(AppRoutes.appLock),
        ),
        ListTile(
          key: const ValueKey('settings.backup.item'),
          leading: const Icon(Icons.backup_outlined),
          title: const Text('백업 및 복원'),
          subtitle: const Text('전체/회원별 백업 생성 및 복원'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.goNamed(AppRoutes.backupRestore),
        ),
        ListTile(
          key: const ValueKey('settings.storage.item'),
          leading: const Icon(Icons.storage_outlined),
          title: const Text('저장 공간 관리'),
          subtitle: const Text('사진 저장 용량 확인'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.goNamed(AppRoutes.storage),
        ),
        ListTile(
          key: const ValueKey('settings.privacy.item'),
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('개인정보 및 이용 안내'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.goNamed(AppRoutes.privacyInfo),
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
