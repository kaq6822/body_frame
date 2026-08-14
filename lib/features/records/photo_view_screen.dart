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
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/photo_grid_overlay.dart';
import 'providers/records_providers.dart';
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

  final String recordId;
  final String photoId;

  const PhotoViewScreen({
    super.key,
    required this.recordId,
    required this.photoId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailKey = (recordId: recordId, photoId: photoId);
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

typedef _PhotoDetailKey = ({String recordId, String photoId});

final _photoDetailProvider = FutureProvider.autoDispose
    .family<_PhotoDetailData, _PhotoDetailKey>((ref, key) async {
      final photoRepo = ref.watch(bodyPhotoRepositoryProvider);
      final recordRepo = ref.watch(photoRecordRepositoryProvider);
      final photo = await photoRepo.getById(key.photoId);
      if (photo == null || photo.recordId != key.recordId) {
        throw PhotoNotFoundException(key.photoId);
      }
      final record = await recordRepo.getById(key.recordId);
      if (record == null) {
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
  _OpState _gridState = _OpState.idle;

  /// 내보내기·공유할 이미지에 격자를 합성할지. 앱 안에서 늘 격자와 함께 보므로
  /// 내보낸 이미지도 같은 모습이 기본이다.
  bool _includeGridOnExport = true;

  /// 이 사진에 적용된 격자 설정. 원본 픽셀에는 굽지 않고 메타데이터로만 남기므로
  /// 촬영 후에도 여기서 조정할 수 있다.
  late GridSettings _grid;

  /// 격자 조정 패널을 펼친 상태인지. 격자 자체는 기본으로 켜져 있으므로 이
  /// 값은 세부 설정 노출 여부만 결정한다.
  bool _gridEditing = false;
  XFile? _pendingReplacement;
  bool _recoveringLostReplacement = false;
  bool _lostReplacementRecoveryScheduled = false;

  /// 이 화면에서 데이터가 실제로 바뀌었는지(뒤로 나갈 때 상위 화면에 알림).
  bool _hasChanges = false;

  ImagePickerRequestContext get _pickerContext =>
      ImagePickerRequestContext.photoReplacement(
        recordId: widget.detailKey.recordId,
        photoId: widget.detailKey.photoId,
      );

  @override
  void initState() {
    super.initState();
    _memoController = TextEditingController(text: widget.data.photo.memo ?? '');
    _direction = widget.data.photo.direction;
    _grid = widget.data.photo.gridSettings;
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
    // 기록 목록과 홈 카메라의 썸네일이 같은 provider를 읽는다. 사진을 바꾸거나
    // 지운 사실을 알리지 않으면 목록이 옛 사진을 계속 그린다.
    ref.invalidate(timelineProvider);
  }

  Future<void> _saveMemo() async {
    setState(() => _memoState = _OpState.running);
    final photo = widget.data.photo;
    final logger = ref.read(appLoggerProvider);
    try {
      final repo = ref.read(bodyPhotoRepositoryProvider);
      final memo = _memoController.text.trim();
      await repo.update(
        photo.copyWith(
          memo: memo.isEmpty ? null : memo,
          clearMemo: memo.isEmpty,
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
        shotAt: widget.data.record.shotAt,
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
          latestRecord == null) {
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

  /// 조정한 격자 설정을 이 사진의 메타데이터로 저장한다.
  ///
  /// 원본 파일은 건드리지 않는다. 촬영 당시 설정은 리포지토리가 그대로 보존하므로
  /// 몇 번을 조정해도 되돌릴 기준점은 남는다.
  Future<void> _saveGrid() async {
    setState(() => _gridState = _OpState.running);
    final photo = widget.data.photo;
    final logger = ref.read(appLoggerProvider);
    logger.phase(
      'photo.grid.update',
      LogPhase.start,
      context: {'id': photo.id},
    );
    try {
      final repo = ref.read(bodyPhotoRepositoryProvider);
      await repo.update(photo.copyWith(gridSettings: _grid));
      logger.phase(
        'photo.grid.update',
        LogPhase.success,
        context: {'id': photo.id},
      );
      _hasChanges = true;
      if (!mounted) return;
      setState(() => _gridState = _OpState.success);
      _invalidate();
    } catch (err) {
      logger.phase(
        'photo.grid.update',
        LogPhase.failure,
        context: {'id': photo.id},
      );
      if (!mounted) return;
      setState(() => _gridState = _OpState.failure);
    }
  }

  /// 촬영 당시 격자 설정으로 되돌린다.
  Future<void> _revertGrid() async {
    setState(() => _grid = widget.data.photo.captureGridSettings);
    await _saveGrid();
  }

  /// 내보내기·공유 결과에 격자를 합성할지.
  ///
  /// 격자를 숨긴 상태에서는 화면에 없는 격자가 결과물에만 찍혀 나오게 되므로
  /// 토글이 켜져 있어도 합성하지 않는다(토글 자체도 그때는 잠긴다).
  bool get _willComposeGrid => _includeGridOnExport && _grid.visible;

  Future<void> _export() async {
    setState(() => _exportState = _OpState.running);
    final photo = widget.data.photo;
    final includeGrid = _willComposeGrid;
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
            .compose(sourceBytes, _grid);
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
    final includeGrid = _willComposeGrid;
    final logger = ref.read(appLoggerProvider);
    // 격자 합성본은 공유 시트에 넘기기 위한 임시 산출물이다. 성공하든 실패하든
    // 정리해야 캐시에 파생 이미지가 쌓이지 않는다.
    Directory? shareDir;
    try {
      // 격자 합성은 공유하는 순간에만 일어난다. 앱 안에는 합성본을 남기지 않으므로
      // 임시 파일로 만들어 넘긴다. 토글이 꺼져 있으면 원본을 그대로 공유한다.
      final XFile file;
      if (includeGrid) {
        final sourceBytes = await File(photo.filePath).readAsBytes();
        final png = await ref
            .read(gridPhotoComposerProvider)
            .compose(sourceBytes, _grid);
        shareDir = await Directory.systemTemp.createTemp('body_frame_share_');
        final composed = File('${shareDir.path}/${photo.id}_grid.png');
        await composed.writeAsBytes(png, flush: true);
        file = XFile(composed.path);
      } else {
        file = XFile(photo.filePath);
      }
      await Share.shareXFiles([file]);
      logger.phase(
        'photo.share',
        LogPhase.success,
        context: {'id': photo.id, 'grid': includeGrid},
      );
      if (!mounted) return;
      setState(() => _shareState = _OpState.success);
    } catch (err) {
      logger.phase('photo.share', LogPhase.failure, context: {'id': photo.id});
      if (!mounted) return;
      setState(() => _shareState = _OpState.failure);
    } finally {
      if (shareDir != null) {
        try {
          if (await shareDir.exists()) {
            await shareDir.delete(recursive: true);
          }
        } catch (_) {
          logger.warn('photo.share.temp.cleanup.failure');
        }
      }
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
      ref.invalidate(timelineProvider);
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
                    // 격자는 항상 오버레이로만 그린다. 원본 픽셀에는 굽지 않는다.
                    PhotoGridOverlay(
                      settings: _grid,
                      semanticsIdentifier: 'records.viewer.grid.overlay',
                    ),
                    // 격자를 잠깐 걷어내고 사진만 보고 싶을 때를 위한 버튼.
                    // 사진 위에 두어야 보고 있는 대상과 조작이 붙어 있다.
                    Positioned(
                      top: AppSpacing.sp2,
                      right: AppSpacing.sp2,
                      child: Semantics(
                        identifier: 'records.viewer.grid.visibility.button',
                        button: true,
                        label: _grid.visible ? '격자 숨기기' : '격자 보기',
                        child: IconButton.filledTonal(
                          key: const ValueKey(
                            'records.viewer.grid.visibility.button',
                          ),
                          tooltip: _grid.visible ? '격자 숨기기' : '격자 보기',
                          icon: Icon(
                            _grid.visible
                                ? Icons.grid_on
                                : Icons.grid_off_outlined,
                          ),
                          onPressed: () => setState(() {
                            _grid = _grid.copyWith(visible: !_grid.visible);
                            _gridState = _OpState.idle;
                          }),
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
            const SizedBox(height: 8),
            _GridEditSection(
              settings: _grid,
              captureSettings: photo.captureGridSettings,
              expanded: _gridEditing,
              state: _gridState,
              onExpandedChanged: (value) =>
                  setState(() => _gridEditing = value),
              onChanged: (value) => setState(() {
                _grid = value;
                _gridState = _OpState.idle;
              }),
              onApply: _gridState == _OpState.running ? null : _saveGrid,
              onRevert: _gridState == _OpState.running ? null : _revertGrid,
            ),
            Semantics(
              identifier: 'records.viewer.export.grid.toggle',
              label: '내보내기에 격자 합성',
              value: _willComposeGrid ? '켜짐' : '꺼짐',
              enabled: _grid.visible,
              child: SwitchListTile(
                key: const ValueKey('records.viewer.export.grid.toggle'),
                contentPadding: EdgeInsets.zero,
                title: const Text('내보내기에 격자 합성'),
                subtitle: Text(
                  _grid.visible
                      ? '원본은 변경하지 않고 격자가 포함된 새 PNG를 만듭니다.'
                      : '격자를 숨긴 상태입니다. 격자를 켜면 합성할 수 있습니다.',
                ),
                value: _willComposeGrid,
                // 격자를 숨긴 채 합성하면 화면에 없는 격자가 결과물에만 찍힌다.
                onChanged: (_exportState == _OpState.running || !_grid.visible)
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
                  label: _willComposeGrid ? '격자 합성 내보내기' : '내보내기',
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

/// 사진별 격자 조정 패널.
///
/// 격자는 원본 픽셀이 아니라 메타데이터이므로 촬영 후에도 바꿀 수 있다. 펼치면
/// 위쪽 사진에 조정 결과가 바로 겹쳐 보이고, 적용을 누를 때 메타데이터로 저장된다.
/// 촬영 당시 값은 따로 보존되므로 언제든 되돌릴 수 있다.
class _GridEditSection extends StatelessWidget {
  final GridSettings settings;
  final GridSettings captureSettings;
  final bool expanded;
  final _OpState state;
  final ValueChanged<bool> onExpandedChanged;
  final ValueChanged<GridSettings> onChanged;
  final VoidCallback? onApply;
  final VoidCallback? onRevert;

  const _GridEditSection({
    required this.settings,
    required this.captureSettings,
    required this.expanded,
    required this.state,
    required this.onExpandedChanged,
    required this.onChanged,
    required this.onApply,
    required this.onRevert,
  });

  @override
  Widget build(BuildContext context) {
    final differsFromCapture = settings != captureSettings;

    return Semantics(
      identifier: 'records.viewer.grid.section',
      container: true,
      label: '격자 조정',
      child: Card(
        key: const ValueKey('records.viewer.grid.section'),
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              identifier: 'records.viewer.grid.expand.button',
              button: true,
              expanded: expanded,
              label: '격자 조정 패널 열기/닫기',
              child: InkWell(
                key: const ValueKey('records.viewer.grid.expand.button'),
                onTap: () => onExpandedChanged(!expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sp3,
                    vertical: AppSpacing.sp2,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.grid_on_outlined, size: 20),
                      const SizedBox(width: AppSpacing.sp3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('격자 조정', style: context.texts.titleSmall),
                            Text(
                              differsFromCapture
                                  ? '촬영 당시와 다르게 조정됨'
                                  : '촬영 당시 설정',
                              style: context.texts.bodySmall?.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _InlineStatus(
                        id: 'records.viewer.grid.status',
                        state: state,
                      ),
                      Icon(expanded ? Icons.expand_less : Icons.expand_more),
                    ],
                  ),
                ),
              ),
            ),
            if (expanded) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sp3,
                  AppSpacing.sp2,
                  AppSpacing.sp3,
                  AppSpacing.sp3,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      identifier: 'records.viewer.grid.visible.switch',
                      label: '격자 표시',
                      value: settings.visible ? '켜짐' : '꺼짐',
                      child: SwitchListTile(
                        key: const ValueKey(
                          'records.viewer.grid.visible.switch',
                        ),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('격자 표시'),
                        value: settings.visible,
                        onChanged: (value) =>
                            onChanged(settings.copyWith(visible: value)),
                      ),
                    ),
                    _GridSlider(
                      id: 'records.viewer.grid.opacity.slider',
                      label: '투명도',
                      value: settings.opacity,
                      min: 0.1,
                      max: 1,
                      display: settings.opacity.toStringAsFixed(2),
                      onChanged: (value) =>
                          onChanged(settings.copyWith(opacity: value)),
                    ),
                    _GridSlider(
                      id: 'records.viewer.grid.lineWidth.slider',
                      label: '선 굵기',
                      value: settings.lineWidth,
                      min: 0.5,
                      max: 4,
                      display: settings.lineWidth.toStringAsFixed(1),
                      onChanged: (value) =>
                          onChanged(settings.copyWith(lineWidth: value)),
                    ),
                    _GridSlider(
                      id: 'records.viewer.grid.spacing.slider',
                      label: '간격',
                      value: settings.spacing,
                      min: 10,
                      max: 120,
                      display: settings.spacing.toStringAsFixed(0),
                      onChanged: (value) =>
                          onChanged(settings.copyWith(spacing: value)),
                    ),
                    const SizedBox(height: AppSpacing.sp2),
                    Text(
                      '격자는 원본 사진에 저장되지 않습니다. 내보내거나 공유할 때만 이미지에 합쳐집니다.',
                      style: context.texts.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sp3),
                    Row(
                      children: [
                        Semantics(
                          identifier: 'records.viewer.grid.apply.button',
                          button: true,
                          label: '격자 설정 적용',
                          child: FilledButton(
                            key: const ValueKey(
                              'records.viewer.grid.apply.button',
                            ),
                            onPressed: onApply,
                            child: const Text('적용'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sp2),
                        if (differsFromCapture)
                          Semantics(
                            identifier: 'records.viewer.grid.revert.button',
                            button: true,
                            label: '촬영 당시 격자 설정으로 되돌리기',
                            child: TextButton(
                              key: const ValueKey(
                                'records.viewer.grid.revert.button',
                              ),
                              onPressed: onRevert,
                              child: const Text('촬영 당시로 되돌리기'),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 라벨 · 슬라이더 · 현재 값을 한 행으로 묶는다.
///
/// 값을 항상 눈에 보이게 두는 것은 접근성 요구다. 슬라이더만으로는 조작 결과를
/// 확인할 수 없다.
class _GridSlider extends StatelessWidget {
  final String id;
  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  const _GridSlider({
    required this.id,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 60, child: Text(label, style: context.texts.bodySmall)),
        Expanded(
          child: Semantics(
            identifier: id,
            slider: true,
            label: label,
            value: display,
            child: Slider(
              key: ValueKey(id),
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            display,
            textAlign: TextAlign.end,
            style: context.numericTexts.bodySmall.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
      ],
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
