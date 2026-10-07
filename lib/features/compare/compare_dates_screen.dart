import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models/models.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/brand_intro.dart';
import '../records/providers/records_providers.dart';
import '../records/records_timeline_logic.dart';

/// compareDates -> compareDirection 쿼리 파라미터 키.
/// [AppParams]에는 촬영 기록 id 쌍이 정의되어 있지 않아 이 feature 안에서만
/// 쓰는 이름을 별도로 둔다(경로 문자열 자체는 여전히 goNamed로만 다룬다).
class CompareQueryKeys {
  CompareQueryKeys._();
  static const beforeRecordId = 'beforeRecordId';
  static const afterRecordId = 'afterRecordId';
}

final _dateFormat = DateFormat('yyyy.MM.dd');
final _timeFormat = DateFormat('HH:mm');

/// 촬영일이 겹치는 기록의 id.
///
/// 촬영 한 건이 기록 하나라 같은 날 여러 건이 있을 수 있다. 목록에서 날짜만
/// 보여주면 어느 촬영분인지 고를 수 없으므로 등록 시각을 함께 붙일 대상을 고른다.
Set<String> duplicatedDateRecordIds(List<PhotoRecord> records) {
  final countByDay = <DateTime, int>{};
  for (final record in records) {
    final day = DateTime(
      record.shotAt.year,
      record.shotAt.month,
      record.shotAt.day,
    );
    countByDay[day] = (countByDay[day] ?? 0) + 1;
  }
  return {
    for (final record in records)
      if ((countByDay[DateTime(
                record.shotAt.year,
                record.shotAt.month,
                record.shotAt.day,
              )] ??
              0) >
          1)
        record.id,
  };
}

/// 비교 날짜 선택 화면.
///
/// 이전/이후 촬영일(=촬영 기록)을 고르고 위치를 교환할 수 있다.
class CompareDatesScreen extends ConsumerStatefulWidget {
  static const screenId = 'screen.compare.dates';

  const CompareDatesScreen({super.key});

  @override
  ConsumerState<CompareDatesScreen> createState() => _CompareDatesScreenState();
}

class _CompareDatesScreenState extends ConsumerState<CompareDatesScreen> {
  String? _beforeRecordId;
  String? _afterRecordId;
  bool _defaultsApplied = false;

  /// 첫 진입 시에만 기본 쌍을 제안한다.
  ///
  /// 자동 제안은 본인 기록 중 공통 방향이 있는 쌍만 고른다. 다른 사람 기록은
  /// 라벨로만 구분될 뿐이라 그 사이를 조용히 채우지 않는다. 쌍이 없으면 기본값을
  /// 비워 두고 수동 선택을 안내한다.
  void _applyDefaults(List<RecordWithPhotos> entries) {
    if (_defaultsApplied) return;
    _defaultsApplied = true;
    final pair = findDefaultComparePair(entries);
    if (pair == null) return;
    _beforeRecordId = pair.beforeRecordId;
    _afterRecordId = pair.afterRecordId;
  }

  Future<void> _pickRecord({
    required bool isBefore,
    required List<RecordWithPhotos> entries,
  }) async {
    final records = entries.map((entry) => entry.record).toList();
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final selectedRecordId = isBefore ? _beforeRecordId : _afterRecordId;
        final unavailableRecordId = isBefore ? _afterRecordId : _beforeRecordId;
        final duplicated = duplicatedDateRecordIds(records);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.75,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    isBefore ? '이전 기록 선택' : '이후 기록 선택',
                    style: context.texts.titleLarge,
                  ),
                ),
                ...records.map((record) {
                  final isUnavailable = record.id == unavailableRecordId;
                  // 같은 날 여러 건이면 등록 시각으로 구분하고, 라벨이 없는
                  // 기록은 "내 기록"이라고 밝혀 다른 대상과 혼동되지 않게 한다.
                  final subtitle = [
                    if (duplicated.contains(record.id))
                      '${_timeFormat.format(record.createdAt)} 등록',
                    if (normalizeLabel(record.label) case final label?)
                      label
                    else
                      '내 기록',
                    if (record.memo != null) record.memo!,
                    if (isUnavailable) '반대쪽에 선택된 기록',
                  ].join(' · ');
                  final id =
                      'compare.${isBefore ? 'before' : 'after'}.date.option.${record.id}';
                  return Semantics(
                    identifier: id,
                    button: true,
                    selected: record.id == selectedRecordId,
                    child: ListTile(
                      key: ValueKey(id),
                      title: Text(_dateFormat.format(record.shotAt)),
                      subtitle: subtitle.isEmpty ? null : Text(subtitle),
                      selected: record.id == selectedRecordId,
                      trailing: record.id == selectedRecordId
                          ? const Icon(Icons.check_circle_outline)
                          : null,
                      enabled: !isUnavailable,
                      onTap: isUnavailable
                          ? null
                          : () => Navigator.of(context).pop(record.id),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (isBefore) {
        _beforeRecordId = selected;
      } else {
        _afterRecordId = selected;
      }
    });
  }

  void _swap() {
    setState(() {
      final tmp = _beforeRecordId;
      _beforeRecordId = _afterRecordId;
      _afterRecordId = tmp;
    });
  }

  void _goNext() {
    final beforeId = _beforeRecordId;
    final afterId = _afterRecordId;
    if (beforeId == null || afterId == null || beforeId == afterId) return;
    context.pushNamed(
      AppRoutes.compareDirection,
      queryParameters: {
        CompareQueryKeys.beforeRecordId: beforeId,
        CompareQueryKeys.afterRecordId: afterId,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 기록과 사진을 한 번에 읽는다. 자동 제안과 라벨 안내가 공통 방향과 라벨을
    // 함께 알아야 하고, 기록마다 따로 조회하면 N+1 쿼리가 된다.
    final entriesAsync = ref.watch(timelineProvider);

    return Semantics(
      identifier: CompareDatesScreen.screenId,
      container: true,
      label: '비교 날짜 선택',
      child: Scaffold(
        key: const ValueKey(CompareDatesScreen.screenId),
        appBar: AppBar(title: const Text('비교 날짜 선택')),
        body: entriesAsync.when(
          loading: () => const _StatusBody(
            key: ValueKey('screen.compare.dates.status'),
            state: _AsyncState.loading,
            message: '촬영 기록을 불러오는 중입니다.',
          ),
          error: (error, stack) => _StatusBody(
            key: const ValueKey('screen.compare.dates.status'),
            state: _AsyncState.error,
            message: '촬영 기록을 불러오지 못했습니다.',
            onRetry: () => ref.invalidate(timelineProvider),
          ),
          data: (entries) {
            if (entries.length < 2) {
              return const _StatusBody(
                key: ValueKey('screen.compare.dates.status'),
                state: _AsyncState.empty,
                message: '비교하려면 촬영 기록이 2개 이상 필요합니다.',
              );
            }
            _applyDefaults(entries);
            final beforeRecord = entries
                .where((entry) => entry.record.id == _beforeRecordId)
                .map((entry) => entry.record)
                .firstOrNull;
            final afterRecord = entries
                .where((entry) => entry.record.id == _afterRecordId)
                .map((entry) => entry.record)
                .firstOrNull;
            final canProceed =
                beforeRecord != null &&
                afterRecord != null &&
                beforeRecord.id != afterRecord.id;
            // 자동 쌍을 찾지 못했거나 사용자가 아직 고르지 않았으면 수동으로 고르게 한다.
            final needsManualSelection = !canProceed;
            // 서로 다른 대상을 골랐다는 사실을 숨기지 않는다.
            final mixedLabels =
                beforeRecord != null &&
                afterRecord != null &&
                normalizeLabel(beforeRecord.label) !=
                    normalizeLabel(afterRecord.label);

            return SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.sp4),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 32,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const BrandIntro(
                            identifier: 'compare.dates.intro',
                            eyebrow: '비교 · 1 / 3',
                            title: '두 기록 사이의 변화',
                            description: '날짜를 고르고, 같은 방향의 사진을 나란히 살펴보세요.',
                          ),
                          const SizedBox(height: AppSpacing.sp6),
                          _DateChoice(
                            identifier: 'compare.before.date.button',
                            label: '이전',
                            record: beforeRecord,
                            onPressed: () =>
                                _pickRecord(isBefore: true, entries: entries),
                          ),
                          Center(
                            child: Semantics(
                              identifier: 'compare.swap.button',
                              label: '이전/이후 위치 교환',
                              button: true,
                              child: IconButton(
                                key: const ValueKey('compare.swap.button'),
                                tooltip: '이전/이후 위치 교환',
                                icon: const Icon(Icons.swap_vert),
                                onPressed: _swap,
                              ),
                            ),
                          ),
                          _DateChoice(
                            identifier: 'compare.after.date.button',
                            label: '이후',
                            record: afterRecord,
                            onPressed: () =>
                                _pickRecord(isBefore: false, entries: entries),
                          ),
                          if (needsManualSelection)
                            Semantics(
                              identifier: 'compare.dates.manual.hint',
                              liveRegion: true,
                              child: Text(
                                key: const ValueKey(
                                  'compare.dates.manual.hint',
                                ),
                                '내 기록 두 건을 직접 골라 주세요. 서로 다른 대상을 골라도 '
                                '비교할 수 있지만, 같은 사람끼리 비교하면 변화를 보기 쉽습니다.',
                                textAlign: TextAlign.center,
                                style: context.texts.bodyMedium?.copyWith(
                                  color: context.colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          if (mixedLabels) ...[
                            const SizedBox(height: AppSpacing.sp4),
                            Semantics(
                              identifier: 'compare.dates.label.warning',
                              liveRegion: true,
                              child: Text(
                                key: const ValueKey(
                                  'compare.dates.label.warning',
                                ),
                                '이전과 이후의 대상 라벨이 다릅니다.',
                                textAlign: TextAlign.center,
                                style: context.texts.bodyMedium?.copyWith(
                                  color: context.colors.error,
                                ),
                              ),
                            ),
                          ],
                          if (beforeRecord != null && afterRecord != null) ...[
                            const SizedBox(height: AppSpacing.sp4),
                            Semantics(
                              identifier: 'compare.dates.interval',
                              child: Text(
                                key: const ValueKey('compare.dates.interval'),
                                // 날짜 계산은 타임라인과 같은 공용 함수를 쓴다.
                                // 여기서 지역 자정 차이를 직접 빼면 서머타임 구간에서
                                // 하루가 깎인다.
                                '${daysBetween(beforeRecord.shotAt, afterRecord.shotAt).abs()}일 사이의 변화',
                                textAlign: TextAlign.center,
                                style: context.texts.bodyMedium?.copyWith(
                                  color: context.colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.sp6),
                          Semantics(
                            identifier: 'compare.dates.next.button',
                            label: '다음: 촬영 방향 선택',
                            button: true,
                            child: ElevatedButton(
                              key: const ValueKey('compare.dates.next.button'),
                              onPressed: canProceed ? _goNext : null,
                              child: const Text('다음'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

enum _AsyncState { loading, error, empty }

class _StatusBody extends StatelessWidget {
  final _AsyncState state;
  final String message;
  final VoidCallback? onRetry;

  const _StatusBody({
    super.key,
    required this.state,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state == _AsyncState.loading)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: CircularProgressIndicator(),
              ),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextButton(
                  onPressed: onRetry,
                  child: const Text('다시 시도'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DateChoice extends StatelessWidget {
  const _DateChoice({
    required this.identifier,
    required this.label,
    required this.record,
    required this.onPressed,
  });
  final String identifier;
  final String label;
  final PhotoRecord? record;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: identifier,
      button: true,
      label: '$label 촬영일 선택',
      value: record == null ? '선택 안 됨' : _dateFormat.format(record!.shotAt),
      child: OutlinedButton(
        key: ValueKey(identifier),
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: context.colors.surfaceContainerLowest,
          padding: const EdgeInsets.all(AppSpacing.sp4),
          alignment: Alignment.centerLeft,
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined, color: context.colors.primary),
            const SizedBox(width: AppSpacing.sp4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: context.texts.labelMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sp1),
                  Text(
                    record == null
                        ? '$label 촬영일 선택'
                        : '$label: ${_dateFormat.format(record!.shotAt)}',
                    style: context.numericTexts.titleMedium.copyWith(
                      color: context.colors.onSurface,
                    ),
                  ),
                  if (record?.label?.trim().isNotEmpty ?? false)
                    Text(record!.label!, style: context.texts.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.expand_more),
          ],
        ),
      ),
    );
  }
}
