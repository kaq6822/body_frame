import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models/models.dart';
import '../../core/providers.dart';
import '../../core/router/app_routes.dart';
import '../../core/services/app_logger.dart';

/// 촬영 기록 상세 화면.
///
/// 촬영일/등록일, 방향별 사진 그리드(정면·좌·우·후면·기타), 기록 메모
/// 표시/수정, 촬영일 수정, 기록 삭제(확인 절차)를 제공한다.
class RecordDetailScreen extends ConsumerWidget {
  static const screenId = 'screen.records.detail';

  final String memberId;
  final String recordId;

  const RecordDetailScreen({
    super.key,
    required this.memberId,
    required this.recordId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_recordDetailProvider(recordId));

    return Semantics(
      identifier: screenId,
      container: true,
      label: '촬영 기록 상세',
      child: Scaffold(
        key: const ValueKey(screenId),
        appBar: AppBar(title: const Text('촬영 기록 상세')),
        body: async.when(
          data: (data) => _RecordDetailBody(
            memberId: memberId,
            recordId: recordId,
            data: data,
          ),
          loading: () => const _StatusPane(
            key: ValueKey('screen.records.detail.status'),
            state: _PaneState.running,
          ),
          error: (error, stack) => _StatusPane(
            key: const ValueKey('screen.records.detail.status'),
            state: _PaneState.failure,
            message: '촬영 기록을 불러오지 못했습니다.',
            onRetry: () => ref.invalidate(_recordDetailProvider(recordId)),
          ),
        ),
      ),
    );
  }
}

class _RecordDetailData {
  final PhotoRecord record;
  final List<BodyPhoto> photos;

  const _RecordDetailData({required this.record, required this.photos});
}

/// [recordId]에 해당하는 촬영 기록을 찾을 수 없을 때 던진다.
class RecordNotFoundException implements Exception {
  final String recordId;

  const RecordNotFoundException(this.recordId);

  @override
  String toString() => '촬영 기록을 찾을 수 없습니다: $recordId';
}

final _recordDetailProvider =
    FutureProvider.autoDispose.family<_RecordDetailData, String>(
  (ref, recordId) async {
    final recordRepo = ref.watch(photoRecordRepositoryProvider);
    final photoRepo = ref.watch(bodyPhotoRepositoryProvider);
    final record = await recordRepo.getById(recordId);
    if (record == null) {
      throw RecordNotFoundException(recordId);
    }
    final photos = await photoRepo.listByRecord(recordId);
    return _RecordDetailData(record: record, photos: photos);
  },
);

enum _PaneState { idle, running, success, failure }

class _RecordDetailBody extends ConsumerStatefulWidget {
  final String memberId;
  final String recordId;
  final _RecordDetailData data;

  const _RecordDetailBody({
    required this.memberId,
    required this.recordId,
    required this.data,
  });

  @override
  ConsumerState<_RecordDetailBody> createState() => _RecordDetailBodyState();
}

class _RecordDetailBodyState extends ConsumerState<_RecordDetailBody> {
  late final TextEditingController _memoController;

  _PaneState _memoState = _PaneState.idle;
  _PaneState _dateState = _PaneState.idle;
  _PaneState _deleteState = _PaneState.idle;

  @override
  void initState() {
    super.initState();
    _memoController = TextEditingController(text: widget.data.record.memo ?? '');
  }

  @override
  void dispose() {
    _memoController.dispose();
    super.dispose();
  }

  void _invalidate() {
    ref.invalidate(_recordDetailProvider(widget.recordId));
  }

  Future<void> _saveMemo() async {
    setState(() => _memoState = _PaneState.running);
    try {
      final repo = ref.read(photoRecordRepositoryProvider);
      final record = widget.data.record;
      await repo.update(
        record.copyWith(
          memo: _memoController.text.trim().isEmpty
              ? null
              : _memoController.text.trim(),
          updatedAt: DateTime.now(),
        ),
      );
      ref
          .read(appLoggerProvider)
          .phase('record.memo.save', LogPhase.success, context: {'id': record.id});
      if (!mounted) return;
      setState(() => _memoState = _PaneState.success);
      _invalidate();
    } catch (err) {
      ref.read(appLoggerProvider).phase('record.memo.save', LogPhase.failure);
      if (!mounted) return;
      setState(() => _memoState = _PaneState.failure);
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

    setState(() => _dateState = _PaneState.running);
    try {
      final repo = ref.read(photoRecordRepositoryProvider);
      await repo.update(
        record.copyWith(shotAt: picked, updatedAt: DateTime.now()),
      );
      ref
          .read(appLoggerProvider)
          .phase('record.date.save', LogPhase.success, context: {'id': record.id});
      if (!mounted) return;
      setState(() => _dateState = _PaneState.success);
      _invalidate();
    } catch (err) {
      ref.read(appLoggerProvider).phase('record.date.save', LogPhase.failure);
      if (!mounted) return;
      setState(() => _dateState = _PaneState.failure);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('records.delete.confirm.dialog'),
        title: const Text('촬영 기록 삭제'),
        content: const Text('이 촬영 기록과 포함된 모든 사진이 삭제됩니다. 삭제 후에는 복구할 수 없습니다.'),
        actions: [
          TextButton(
            key: const ValueKey('records.delete.cancel.button'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const ValueKey('records.delete.confirm.button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _deleteRecord();
  }

  Future<void> _deleteRecord() async {
    setState(() => _deleteState = _PaneState.running);
    final logger = ref.read(appLoggerProvider);
    logger.phase('record.delete', LogPhase.start, context: {'id': widget.recordId});
    try {
      final repo = ref.read(photoRecordRepositoryProvider);
      await repo.delete(widget.recordId);
      logger.phase('record.delete', LogPhase.success, context: {'id': widget.recordId});
      if (!mounted) return;
      setState(() => _deleteState = _PaneState.success);
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.goNamed(
          AppRoutes.memberDetail,
          pathParameters: {AppParams.memberId: widget.memberId},
        );
      }
    } catch (err) {
      logger.phase('record.delete', LogPhase.failure, context: {'id': widget.recordId});
      if (!mounted) return;
      setState(() => _deleteState = _PaneState.failure);
    }
  }

  Future<void> _openPhoto(BodyPhoto photo) async {
    final changed = await context.pushNamed<bool>(
      AppRoutes.photoView,
      pathParameters: {
        AppParams.memberId: widget.memberId,
        AppParams.recordId: widget.recordId,
        AppParams.photoId: photo.id,
      },
    );
    if (changed == true) {
      _invalidate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.data.record;
    final photosByDirection = <BodyDirection, List<BodyPhoto>>{
      for (final d in BodyDirection.values) d: <BodyPhoto>[],
    };
    for (final photo in widget.data.photos) {
      photosByDirection[photo.direction]!.add(photo);
    }

    return SingleChildScrollView(
      key: const ValueKey('screen.records.detail.status'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '촬영일: ${DateFormat('yyyy-MM-dd').format(record.shotAt)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Semantics(
                identifier: 'records.date.edit.button',
                button: true,
                label: '촬영일 수정',
                child: IconButton(
                  key: const ValueKey('records.date.edit.button'),
                  onPressed: _editShotDate,
                  icon: const Icon(Icons.edit_calendar_outlined),
                ),
              ),
              _InlineStatus(id: 'records.date.save.status', state: _dateState),
              Semantics(
                identifier: 'records.record.delete.button',
                button: true,
                label: '촬영 기록 삭제',
                child: IconButton(
                  key: const ValueKey('records.record.delete.button'),
                  onPressed:
                      _deleteState == _PaneState.running ? null : _confirmDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ],
          ),
          _InlineStatus(id: 'records.delete.status', state: _deleteState),
          Text(
            '등록일: ${DateFormat('yyyy-MM-dd HH:mm').format(record.createdAt)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Text('사진', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.9,
            children: [
              for (final direction in BodyDirection.values)
                for (final entry in photosByDirection[direction]!.isEmpty
                    ? [null]
                    : photosByDirection[direction]!)
                  entry == null
                      ? _EmptyDirectionTile(direction: direction)
                      : _PhotoTile(
                          direction: direction,
                          index: photosByDirection[direction]!.indexOf(entry),
                          count: photosByDirection[direction]!.length,
                          photo: entry,
                          onTap: () => _openPhoto(entry),
                        ),
            ],
          ),
          const SizedBox(height: 24),
          Text('기록 메모', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Semantics(
            identifier: 'records.memo.field',
            textField: true,
            label: '기록 메모 입력',
            child: TextField(
              key: const ValueKey('records.memo.field'),
              controller: _memoController,
              maxLines: 4,
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
                identifier: 'records.memo.save.button',
                button: true,
                label: '메모 저장',
                child: ElevatedButton(
                  key: const ValueKey('records.memo.save.button'),
                  onPressed: _memoState == _PaneState.running ? null : _saveMemo,
                  child: const Text('메모 저장'),
                ),
              ),
              const SizedBox(width: 12),
              _InlineStatus(id: 'records.memo.save.status', state: _memoState),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final BodyDirection direction;
  final int index;
  final int count;
  final BodyPhoto photo;
  final VoidCallback onTap;

  const _PhotoTile({
    required this.direction,
    required this.index,
    required this.count,
    required this.photo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final id = count > 1
        ? 'records.photo.${direction.key}.image.$index'
        : 'records.photo.${direction.key}.image';
    return Semantics(
      identifier: id,
      label: '${direction.label} 사진',
      button: true,
      child: GestureDetector(
        key: ValueKey(id),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Expanded(
                child: Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Image.file(
                    File(photo.filePath),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stack) =>
                        const Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(direction.label, style: Theme.of(context).textTheme.labelSmall),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyDirectionTile extends StatelessWidget {
  final BodyDirection direction;

  const _EmptyDirectionTile({required this.direction});

  @override
  Widget build(BuildContext context) {
    final id = 'records.photo.${direction.key}.empty';
    return Semantics(
      identifier: id,
      label: '${direction.label} 사진 미등록',
      child: Container(
        key: ValueKey(id),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.image_not_supported_outlined),
              const SizedBox(height: 4),
              Text('${direction.label} 미등록', style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// 화면 전체 로딩/에러 표시(대기/진행/실패). 성공은 실제 콘텐츠로 대체된다.
class _StatusPane extends StatelessWidget {
  final _PaneState state;
  final String? message;
  final VoidCallback? onRetry;

  const _StatusPane({
    super.key,
    required this.state,
    this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (state == _PaneState.running) {
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

/// 인라인 작업 상태(대기/진행/성공/실패) 표시.
class _InlineStatus extends StatelessWidget {
  final String id;
  final _PaneState state;

  const _InlineStatus({required this.id, required this.state});

  @override
  Widget build(BuildContext context) {
    Widget child;
    String label;
    switch (state) {
      case _PaneState.idle:
        child = const SizedBox(width: 16, height: 16);
        label = '대기';
        break;
      case _PaneState.running:
        child = const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
        label = '진행 중';
        break;
      case _PaneState.success:
        child = Icon(Icons.check_circle, size: 16, color: Theme.of(context).colorScheme.primary);
        label = '저장됨';
        break;
      case _PaneState.failure:
        child = Icon(Icons.error, size: 16, color: Theme.of(context).colorScheme.error);
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
