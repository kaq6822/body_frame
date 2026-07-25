import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models/models.dart';
import '../../core/providers.dart';
import '../../core/services/app_image_picker.dart';
import '../../core/services/app_logger.dart';
import '../../core/widgets/grid_painter.dart';
import 'services/grid_photo_composer.dart';
import 'services/photo_export_sink.dart';

/// 원본 사진 보기 화면.
///
/// 확대/이동(원본 비율 유지, BoxFit.contain 기반), 촬영 방향/촬영일/메모
/// 수정, 사진 교체, 내보내기(gal), 공유(share_plus), 삭제(확인 절차)를
/// 제공한다. 촬영일은 [PhotoRecord]에 속하므로 편집 시 같은 기록의 다른
/// 사진에도 반영된다.
class PhotoViewScreen extends ConsumerWidget {
  static const screenId = 'screen.records.photo';

  final String memberId;
  final String recordId;
  final String photoId;

  const PhotoViewScreen({
    super.key,
    required this.memberId,
    required this.recordId,
    required this.photoId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailKey = (
      memberId: memberId,
      recordId: recordId,
      photoId: photoId,
    );
    final async = ref.watch(_photoDetailProvider(detailKey));

    return Semantics(
      identifier: screenId,
      container: true,
      label: '원본 사진 보기',
      child: Scaffold(
        key: const ValueKey(screenId),
        appBar: AppBar(title: const Text('원본 사진 보기')),
        body: async.when(
          data: (data) => _PhotoViewBody(detailKey: detailKey, data: data),
          loading: () => const _PaneStatus(
            key: ValueKey('screen.records.photo.status'),
            state: _OpState.running,
          ),
          error: (error, stack) => _PaneStatus(
            key: const ValueKey('screen.records.photo.status'),
            state: _OpState.failure,
            message: '사진 정보를 불러오지 못했습니다.',
            onRetry: () => ref.invalidate(_photoDetailProvider(detailKey)),
          ),
        ),
      ),
    );
  }
}

class _PhotoDetailData {
  final BodyPhoto photo;
  final PhotoRecord record;

  const _PhotoDetailData({required this.photo, required this.record});
}

/// [photoId]에 해당하는 사진을 찾을 수 없을 때 던진다.
class PhotoNotFoundException implements Exception {
  final String photoId;

  const PhotoNotFoundException(this.photoId);

  @override
  String toString() => '사진을 찾을 수 없습니다: $photoId';
}

typedef _PhotoDetailKey = ({String memberId, String recordId, String photoId});

final _photoDetailProvider = FutureProvider.autoDispose
    .family<_PhotoDetailData, _PhotoDetailKey>((ref, key) async {
      final photoRepo = ref.watch(bodyPhotoRepositoryProvider);
      final recordRepo = ref.watch(photoRecordRepositoryProvider);
      final photo = await photoRepo.getById(key.photoId);
      if (photo == null || photo.recordId != key.recordId) {
        throw PhotoNotFoundException(key.photoId);
      }
      final record = await recordRepo.getById(key.recordId);
      if (record == null || record.memberId != key.memberId) {
        throw RecordNotFoundException(key.recordId);
      }
      return _PhotoDetailData(photo: photo, record: record);
    });

/// [recordId]에 해당하는 촬영 기록을 찾을 수 없을 때 던진다.
class RecordNotFoundException implements Exception {
  final String recordId;

  const RecordNotFoundException(this.recordId);

  @override
  String toString() => '촬영 기록을 찾을 수 없습니다: $recordId';
}

class PhotoReplacementOwnershipException implements Exception {
  const PhotoReplacementOwnershipException();
}

enum _OpState { idle, running, success, failure }

class _PhotoViewBody extends ConsumerStatefulWidget {
  final _PhotoDetailKey detailKey;
  final _PhotoDetailData data;

  const _PhotoViewBody({required this.detailKey, required this.data});

  @override
  ConsumerState<_PhotoViewBody> createState() => _PhotoViewBodyState();
}

class _PhotoViewBodyState extends ConsumerState<_PhotoViewBody> {
  late final TextEditingController _memoController;
  late BodyDirection _direction;

  _OpState _memoState = _OpState.idle;
  _OpState _dateState = _OpState.idle;
  _OpState _directionState = _OpState.idle;
  _OpState _replaceState = _OpState.idle;
  _OpState _exportState = _OpState.idle;
  _OpState _shareState = _OpState.idle;
  _OpState _deleteState = _OpState.idle;
  bool _includeGridOnExport = false;
  XFile? _pendingReplacement;
  bool _recoveringLostReplacement = false;
  bool _lostReplacementRecoveryScheduled = false;

  /// 이 화면에서 데이터가 실제로 바뀌었는지(뒤로 나갈 때 상위 화면에 알림).
  bool _hasChanges = false;

  ImagePickerRequestContext get _pickerContext =>
      ImagePickerRequestContext.photoReplacement(
        memberId: widget.detailKey.memberId,
        recordId: widget.detailKey.recordId,
        photoId: widget.detailKey.photoId,
      );

  @override
  void initState() {
    super.initState();
    _memoController = TextEditingController(text: widget.data.photo.memo ?? '');
    _direction = widget.data.photo.direction;
    ref.listenManual<RecoveredImagePickerSelection?>(
      appImagePickerCoordinatorProvider,
      (previous, next) {
        if (next?.context == _pickerContext) {
          _scheduleLostReplacementRecovery();
        }
      },
      fireImmediately: true,
    );
  }

  void _scheduleLostReplacementRecovery() {
    if (_lostReplacementRecoveryScheduled) return;
    _lostReplacementRecoveryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lostReplacementRecoveryScheduled = false;
      if (mounted) unawaited(_recoverLostReplacement());
    });
  }

  @override
  void dispose() {
    _memoController.dispose();
    super.dispose();
  }

  void _invalidate() {
    ref.invalidate(_photoDetailProvider(widget.detailKey));
  }

  Future<void> _saveMemo() async {
    setState(() => _memoState = _OpState.running);
    final photo = widget.data.photo;
    final logger = ref.read(appLoggerProvider);
    try {
      final repo = ref.read(bodyPhotoRepositoryProvider);
      await repo.update(
        photo.copyWith(
          memo: _memoController.text.trim().isEmpty
              ? null
              : _memoController.text.trim(),
        ),
      );
      logger.phase(
        'photo.memo.save',
        LogPhase.success,
        context: {'id': photo.id},
      );
      if (!mounted) return;
      _hasChanges = true;
      setState(() => _memoState = _OpState.success);
      _invalidate();
    } catch (err) {
      logger.phase(
        'photo.memo.save',
        LogPhase.failure,
        context: {'id': photo.id},
      );
      if (!mounted) return;
      setState(() => _memoState = _OpState.failure);
    }
  }

  Future<void> _changeDirection(BodyDirection? newDirection) async {
    if (newDirection == null || newDirection == _direction) return;
    final previous = _direction;
    setState(() {
      _direction = newDirection;
      _directionState = _OpState.running;
    });
    final photo = widget.data.photo;
    final logger = ref.read(appLoggerProvider);
    try {
      final repo = ref.read(bodyPhotoRepositoryProvider);
      await repo.update(photo.copyWith(direction: newDirection));
      logger.phase(
        'photo.direction.save',
        LogPhase.success,
        context: {'id': photo.id},
      );
      if (!mounted) return;
      _hasChanges = true;
      setState(() => _directionState = _OpState.success);
      _invalidate();
    } catch (err) {
      logger.phase(
        'photo.direction.save',
        LogPhase.failure,
        context: {'id': photo.id},
      );
      if (!mounted) return;
      setState(() {
        _direction = previous;
        _directionState = _OpState.failure;
      });
    }
  }

  Future<void> _editShotDate() async {
    final record = widget.data.record;
    final picked = await showDatePicker(
      context: context,
      initialDate: record.shotAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;

    setState(() => _dateState = _OpState.running);
    final logger = ref.read(appLoggerProvider);
    try {
      final repo = ref.read(photoRecordRepositoryProvider);
      await repo.update(
        record.copyWith(shotAt: picked, updatedAt: DateTime.now()),
      );
      logger.phase(
        'record.date.save',
        LogPhase.success,
        context: {'id': record.id},
      );
      if (!mounted) return;
      _hasChanges = true;
      setState(() => _dateState = _OpState.success);
      _invalidate();
    } catch (err) {
      logger.phase(
        'record.date.save',
        LogPhase.failure,
        context: {'id': record.id},
      );
      if (!mounted) return;
      setState(() => _dateState = _OpState.failure);
    }
  }

  Future<void> _replacePhoto() async {
    final XFile? picked;
    try {
      picked = await ref
          .read(appImagePickerCoordinatorProvider.notifier)
          .pickImage(context: _pickerContext, source: ImageSource.gallery);
    } catch (err) {
      setState(() => _replaceState = _OpState.failure);
      return;
    }
    if (picked == null) return;
    _stageReplacement(picked);
  }

  Future<void> _recoverLostReplacement() async {
    if (!mounted || _recoveringLostReplacement) return;
    final coordinator = ref.read(appImagePickerCoordinatorProvider.notifier);
    final recovered = coordinator.recoveredFor(_pickerContext);
    if (recovered == null) return;
    _recoveringLostReplacement = true;
    try {
      final picked = recovered.lastFile;
      if (picked == null) {
        throw StateError('복구할 교체 사진이 없습니다.');
      }
      if (!mounted) return;
      _stageReplacement(picked);
      await coordinator.acknowledgeRecovered(_pickerContext);
    } catch (err) {
      if (mounted) setState(() => _replaceState = _OpState.failure);
    } finally {
      _recoveringLostReplacement = false;
    }
  }

  void _stageReplacement(XFile picked) {
    if (!mounted) return;
    setState(() {
      _pendingReplacement = picked;
      _replaceState = _OpState.idle;
    });
  }

  void _cancelPendingReplacement() {
    setState(() {
      _pendingReplacement = null;
      _replaceState = _OpState.idle;
    });
  }

  Future<void> _confirmPendingReplacement() async {
    final picked = _pendingReplacement;
    if (picked == null) return;
    await _replaceWithPicked(picked);
  }

  Future<void> _replaceWithPicked(XFile picked) async {
    if (!mounted) return;
    setState(() => _replaceState = _OpState.running);
    final originalPhoto = widget.data.photo;
    final logger = ref.read(appLoggerProvider);
    logger.phase(
      'photo.replace',
      LogPhase.start,
      context: {'id': originalPhoto.id},
    );
    String? newlySavedPath;
    try {
      final bytes = await picked.readAsBytes();
      final size = await _decodeImageSize(bytes);
      final orientation = await _readOrientation(bytes);
      final storage = ref.read(photoStorageServiceProvider);
      final newPath = await storage.saveOriginal(
        memberId: widget.detailKey.memberId,
        sourcePath: picked.path,
      );
      newlySavedPath = newPath;
      final repo = ref.read(bodyPhotoRepositoryProvider);
      final latestPhoto = await repo.getById(widget.detailKey.photoId);
      final latestRecord = await ref
          .read(photoRecordRepositoryProvider)
          .getById(widget.detailKey.recordId);
      if (latestPhoto == null ||
          latestPhoto.recordId != widget.detailKey.recordId ||
          latestRecord == null ||
          latestRecord.memberId != widget.detailKey.memberId) {
        throw const PhotoReplacementOwnershipException();
      }
      await repo.update(
        latestPhoto.copyWith(
          filePath: newPath,
          width: size.$1,
          height: size.$2,
          orientation: orientation,
        ),
      );
      logger.phase(
        'photo.replace',
        LogPhase.success,
        context: {'id': originalPhoto.id},
      );
      if (!mounted) return;
      _hasChanges = true;
      setState(() {
        _pendingReplacement = null;
        _replaceState = _OpState.success;
      });
      _invalidate();
    } catch (err) {
      if (newlySavedPath != null) {
        try {
          await ref
              .read(photoStorageServiceProvider)
              .deleteFile(newlySavedPath);
        } catch (_) {
          logger.warn(
            'photo.replace.cleanup.failure',
            context: {'id': originalPhoto.id},
          );
        }
      }
      logger.phase(
        'photo.replace',
        LogPhase.failure,
        context: {'id': originalPhoto.id},
      );
      if (!mounted) return;
      setState(() => _replaceState = _OpState.failure);
    }
  }

  Future<void> _export() async {
    setState(() => _exportState = _OpState.running);
    final photo = widget.data.photo;
    final includeGrid = _includeGridOnExport;
    final logger = ref.read(appLoggerProvider);
    logger.phase(
      'photo.export',
      LogPhase.start,
      context: {'id': photo.id, 'grid': includeGrid},
    );
    try {
      final sink = ref.read(photoExportSinkProvider);
      final name =
          'body_frame_${photo.id}_${DateTime.now().microsecondsSinceEpoch}';
      if (includeGrid) {
        final sourceBytes = await File(photo.filePath).readAsBytes();
        final png = await ref
            .read(gridPhotoComposerProvider)
            .compose(sourceBytes, photo.gridSettings);
        await sink.savePng(png, name: '${name}_grid');
      } else {
        await sink.saveOriginalFile(photo.filePath, name: name);
      }
      logger.phase(
        'photo.export',
        LogPhase.success,
        context: {'id': photo.id, 'grid': includeGrid},
      );
      if (!mounted) return;
      setState(() => _exportState = _OpState.success);
    } catch (err) {
      logger.phase(
        'photo.export',
        LogPhase.failure,
        context: {'id': photo.id, 'grid': includeGrid},
      );
      if (!mounted) return;
      setState(() => _exportState = _OpState.failure);
    }
  }

  Future<void> _share() async {
    setState(() => _shareState = _OpState.running);
    final photo = widget.data.photo;
    final logger = ref.read(appLoggerProvider);
    try {
      await Share.shareXFiles([XFile(photo.filePath)]);
      logger.phase('photo.share', LogPhase.success, context: {'id': photo.id});
      if (!mounted) return;
      setState(() => _shareState = _OpState.success);
    } catch (err) {
      logger.phase('photo.share', LogPhase.failure, context: {'id': photo.id});
      if (!mounted) return;
      setState(() => _shareState = _OpState.failure);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('records.viewer.delete.confirm.dialog'),
        title: const Text('사진 삭제'),
        content: const Text('이 사진을 삭제합니다. 삭제 후에는 복구할 수 없습니다.'),
        actions: [
          TextButton(
            key: const ValueKey('records.viewer.delete.cancel.button'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const ValueKey('records.viewer.delete.confirm.button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _deletePhoto();
  }

  Future<void> _deletePhoto() async {
    setState(() => _deleteState = _OpState.running);
    final photo = widget.data.photo;
    final logger = ref.read(appLoggerProvider);
    logger.phase('photo.delete', LogPhase.start, context: {'id': photo.id});
    try {
      final repo = ref.read(bodyPhotoRepositoryProvider);
      await repo.delete(photo.id);
      logger.phase('photo.delete', LogPhase.success, context: {'id': photo.id});
      if (!mounted) return;
      setState(() => _deleteState = _OpState.success);
      Navigator.of(context).pop(true);
    } catch (err) {
      logger.phase('photo.delete', LogPhase.failure, context: {'id': photo.id});
      if (!mounted) return;
      setState(() => _deleteState = _OpState.failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.data.photo;
    final record = widget.data.record;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && result == null && _hasChanges) {
          // 시스템 뒤로가기(스와이프 등)로 나갈 때도 변경 사실을 남긴다.
          // 이미 pop된 뒤라 결과 전달은 불가하므로 상위 화면은 복귀 시
          // 명시적 새로고침 버튼으로 갱신할 수 있다.
        }
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Semantics(
                      identifier: 'records.viewer.image',
                      label: '${photo.direction.label} 원본 사진, 확대 및 이동 가능',
                      child: PhotoView.customChild(
                        key: const ValueKey('records.viewer.image'),
                        backgroundDecoration: const BoxDecoration(
                          color: Colors.transparent,
                        ),
                        minScale: PhotoViewComputedScale.contained,
                        maxScale: PhotoViewComputedScale.covered * 3,
                        initialScale: PhotoViewComputedScale.contained,
                        // Flutter의 Image.file은 JPEG EXIF orientation을 디코딩
                        // 단계에서 자동 반영하므로 수동 회전(RotatedBox)을 더하면
                        // 이중 회전이 된다. orientation 값은 메타데이터로만 보존한다.
                        child: Image.file(
                          File(photo.filePath),
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stack) => const Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                    ),
                    if (_includeGridOnExport)
                      Semantics(
                        identifier: 'records.viewer.export.grid.preview',
                        label: '내보내기에 합성할 격자 미리보기',
                        child: IgnorePointer(
                          child: CustomPaint(
                            key: const ValueKey(
                              'records.viewer.export.grid.preview',
                            ),
                            painter: GridPainter(
                              photo.gridSettings.copyWith(visible: true),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('방향: '),
                Semantics(
                  identifier: 'records.viewer.direction.field',
                  label: '촬영 방향 선택',
                  child: DropdownButton<BodyDirection>(
                    key: const ValueKey('records.viewer.direction.field'),
                    value: _direction,
                    items: [
                      for (final d in BodyDirection.values)
                        DropdownMenuItem(value: d, child: Text(d.label)),
                    ],
                    onChanged: _directionState == _OpState.running
                        ? null
                        : _changeDirection,
                  ),
                ),
                const SizedBox(width: 8),
                _InlineStatus(
                  id: 'records.viewer.direction.status',
                  state: _directionState,
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '촬영일: ${DateFormat('yyyy-MM-dd').format(record.shotAt)}',
                  ),
                ),
                Semantics(
                  identifier: 'records.viewer.date.edit.button',
                  button: true,
                  label: '촬영일 수정',
                  child: IconButton(
                    key: const ValueKey('records.viewer.date.edit.button'),
                    onPressed: _editShotDate,
                    icon: const Icon(Icons.edit_calendar_outlined),
                  ),
                ),
                _InlineStatus(
                  id: 'records.viewer.date.status',
                  state: _dateState,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('사진 메모', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Semantics(
              identifier: 'records.viewer.memo.field',
              textField: true,
              label: '사진 메모 입력',
              child: TextField(
                key: const ValueKey('records.viewer.memo.field'),
                controller: _memoController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: '메모를 입력하세요',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Semantics(
                  identifier: 'records.viewer.memo.save.button',
                  button: true,
                  label: '사진 메모 저장',
                  child: ElevatedButton(
                    key: const ValueKey('records.viewer.memo.save.button'),
                    onPressed: _memoState == _OpState.running
                        ? null
                        : _saveMemo,
                    child: const Text('메모 저장'),
                  ),
                ),
                const SizedBox(width: 12),
                _InlineStatus(
                  id: 'records.viewer.memo.status',
                  state: _memoState,
                ),
              ],
            ),
            Semantics(
              identifier: 'records.viewer.export.grid.toggle',
              label: '내보내기에 격자 합성',
              value: _includeGridOnExport ? '켜짐' : '꺼짐',
              child: SwitchListTile(
                key: const ValueKey('records.viewer.export.grid.toggle'),
                contentPadding: EdgeInsets.zero,
                title: const Text('내보내기에 격자 합성'),
                subtitle: const Text('원본은 변경하지 않고 격자가 포함된 새 PNG를 만듭니다.'),
                value: _includeGridOnExport,
                onChanged: _exportState == _OpState.running
                    ? null
                    : (value) => setState(() {
                        _includeGridOnExport = value;
                        _exportState = _OpState.idle;
                      }),
              ),
            ),
            if (_pendingReplacement != null) ...[
              const SizedBox(height: 8),
              Semantics(
                identifier: 'records.viewer.replace.pending.card',
                container: true,
                label: '교체할 사진 미리보기와 적용 확인',
                child: Card(
                  key: const ValueKey('records.viewer.replace.pending.card'),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Semantics(
                            identifier: 'records.viewer.replace.pending.image',
                            image: true,
                            label: '교체할 사진 미리보기',
                            child: Image.file(
                              File(_pendingReplacement!.path),
                              key: const ValueKey(
                                'records.viewer.replace.pending.image',
                              ),
                              width: 88,
                              height: 88,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  const SizedBox(
                                    width: 88,
                                    height: 88,
                                    child: Icon(Icons.broken_image_outlined),
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '이 사진으로 교체할까요?',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              const Text('적용하기 전까지 기존 원본은 변경되지 않습니다.'),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: [
                                  Semantics(
                                    identifier:
                                        'records.viewer.replace.cancel.button',
                                    button: true,
                                    enabled: _replaceState != _OpState.running,
                                    label: '사진 교체 취소',
                                    child: TextButton(
                                      key: const ValueKey(
                                        'records.viewer.replace.cancel.button',
                                      ),
                                      onPressed:
                                          _replaceState == _OpState.running
                                          ? null
                                          : _cancelPendingReplacement,
                                      child: const Text('취소'),
                                    ),
                                  ),
                                  Semantics(
                                    identifier:
                                        'records.viewer.replace.confirm.button',
                                    button: true,
                                    enabled: _replaceState != _OpState.running,
                                    label: '사진 교체 적용',
                                    child: FilledButton(
                                      key: const ValueKey(
                                        'records.viewer.replace.confirm.button',
                                      ),
                                      onPressed:
                                          _replaceState == _OpState.running
                                          ? null
                                          : _confirmPendingReplacement,
                                      child: const Text('교체 적용'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const Divider(height: 32),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _ActionButton(
                  id: 'records.viewer.replace.button',
                  label: '사진 교체',
                  icon: Icons.image_outlined,
                  state: _replaceState,
                  onPressed: _replacePhoto,
                ),
                _ActionButton(
                  id: 'records.viewer.export.button',
                  label: _includeGridOnExport ? '격자 합성 내보내기' : '내보내기',
                  icon: Icons.save_alt_outlined,
                  state: _exportState,
                  onPressed: _export,
                ),
                _ActionButton(
                  id: 'records.viewer.share.button',
                  label: '공유',
                  icon: Icons.ios_share_outlined,
                  state: _shareState,
                  onPressed: _share,
                ),
                _ActionButton(
                  id: 'records.viewer.delete.button',
                  label: '삭제',
                  icon: Icons.delete_outline,
                  state: _deleteState,
                  onPressed: _confirmDelete,
                  isDestructive: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<(int, int)> _decodeImageSize(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return (frame.image.width, frame.image.height);
}

Future<int> _readOrientation(Uint8List bytes) async {
  try {
    final tags = await readExifFromBytes(bytes);
    final tag = tags['Image Orientation'];
    if (tag == null) return 1;
    final match = RegExp(r'\d+').firstMatch(tag.printable);
    return match != null ? int.parse(match.group(0)!) : 1;
  } catch (_) {
    return 1;
  }
}

class _PaneStatus extends StatelessWidget {
  final _OpState state;
  final String? message;
  final VoidCallback? onRetry;

  const _PaneStatus({
    super.key,
    required this.state,
    this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (state == _OpState.running) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline),
            const SizedBox(height: 8),
            Text(message ?? '오류가 발생했습니다.', textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onRetry, child: const Text('다시 시도')),
            ],
          ],
        ),
      ),
    );
  }
}

class _InlineStatus extends StatelessWidget {
  final String id;
  final _OpState state;

  const _InlineStatus({required this.id, required this.state});

  @override
  Widget build(BuildContext context) {
    Widget child;
    String label;
    switch (state) {
      case _OpState.idle:
        child = const SizedBox(width: 16, height: 16);
        label = '대기';
        break;
      case _OpState.running:
        child = const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
        label = '진행 중';
        break;
      case _OpState.success:
        child = Icon(
          Icons.check_circle,
          size: 16,
          color: Theme.of(context).colorScheme.primary,
        );
        label = '완료';
        break;
      case _OpState.failure:
        child = Icon(
          Icons.error,
          size: 16,
          color: Theme.of(context).colorScheme.error,
        );
        label = '실패';
        break;
    }
    return Semantics(
      identifier: id,
      label: label,
      child: SizedBox(key: ValueKey(id), width: 16, height: 16, child: child),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String id;
  final String label;
  final IconData icon;
  final _OpState state;
  final VoidCallback onPressed;
  final bool isDestructive;

  const _ActionButton({
    required this.id,
    required this.label,
    required this.icon,
    required this.state,
    required this.onPressed,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final busy = state == _OpState.running;
    final color = isDestructive ? Theme.of(context).colorScheme.error : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          identifier: id,
          button: true,
          label: label,
          child: OutlinedButton.icon(
            key: ValueKey(id),
            onPressed: busy ? null : onPressed,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(icon, color: color),
            label: Text(
              label,
              style: color != null ? TextStyle(color: color) : null,
            ),
          ),
        ),
        _InlineStatus(id: '$id.status', state: state),
      ],
    );
  }
}
