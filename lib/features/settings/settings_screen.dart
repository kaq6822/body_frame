import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models/models.dart';
import '../../core/providers.dart';
import '../../core/router/app_routes.dart';
import '../../core/services/app_image_picker.dart';
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
  static const _studioAssetOwner = 'studio-assets';

  late final TextEditingController _studioNameController;
  bool _logoBusy = false;
  bool _recoveringLostLogo = false;
  bool _lostLogoRecoveryScheduled = false;

  ImagePickerRequestContext get _logoPickerContext =>
      ImagePickerRequestContext.studioLogo();

  @override
  void initState() {
    super.initState();
    _studioNameController = TextEditingController(
      text: widget.settings.studioName ?? '',
    );
    ref.listenManual<RecoveredImagePickerSelection?>(
      appImagePickerCoordinatorProvider,
      (previous, next) {
        if (next?.context == _logoPickerContext) {
          _scheduleLostLogoRecovery();
        }
      },
      fireImmediately: true,
    );
    if (ref.read(appImagePickerCoordinatorProvider)?.context ==
        _logoPickerContext) {
      _scheduleLostLogoRecovery();
    }
  }

  void _scheduleLostLogoRecovery() {
    if (_lostLogoRecoveryScheduled) return;
    _lostLogoRecoveryScheduled = true;
    Future<void>.microtask(() {
      _lostLogoRecoveryScheduled = false;
      if (mounted) unawaited(_recoverLostLogo());
    });
  }

  Future<void> _recoverLostLogo() async {
    if (!mounted || _recoveringLostLogo || _logoBusy) return;
    final coordinator = ref.read(appImagePickerCoordinatorProvider.notifier);
    final recovered = coordinator.recoveredFor(_logoPickerContext);
    if (recovered == null) return;
    _recoveringLostLogo = true;
    try {
      final picked = recovered.lastFile;
      if (picked == null) {
        throw StateError('복구할 스튜디오 로고가 없습니다.');
      }
      final saved = await _storeStudioLogo(picked);
      if (saved) {
        await coordinator.acknowledgeRecovered(_logoPickerContext);
      }
    } finally {
      _recoveringLostLogo = false;
    }
  }

  @override
  void dispose() {
    _studioNameController.dispose();
    super.dispose();
  }

  Future<void> _saveStudioName() async {
    final value = _studioNameController.text.trim();
    await ref
        .read(appSettingsControllerProvider.notifier)
        .updateSettings(
          (s) => value.isEmpty
              ? s.copyWith(clearStudioName: true)
              : s.copyWith(studioName: value),
        );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('스튜디오명을 저장했습니다')));
  }

  Future<void> _pickStudioLogo() async {
    if (_logoBusy) return;
    try {
      final picked = await ref
          .read(appImagePickerCoordinatorProvider.notifier)
          .pickImage(context: _logoPickerContext, source: ImageSource.gallery);
      if (picked == null || !mounted) return;
      await _storeStudioLogo(picked);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('스튜디오 로고를 불러오지 못했습니다')));
    }
  }

  Future<bool> _storeStudioLogo(XFile picked) async {
    if (_logoBusy) return false;
    setState(() => _logoBusy = true);
    final storage = ref.read(photoStorageServiceProvider);
    String? newPath;
    var settingsSaved = false;
    try {
      newPath = await storage.saveOriginal(
        memberId: _studioAssetOwner,
        sourcePath: picked.path,
      );
      final storedPath = await storage.toStoredPath(newPath);
      final oldPath = widget.settings.studioLogoPath;
      await ref
          .read(appSettingsControllerProvider.notifier)
          .updateSettings(
            (settings) => settings.copyWith(studioLogoPath: storedPath),
          );
      settingsSaved = true;
      if (oldPath != null && oldPath != storedPath) {
        try {
          await storage.deleteFile(oldPath);
        } catch (_) {
          ref
              .read(appLoggerProvider)
              .warn('settings.studioLogo.oldCleanup.failure');
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('스튜디오 로고를 저장했습니다')));
      }
      return true;
    } catch (_) {
      if (!settingsSaved && newPath != null) {
        try {
          await storage.deleteFile(newPath);
        } catch (_) {
          // 새 파일 정리 실패는 원래 저장 오류를 가리지 않는다.
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('스튜디오 로고를 저장하지 못했습니다')));
      }
      return false;
    } finally {
      if (mounted) setState(() => _logoBusy = false);
    }
  }

  Future<void> _clearStudioLogo() async {
    if (_logoBusy) return;
    final oldPath = widget.settings.studioLogoPath;
    if (oldPath == null) return;
    setState(() => _logoBusy = true);
    try {
      await ref
          .read(appSettingsControllerProvider.notifier)
          .updateSettings(
            (settings) => settings.copyWith(clearStudioLogoPath: true),
          );
      try {
        await ref.read(photoStorageServiceProvider).deleteFile(oldPath);
      } catch (_) {
        ref.read(appLoggerProvider).warn('settings.studioLogo.cleanup.failure');
      }
    } finally {
      if (mounted) setState(() => _logoBusy = false);
    }
  }

  Future<String?> _resolvedLogoPath() async {
    final stored = widget.settings.studioLogoPath;
    if (stored == null || stored.isEmpty) return null;
    try {
      final path = await ref
          .read(photoStorageServiceProvider)
          .resolvePath(stored);
      return await File(path).exists() ? path : null;
    } catch (_) {
      return null;
    }
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
        const SizedBox(height: 16),
        const Text('스튜디오 로고', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Semantics(
              identifier: 'settings.studioLogo.preview',
              label: '저장된 스튜디오 로고',
              child: Container(
                key: const ValueKey('settings.studioLogo.preview'),
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: FutureBuilder<String?>(
                  future: _resolvedLogoPath(),
                  builder: (context, snapshot) {
                    final path = snapshot.data;
                    return path == null
                        ? const Icon(Icons.business_outlined)
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(7),
                            child: Image.file(File(path), fit: BoxFit.contain),
                          );
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    key: const ValueKey('settings.studioLogo.pick.button'),
                    onPressed: _logoBusy ? null : _pickStudioLogo,
                    child: Text(
                      widget.settings.studioLogoPath == null
                          ? '로고 선택'
                          : '로고 교체',
                    ),
                  ),
                  if (widget.settings.studioLogoPath != null)
                    TextButton(
                      key: const ValueKey('settings.studioLogo.clear.button'),
                      onPressed: _logoBusy ? null : _clearStudioLogo,
                      child: const Text('삭제'),
                    ),
                ],
              ),
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
