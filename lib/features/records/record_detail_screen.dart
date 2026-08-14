import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models/models.dart';
import '../../core/photo_frame.dart';
import '../../core/providers.dart';
import '../../core/router/app_routes.dart';
import '../../core/services/app_logger.dart';
import '../../core/widgets/photo_grid_overlay.dart';

/// 촬영 기록 상세 화면.
///
/// 촬영일/등록일, 이 기록의 촬영분을 좌우로 넘겨 보는 사진 슬라이더, 기록 메모
/// 표시/수정, 촬영일 수정, 기록 삭제(확인 절차)를 제공한다.
class RecordDetailScreen extends ConsumerWidget {
  static const screenId = 'screen.records.detail';

  final String recordId;

  const RecordDetailScreen({super.key, required this.recordId});

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
          data: (data) => _RecordDetailBody(recordId: recordId, data: data),
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

final _recordDetailProvider = FutureProvider.autoDispose
    .family<_RecordDetailData, String>((ref, recordId) async {
      final recordRepo = ref.watch(photoRecordRepositoryProvider);
      final photoRepo = ref.watch(bodyPhotoRepositoryProvider);
      final record = await recordRepo.getById(recordId);
      if (record == null) {
        throw RecordNotFoundException(recordId);
      }
      final photos = await photoRepo.listByRecord(recordId);
      return _RecordDetailData(record: record, photos: photos);
    });

enum _PaneState { idle, running, success, failure }

class _RecordDetailBody extends ConsumerStatefulWidget {
  final String recordId;
  final _RecordDetailData data;

  const _RecordDetailBody({required this.recordId, required this.data});

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
    _memoController = TextEditingController(
      text: widget.data.record.memo ?? '',
    );
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
          .phase(
            'record.memo.save',
            LogPhase.success,
            context: {'id': record.id},
          );
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
          .phase(
            'record.date.save',
            LogPhase.success,
            context: {'id': record.id},
          );
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
    logger.phase(
      'record.delete',
      LogPhase.start,
      context: {'id': widget.recordId},
    );
    try {
      final repo = ref.read(photoRecordRepositoryProvider);
      await repo.delete(widget.recordId);
      logger.phase(
        'record.delete',
        LogPhase.success,
        context: {'id': widget.recordId},
      );
      if (!mounted) return;
      setState(() => _deleteState = _PaneState.success);
      if (context.canPop()) {
        context.pop(true);
      } else {
        // 딥링크로 상세에 바로 들어온 경우엔 돌아갈 화면이 없다. 삭제한 기록이
        // 있던 타임라인으로 보낸다(홈은 촬영 화면이라 결과를 확인할 수 없다).
        context.goNamed(AppRoutes.records);
      }
    } catch (err) {
      logger.phase(
        'record.delete',
        LogPhase.failure,
        context: {'id': widget.recordId},
      );
      if (!mounted) return;
      setState(() => _deleteState = _PaneState.failure);
    }
  }

  Future<void> _openPhoto(BodyPhoto photo) async {
    final changed = await context.pushNamed<bool>(
      AppRoutes.photoView,
      pathParameters: {
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
    // 넘겨 보는 순서는 촬영 순서(정면→좌→우→후→기타)를 따른다.
    final ordered = <BodyPhoto>[
      for (final direction in BodyDirection.values)
        ...photosByDirection[direction]!,
    ];
    final missing = BodyDirection.values
        .where((d) => photosByDirection[d]!.isEmpty)
        .toList();

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
                  onPressed: _deleteState == _PaneState.running
                      ? null
                      : _confirmDelete,
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
          if (ordered.isEmpty)
            const _NoPhotosNotice()
          else
            _PhotoSlider(
              photos: ordered,
              photosByDirection: photosByDirection,
              onOpen: _openPhoto,
            ),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 12),
            _MissingDirections(directions: missing),
          ],
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
                  onPressed: _memoState == _PaneState.running
                      ? null
                      : _saveMemo,
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

/// 이 기록의 촬영분을 좌우로 넘겨 보는 사진 슬라이더.
///
/// 방향마다 작은 타일을 늘어놓는 대신 한 장을 크게 보여준다. 체형 변화는 작아서
/// 타일 크기로는 알아보기 어렵고, 같은 기록 안의 다른 방향은 순서대로 넘겨 보는
/// 편이 몸을 한 바퀴 둘러보는 실제 흐름에 가깝다.
class _PhotoSlider extends StatefulWidget {
  final List<BodyPhoto> photos;
  final Map<BodyDirection, List<BodyPhoto>> photosByDirection;
  final ValueChanged<BodyPhoto> onOpen;

  const _PhotoSlider({
    required this.photos,
    required this.photosByDirection,
    required this.onOpen,
  });

  @override
  State<_PhotoSlider> createState() => _PhotoSliderState();
}

class _PhotoSliderState extends State<_PhotoSlider> {
  final _controller = PageController();
  int _index = 0;

  @override
  void didUpdateWidget(_PhotoSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 원본 보기에서 사진을 지우고 돌아오면 장수가 줄어든다. 컨트롤러가 사라진
    // 페이지를 가리키고 있으면 마지막 장으로 당겨 온다.
    final last = widget.photos.length - 1;
    if (last >= 0 && _index > last) {
      _index = last;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) _controller.jumpToPage(last);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 사진 식별자. 같은 방향이 여러 장이면 방향 안에서의 순번을 덧붙인다.
  String _imageId(BodyPhoto photo) {
    final sameDirection = widget.photosByDirection[photo.direction] ?? const [];
    if (sameDirection.length <= 1) {
      return 'records.photo.${photo.direction.key}.image';
    }
    final order = sameDirection.indexOf(photo);
    return 'records.photo.${photo.direction.key}.image.$order';
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    final index = _index.clamp(0, photos.length - 1);
    final current = photos[index];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AspectRatio(
            aspectRatio: kPhotoFrameAspect,
            child: Semantics(
              identifier: 'records.photo.slider',
              container: true,
              label: '촬영분 ${photos.length}장, 좌우로 넘겨 보기',
              value: '${index + 1} / ${photos.length}',
              child: PageView.builder(
                key: const ValueKey('records.photo.slider'),
                controller: _controller,
                itemCount: photos.length,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder: (context, i) => _PhotoPage(
                  photo: photos[i],
                  id: _imageId(photos[i]),
                  onTap: () => widget.onOpen(photos[i]),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                current.direction.label,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Text(
              '${index + 1} / ${photos.length}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        if (photos.length > 1) ...[
          const SizedBox(height: 8),
          // 점은 위치 표시이자 바로 이동 수단이다. 스와이프만으로는 몇 장이
          // 남았는지 알 수 없고, 손이 닿기 어려운 상황도 있다.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < photos.length; i++)
                _SliderDot(
                  id: 'records.photo.slider.dot.$i',
                  label: '${photos[i].direction.label} 사진으로 이동',
                  selected: i == index,
                  onTap: () {
                    _controller.animateToPage(
                      i,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                    );
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PhotoPage extends StatelessWidget {
  final BodyPhoto photo;
  final String id;
  final VoidCallback onTap;

  const _PhotoPage({
    required this.photo,
    required this.id,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: id,
      button: true,
      label: '${photo.direction.label} 사진, 탭하면 원본 보기',
      child: GestureDetector(
        key: ValueKey(id),
        onTap: onTap,
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                File(photo.filePath),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) =>
                    const Center(child: Icon(Icons.broken_image_outlined)),
              ),
              PhotoGridOverlay(
                settings: photo.gridSettings,
                semanticsIdentifier: '$id.grid.overlay',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SliderDot extends StatelessWidget {
  final String id;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SliderDot({
    required this.id,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      identifier: id,
      button: true,
      selected: selected,
      label: label,
      child: InkResponse(
        key: ValueKey(id),
        onTap: onTap,
        radius: 20,
        child: Padding(
          // 점 자체는 작아도 터치 영역은 48dp를 확보한다.
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? colors.primary : colors.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// 이 기록에 아직 없는 방향 안내.
///
/// 빈 타일을 방향마다 늘어놓지 않고 한 줄로 요약한다. 비교는 양쪽에 같은 방향이
/// 있어야 하므로 무엇이 빠졌는지는 계속 보여줄 값이 있다.
class _MissingDirections extends StatelessWidget {
  final List<BodyDirection> directions;

  const _MissingDirections({required this.directions});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '미등록',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        for (final direction in directions)
          Semantics(
            identifier: 'records.photo.${direction.key}.empty',
            label: '${direction.label} 사진 미등록',
            child: Chip(
              key: ValueKey('records.photo.${direction.key}.empty'),
              label: Text(direction.label),
              avatar: const Icon(Icons.image_not_supported_outlined, size: 16),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
      ],
    );
  }
}

/// 사진이 한 장도 없는 기록. 갤러리 등록으로 만든 뒤 사진을 모두 지운 경우다.
class _NoPhotosNotice extends StatelessWidget {
  const _NoPhotosNotice();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'records.photo.none',
      label: '이 기록에 사진이 없습니다',
      child: Container(
        key: const ValueKey('records.photo.none'),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            '이 기록에는 사진이 없습니다.',
            style: Theme.of(context).textTheme.bodyMedium,
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
        child = Icon(
          Icons.check_circle,
          size: 16,
          color: Theme.of(context).colorScheme.primary,
        );
        label = '저장됨';
        break;
      case _PaneState.failure:
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
