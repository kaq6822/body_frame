import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'models/backup_models.dart';
import 'providers/settings_providers.dart';

enum _OpStatus { idle, busy, success, failure }

/// 18. 백업 및 복원 화면. MVP.md 10장.
///
/// 대기/진행/성공/실패 상태를 `backup.progress.status`에 표시하고, 데이터
/// 손실 가능성이 있는 복원(특히 교체 모드)은 반드시 확인 절차를 거친다.
class BackupRestoreScreen extends ConsumerStatefulWidget {
  static const screenId = 'screen.settings.backup';

  const BackupRestoreScreen({super.key});

  @override
  ConsumerState<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends ConsumerState<BackupRestoreScreen> {
  _OpStatus _status = _OpStatus.idle;
  String _statusMessage = '대기 중';
  String? _lastBackupFilePath;
  String? _selectedMemberId;

  @override
  void initState() {
    super.initState();
    _cleanupStaleTempBackups();
  }

  @override
  void dispose() {
    // 평문 개인정보가 담긴 임시 백업 zip을 화면 이탈 시 정리한다.
    final path = _lastBackupFilePath;
    if (path != null) {
      File(path).delete().ignore();
    }
    super.dispose();
  }

  /// 이전 실행/화면에서 남은 임시 백업 zip을 정리한다(민감 정보 잔존 방지).
  Future<void> _cleanupStaleTempBackups() async {
    try {
      final dir = await getTemporaryDirectory();
      await for (final entity in dir.list()) {
        if (entity is File &&
            p.basename(entity.path).startsWith('body_frame_backup_')) {
          await entity.delete();
        }
      }
    } catch (_) {
      // 임시 파일 정리는 best effort — 실패해도 기능에 영향 없음.
    }
  }

  void _setStatus(_OpStatus status, String message) {
    if (!mounted) return;
    setState(() {
      _status = status;
      _statusMessage = message;
    });
  }

  Future<String> _writeToTempFile(List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final fileName = 'body_frame_backup_${DateTime.now().millisecondsSinceEpoch}.zip';
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _createFullBackup() async {
    _setStatus(_OpStatus.busy, '전체 백업 생성 중...');
    try {
      final bytes = await ref.read(backupServiceProvider).buildBackup();
      final path = await _writeToTempFile(bytes);
      setState(() => _lastBackupFilePath = path);
      _setStatus(_OpStatus.success, '전체 백업이 생성되었습니다 (${bytes.length}바이트)');
    } catch (e) {
      _setStatus(_OpStatus.failure, '백업 생성에 실패했습니다: $e');
    }
  }

  Future<void> _createMemberBackup() async {
    final memberId = _selectedMemberId;
    if (memberId == null) {
      _setStatus(_OpStatus.failure, '백업할 회원을 선택해 주세요');
      return;
    }
    _setStatus(_OpStatus.busy, '회원별 백업 생성 중...');
    try {
      final bytes = await ref.read(backupServiceProvider).buildBackup(memberId: memberId);
      final path = await _writeToTempFile(bytes);
      setState(() => _lastBackupFilePath = path);
      _setStatus(_OpStatus.success, '회원별 백업이 생성되었습니다 (${bytes.length}바이트)');
    } catch (e) {
      _setStatus(_OpStatus.failure, '백업 생성에 실패했습니다: $e');
    }
  }

  Future<void> _saveBackupToDevice() async {
    final path = _lastBackupFilePath;
    if (path == null) return;
    final location = await getSaveLocation(
      suggestedName: p.basename(path),
      acceptedTypeGroups: const [XTypeGroup(label: 'zip', extensions: ['zip'])],
    );
    if (location == null) return;
    await File(path).copy(location.path);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('저장했습니다')));
  }

  Future<void> _shareBackup() async {
    final path = _lastBackupFilePath;
    if (path == null) return;
    await Share.shareXFiles(
      [XFile(path)],
      text: '체형 변화 기록 백업 파일에는 회원 정보와 사진이 포함되어 있습니다. 안전하게 보관해 주세요.',
    );
  }

  Future<void> _pickAndPrepareRestore() async {
    final file = await openFile(
      acceptedTypeGroups: const [XTypeGroup(label: 'zip', extensions: ['zip'])],
    );
    if (file == null) return;

    _setStatus(_OpStatus.busy, '백업 파일 검증 중...');
    try {
      final bytes = await file.readAsBytes();
      final preview = await ref.read(backupServiceProvider).prepareRestore(bytes);
      _setStatus(
        _OpStatus.idle,
        '검증 완료: 회원 ${preview.memberCount}명 / 사진 ${preview.photoCount}장',
      );
      if (!mounted) return;
      await _showRestoreDialog(preview);
    } catch (e) {
      _setStatus(_OpStatus.failure, '백업 파일이 올바르지 않습니다: $e');
    }
  }

  Future<void> _showRestoreDialog(RestorePreview preview) async {
    var mode = RestoreMode.append;
    final decision = await showDialog<RestoreMode>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('복원 미리보기'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('회원 ${preview.memberCount}명'),
                  Text('촬영 기록 ${preview.recordCount}건'),
                  Text('사진 ${preview.photoCount}장'),
                  if (preview.hasDuplicates) ...[
                    const SizedBox(height: 8),
                    Text(
                      '주의: 기존 앱에 이미 존재하는 회원 ${preview.duplicateMemberIds.length}명이 백업에 포함되어 있습니다.',
                      key: const ValueKey('backup.restore.duplicate.warning'),
                      style: const TextStyle(color: Colors.orange),
                    ),
                  ],
                  const Divider(height: 24),
                  _SelectableRestoreModeTile(
                    keyValue: 'backup.restore.mode.append.radio',
                    label: '추가 (기존 데이터 유지, 중복은 새 항목으로 추가)',
                    selected: mode == RestoreMode.append,
                    onTap: () => setDialogState(() => mode = RestoreMode.append),
                  ),
                  _SelectableRestoreModeTile(
                    keyValue: 'backup.restore.mode.replace.radio',
                    label: '교체 (기존 데이터를 모두 삭제하고 백업으로 대체)',
                    selected: mode == RestoreMode.replace,
                    onTap: () => setDialogState(() => mode = RestoreMode.replace),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  key: const ValueKey('backup.restore.cancel.button'),
                  onPressed: () => Navigator.of(dialogContext).pop(null),
                  child: const Text('취소'),
                ),
                FilledButton(
                  key: const ValueKey('backup.restore.confirm.button'),
                  onPressed: () => Navigator.of(dialogContext).pop(mode),
                  child: const Text('다음'),
                ),
              ],
            );
          },
        );
      },
    );

    if (decision == null) {
      await ref.read(backupServiceProvider).discardRestore(preview);
      _setStatus(_OpStatus.idle, '복원이 취소되었습니다');
      return;
    }

    if (decision == RestoreMode.replace) {
      final confirmed = await _confirmReplace();
      if (!confirmed) {
        await ref.read(backupServiceProvider).discardRestore(preview);
        _setStatus(_OpStatus.idle, '복원이 취소되었습니다');
        return;
      }
    }

    await _applyRestore(preview, decision);
  }

  Future<bool> _confirmReplace() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('데이터 교체 확인'),
        content: const Text(
          '현재 기기의 모든 회원 정보와 사진이 삭제되고 백업 파일의 내용으로 교체됩니다. '
          '이 작업은 되돌릴 수 없습니다. 계속하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const ValueKey('backup.restore.replace.finalConfirm.button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('교체'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _applyRestore(RestorePreview preview, RestoreMode mode) async {
    _setStatus(_OpStatus.busy, '복원 적용 중...');
    try {
      final outcome = await ref.read(backupServiceProvider).applyRestore(preview, mode: mode);
      if (outcome.success) {
        ref.invalidate(backupMemberListProvider);
        ref.invalidate(storageUsageProvider);
        _setStatus(
          outcome.error == null ? _OpStatus.success : _OpStatus.failure,
          outcome.error ??
              '복원 완료: 회원 ${outcome.memberCount}명 / 사진 ${outcome.photoCount}장',
        );
      } else {
        _setStatus(_OpStatus.failure, outcome.error ?? '복원에 실패했습니다');
      }
    } catch (e) {
      _setStatus(_OpStatus.failure, '복원 중 오류가 발생했습니다: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(backupMemberListProvider);

    return Semantics(
      identifier: BackupRestoreScreen.screenId,
      container: true,
      label: '백업 및 복원',
      child: Scaffold(
        key: const ValueKey(BackupRestoreScreen.screenId),
        appBar: AppBar(title: const Text('백업 및 복원')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              key: const ValueKey('backup.warning.banner'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_outlined, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '백업 파일에는 회원 정보와 체형 사진이 포함됩니다. 안전한 곳에 보관하고 '
                      '타인에게 전달하지 않도록 주의하세요.',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('전체 백업', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ElevatedButton(
              key: const ValueKey('backup.create.button'),
              onPressed: _status == _OpStatus.busy ? null : _createFullBackup,
              child: const Text('전체 백업 생성'),
            ),
            const SizedBox(height: 24),
            const Text('회원별 백업', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            membersAsync.when(
              data: (members) => DropdownButton<String>(
                key: const ValueKey('backup.member.select.dropdown'),
                hint: const Text('회원 선택'),
                value: _selectedMemberId,
                items: members
                    .map((m) => DropdownMenuItem(
                          value: m.member.id,
                          child: Text(m.member.name),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedMemberId = v),
              ),
              loading: () => const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (e, st) => const Text('회원 목록을 불러오지 못했습니다'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              key: const ValueKey('backup.member.create.button'),
              onPressed: _status == _OpStatus.busy ? null : _createMemberBackup,
              child: const Text('선택 회원 백업 생성'),
            ),
            if (_lastBackupFilePath != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('backup.export.save.button'),
                    onPressed: _saveBackupToDevice,
                    icon: const Icon(Icons.save_alt),
                    label: const Text('기기에 저장'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('backup.export.share.button'),
                    onPressed: _shareBackup,
                    icon: const Icon(Icons.share),
                    label: const Text('공유'),
                  ),
                ],
              ),
            ],
            const Divider(height: 32),
            const Text('복원', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('backup.restore.button'),
              onPressed: _status == _OpStatus.busy ? null : _pickAndPrepareRestore,
              child: const Text('백업 파일에서 복원'),
            ),
            const SizedBox(height: 16),
            _StatusRow(status: _status, message: _statusMessage, onRetry: _createFullBackup),
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final _OpStatus status;
  final String message;
  final VoidCallback onRetry;

  const _StatusRow({required this.status, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    switch (status) {
      case _OpStatus.idle:
        color = Colors.grey;
        icon = Icons.hourglass_empty;
      case _OpStatus.busy:
        color = Colors.blue;
        icon = Icons.sync;
      case _OpStatus.success:
        color = Colors.green;
        icon = Icons.check_circle_outline;
      case _OpStatus.failure:
        color = Colors.red;
        icon = Icons.error_outline;
    }

    return Semantics(
      identifier: 'backup.progress.status',
      label: message,
      child: Row(
        key: const ValueKey('backup.progress.status'),
        children: [
          if (status == _OpStatus.busy)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: TextStyle(color: color))),
          if (status == _OpStatus.failure)
            TextButton(
              key: const ValueKey('backup.progress.retry.button'),
              onPressed: onRetry,
              child: const Text('재시도'),
            ),
        ],
      ),
    );
  }
}

/// 복원 모드 선택 항목. RadioListTile의 deprecated groupValue/onChanged 대신
/// 일반 ListTile + 선택 아이콘으로 라디오 선택 UX를 구현한다.
class _SelectableRestoreModeTile extends StatelessWidget {
  final String keyValue;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SelectableRestoreModeTile({
    required this.keyValue,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: keyValue,
      label: label,
      selected: selected,
      button: true,
      child: ListTile(
        key: ValueKey(keyValue),
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        ),
        title: Text(label),
        onTap: onTap,
      ),
    );
  }
}
