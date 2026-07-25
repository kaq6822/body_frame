import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models/models.dart';
import '../../core/router/app_routes.dart';
import 'compare_dates_screen.dart' show CompareQueryKeys;
import 'compare_logic.dart';
import 'compare_providers.dart';
import 'widgets/compare_missing_context.dart';

final _dateFormat = DateFormat('yyyy.MM.dd');

/// 비교 방향 선택 화면.
///
/// 이전/이후 촬영 기록에 공통으로 존재하는 방향만 선택 가능하게 하고
/// (동일 방향끼리 비교가 기본), 선택 시 해당 방향의 사진 id를 확정해
/// 전후 비교 화면으로 넘긴다.
class CompareDirectionScreen extends ConsumerStatefulWidget {
  static const screenId = 'screen.compare.direction';

  final String memberId;

  const CompareDirectionScreen({super.key, required this.memberId});

  @override
  ConsumerState<CompareDirectionScreen> createState() =>
      _CompareDirectionScreenState();
}

class _CompareDirectionScreenState
    extends ConsumerState<CompareDirectionScreen> {
  BodyDirection? _selected;

  @override
  Widget build(BuildContext context) {
    final query = GoRouterState.of(context).uri.queryParameters;
    final beforeRecordId = query[CompareQueryKeys.beforeRecordId];
    final afterRecordId = query[CompareQueryKeys.afterRecordId];
    final hasMissingRecord = beforeRecordId == null || afterRecordId == null;
    final hasSameRecord =
        beforeRecordId != null && beforeRecordId == afterRecordId;

    return Semantics(
      identifier: CompareDirectionScreen.screenId,
      container: true,
      label: '비교 방향 선택',
      child: Scaffold(
        key: const ValueKey(CompareDirectionScreen.screenId),
        appBar: AppBar(title: const Text('비교 방향 선택')),
        body: (hasMissingRecord || hasSameRecord)
            ? CompareMissingContext(
                memberId: widget.memberId,
                message: hasSameRecord
                    ? '이전과 이후에는 서로 다른 촬영 기록을 선택해 주세요.'
                    : '비교 날짜 선택 화면에서 다시 진입해 주세요.',
                backButtonId: 'compare.direction.backToDates.button',
              )
            : _DirectionBody(
                memberId: widget.memberId,
                beforeRecordId: beforeRecordId,
                afterRecordId: afterRecordId,
                selected: _selected,
                onSelect: (d) => setState(() => _selected = d),
              ),
      ),
    );
  }
}

class _DirectionBody extends ConsumerWidget {
  final String memberId;
  final String beforeRecordId;
  final String afterRecordId;
  final BodyDirection? selected;
  final ValueChanged<BodyDirection> onSelect;

  const _DirectionBody({
    required this.memberId,
    required this.beforeRecordId,
    required this.afterRecordId,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final beforePhotosAsync = ref.watch(recordPhotosProvider(beforeRecordId));
    final afterPhotosAsync = ref.watch(recordPhotosProvider(afterRecordId));
    final beforeRecordAsync = ref.watch(recordByIdProvider(beforeRecordId));
    final afterRecordAsync = ref.watch(recordByIdProvider(afterRecordId));

    if (beforePhotosAsync.isLoading || afterPhotosAsync.isLoading) {
      return const Center(
        key: ValueKey('screen.compare.direction.status'),
        child: CircularProgressIndicator(),
      );
    }
    if (beforePhotosAsync.hasError || afterPhotosAsync.hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          key: const ValueKey('screen.compare.direction.status'),
          children: [
            const Text('사진 목록을 불러오지 못했습니다.'),
            TextButton(
              onPressed: () {
                ref.invalidate(recordPhotosProvider(beforeRecordId));
                ref.invalidate(recordPhotosProvider(afterRecordId));
              },
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    final beforePhotos = beforePhotosAsync.requireValue;
    final afterPhotos = afterPhotosAsync.requireValue;
    final available = commonDirections(beforePhotos, afterPhotos).toSet();

    if (available.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '두 촬영 기록에 공통으로 존재하는 촬영 방향이 없습니다.\n다른 날짜를 선택해 주세요.',
            key: ValueKey('screen.compare.direction.status'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final effectiveSelection = available.contains(selected)
        ? selected
        : available.first;
    if (effectiveSelection != selected) {
      // 최초 진입 시 사용 가능한 첫 방향을 기본 선택으로 제안한다.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => onSelect(effectiveSelection!),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '이전: ${_recordDateLabel(beforeRecordAsync)}   '
            '이후: ${_recordDateLabel(afterRecordAsync)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          const Text('동일한 촬영 방향끼리 비교하는 것을 기본으로 합니다.'),
          const SizedBox(height: 8),
          Semantics(
            identifier: 'compare.direction.selector',
            label: '촬영 방향 선택',
            child: Wrap(
              spacing: 8,
              children: BodyDirection.values.map((direction) {
                final isAvailable = available.contains(direction);
                final isSelected = direction == effectiveSelection;
                return Semantics(
                  identifier: 'compare.direction.selector.${direction.key}',
                  label: direction.label,
                  selected: isSelected,
                  enabled: isAvailable,
                  child: ChoiceChip(
                    key: ValueKey(
                      'compare.direction.selector.${direction.key}',
                    ),
                    label: Text(direction.label),
                    selected: isSelected,
                    onSelected: isAvailable ? (_) => onSelect(direction) : null,
                  ),
                );
              }).toList(),
            ),
          ),
          const Spacer(),
          Semantics(
            identifier: 'compare.direction.next.button',
            label: '다음: 전후 사진 비교',
            child: ElevatedButton(
              key: const ValueKey('compare.direction.next.button'),
              onPressed: effectiveSelection == null
                  ? null
                  : () {
                      final beforePhoto = photoForDirection(
                        beforePhotos,
                        effectiveSelection,
                      );
                      final afterPhoto = photoForDirection(
                        afterPhotos,
                        effectiveSelection,
                      );
                      if (beforePhoto == null || afterPhoto == null) return;
                      context.pushNamed(
                        AppRoutes.compareView,
                        pathParameters: {AppParams.memberId: memberId},
                        queryParameters: {
                          AppParams.direction: effectiveSelection.key,
                          AppParams.beforePhotoId: beforePhoto.id,
                          AppParams.afterPhotoId: afterPhoto.id,
                        },
                      );
                    },
              child: const Text('다음'),
            ),
          ),
        ],
      ),
    );
  }

  String _recordDateLabel(AsyncValue<PhotoRecord?> recordAsync) {
    final record = recordAsync.valueOrNull;
    if (record == null) return '-';
    return _dateFormat.format(record.shotAt);
  }
}
