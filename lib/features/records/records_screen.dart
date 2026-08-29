import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/async_value_view.dart';
import '../../core/widgets/brand_symbol.dart';
import '../../core/widgets/photo_grid_overlay.dart';
import '../compare/compare_dates_screen.dart' show CompareQueryKeys;
import 'providers/records_providers.dart';
import 'records_timeline_logic.dart';

/// 촬영 기록 화면.
///
/// 카메라(홈)에서 좌하단 썸네일로 진입한다. 전체 보기는 기록 1건을 4방향 스트립
/// 카드로 보여주고, 방향 필터를 고르면 그 방향만 큰 타일로 세로 나열해 스크롤이
/// 곧 시간축이 되게 한다.
class RecordsScreen extends ConsumerStatefulWidget {
  static const screenId = 'screen.records';

  const RecordsScreen({super.key});

  @override
  ConsumerState<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends ConsumerState<RecordsScreen> {
  /// null이면 전체 보기.
  BodyDirection? _filter;

  /// 고른 방향의 사진이 모두 사라지면 필터 바까지 함께 사라져(방향이 1개 이하)
  /// 전체 보기로 돌아갈 칩이 없어진다. 빈 화면에 갇히지 않게 상태를 되돌린다.
  /// 빌드 도중에는 setState를 부를 수 없어 다음 프레임으로 미룬다.
  void _resetFilterAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _filter != null) setState(() => _filter = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final timeline = ref.watch(timelineProvider);

    return Semantics(
      identifier: RecordsScreen.screenId,
      container: true,
      label: '내 기록',
      child: Scaffold(
        key: const ValueKey(RecordsScreen.screenId),
        appBar: AppBar(
          centerTitle: false,
          // 브랜드가 앱 안에서 드러나는 자리는 여기와 내보내기 꼬리말뿐이다.
          // 촬영 화면은 뷰파인더가 주인공이라 심벌을 얹지 않는다.
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrandSymbol(size: 20, color: context.colors.primary),
              const SizedBox(width: AppSpacing.sp2),
              const Text('내 기록'),
            ],
          ),
          leading: Semantics(
            identifier: 'records.close.button',
            button: true,
            label: '닫고 촬영 화면으로',
            child: IconButton(
              key: const ValueKey('records.close.button'),
              icon: const Icon(Icons.close),
              tooltip: '닫기',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          actions: [
            Semantics(
              identifier: 'records.compare.button',
              button: true,
              label: '전후 비교',
              child: IconButton(
                key: const ValueKey('records.compare.button'),
                icon: const Icon(Icons.compare),
                tooltip: '전후 비교',
                onPressed: () => context.pushNamed(AppRoutes.compareDates),
              ),
            ),
            Semantics(
              identifier: 'records.import.button',
              button: true,
              label: '갤러리에서 등록',
              child: IconButton(
                key: const ValueKey('records.import.button'),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                tooltip: '갤러리에서 등록',
                onPressed: () => context.pushNamed(AppRoutes.galleryImport),
              ),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async => ref.invalidate(timelineProvider),
          child: AsyncValueView<List<RecordWithPhotos>>(
            value: timeline,
            statusId: 'screen.records.status',
            onRetry: () => ref.invalidate(timelineProvider),
            builder: (entries) {
              if (entries.isEmpty) return const _EmptyRecords();
              // 사진이 지워져 더 이상 고를 수 없는 방향이면 이번 프레임부터
              // 전체 보기로 그리고, 남아 있는 상태도 함께 되돌린다.
              final filter = availableDirections(entries).contains(_filter)
                  ? _filter
                  : null;
              if (filter != _filter) _resetFilterAfterFrame();
              return _RecordsBody(
                entries: entries,
                filter: filter,
                onFilterChanged: (value) => setState(() => _filter = value),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RecordsBody extends StatelessWidget {
  final List<RecordWithPhotos> entries;
  final BodyDirection? filter;
  final ValueChanged<BodyDirection?> onFilterChanged;

  const _RecordsBody({
    required this.entries,
    required this.filter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final directions = availableDirections(entries);

    return Column(
      children: [
        if (directions.length > 1)
          _DirectionFilterBar(
            directions: directions,
            selected: filter,
            onChanged: onFilterChanged,
          ),
        Expanded(
          child: filter == null
              ? _Timeline(entries: entries)
              : _DirectionGallery(entries: entries, direction: filter!),
        ),
      ],
    );
  }
}

/// 방향 모아보기 필터.
class _DirectionFilterBar extends StatelessWidget {
  final List<BodyDirection> directions;
  final BodyDirection? selected;
  final ValueChanged<BodyDirection?> onChanged;

  const _DirectionFilterBar({
    required this.directions,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'records.filter',
      label: '방향 모아보기 필터',
      child: SizedBox(
        height: 56,
        child: ListView(
          key: const ValueKey('records.filter'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sp3,
            vertical: AppSpacing.sp2,
          ),
          children: [
            _FilterChip(
              id: 'records.filter.all',
              label: '전체',
              selected: selected == null,
              onSelected: () => onChanged(null),
            ),
            for (final direction in directions)
              _FilterChip(
                id: 'records.filter.${direction.key}',
                label: direction.label,
                selected: selected == direction,
                onSelected: () => onChanged(direction),
              ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String id;
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _FilterChip({
    required this.id,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sp2),
      child: Semantics(
        identifier: id,
        button: true,
        selected: selected,
        label: '$label 보기',
        child: ChoiceChip(
          key: ValueKey(id),
          label: Text(label),
          selected: selected,
          onSelected: (_) => onSelected(),
          // 칩은 기본적으로 터치 타겟을 줄이므로 명시적으로 48dp를 확보한다.
          materialTapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  final List<RecordWithPhotos> entries;

  const _Timeline({required this.entries});

  @override
  Widget build(BuildContext context) {
    final rows = buildTimelineRows(entries);

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: AppSpacing.sp6),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (row.monthHeader != null) _MonthHeader(label: row.monthHeader!),
            _RecordCard(row: row, entries: entries, index: index),
          ],
        );
      },
    );
  }
}

class _MonthHeader extends StatelessWidget {
  final String label;

  const _MonthHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sp4,
        AppSpacing.sp4,
        AppSpacing.sp4,
        AppSpacing.sp2,
      ),
      child: Text(
        label,
        style: context.texts.labelMedium?.copyWith(
          color: context.colors.onSurfaceVariant,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// 기록 1건. 사진이 카드 폭 전체를 4등분해 채운다.
///
/// 사진은 [timelineProvider]가 한 번에 조회해 그룹핑한 결과를 그대로 받으므로
/// 이 위젯은 별도 쿼리를 하지 않는다(N+1 방지).
class _RecordCard extends StatelessWidget {
  final TimelineRow row;
  final List<RecordWithPhotos> entries;
  final int index;

  /// 스트립에 항상 자리를 잡는 방향. 기타는 헤더 칩으로 알린다.
  static const _stripDirections = [
    BodyDirection.front,
    BodyDirection.leftSide,
    BodyDirection.rightSide,
    BodyDirection.back,
  ];

  const _RecordCard({
    required this.row,
    required this.entries,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final record = row.record;
    final photos = row.entry.photos;
    final byDirection = <BodyDirection, BodyPhoto>{};
    for (final photo in photos) {
      byDirection.putIfAbsent(photo.direction, () => photo);
    }
    final etcCount = photos
        .where((p) => p.direction == BodyDirection.etc)
        .length;
    final label = normalizeLabel(record.label);
    final dateLabel = formatDayLabel(record.shotAt);
    final compareTarget = findCompareTarget(entries, record.id);

    final ordinal = row.sameDayOrdinal;
    final ordinalLabel = ordinal == null
        ? null
        : '$ordinal/${row.sameDayTotal}번째';

    return Card(
      key: ValueKey('records.item.$index'),
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.sp3,
        0,
        AppSpacing.sp3,
        AppSpacing.sp3,
      ),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        identifier: 'records.item.$index',
        button: true,
        label: ordinalLabel == null
            ? '$dateLabel 촬영 기록, 사진 ${photos.length}장'
            : '$dateLabel $ordinalLabel 촬영 기록, 사진 ${photos.length}장',
        child: InkWell(
          onTap: () => context.pushNamed(
            AppRoutes.recordDetail,
            pathParameters: {AppParams.recordId: record.id},
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sp3,
                  AppSpacing.sp2,
                  AppSpacing.sp2,
                  AppSpacing.sp2,
                ),
                child: Row(
                  children: [
                    Text(dateLabel, style: context.numericTexts.titleMedium),
                    // 같은 날 여러 건이면 제목이 같아지므로 촬영 회차를 붙인다.
                    if (ordinalLabel != null) ...[
                      const SizedBox(width: AppSpacing.sp2),
                      Text(
                        ordinalLabel,
                        style: context.numericTexts.bodySmall.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                    // 같은 날 기록끼리는 간격이 0이라 알릴 것이 없다.
                    if ((row.daysSincePrevious ?? 0) > 0) ...[
                      const SizedBox(width: AppSpacing.sp2),
                      _ElapsedBadge(days: row.daysSincePrevious!),
                    ],
                    if (label != null) ...[
                      const SizedBox(width: AppSpacing.sp2),
                      Flexible(
                        child: Chip(
                          key: ValueKey('records.item.$index.label'),
                          label: Text(label),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (etcCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sp2),
                        child: Text(
                          '기타 $etcCount',
                          style: context.numericTexts.bodySmall.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    Text(
                      '${photos.length}장',
                      style: context.numericTexts.bodySmall.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                    if (compareTarget != null)
                      Semantics(
                        identifier: 'records.item.$index.compare.button',
                        button: true,
                        label:
                            '${formatDayLabel(compareTarget.before.record.shotAt)}와 비교',
                        child: IconButton(
                          key: ValueKey('records.item.$index.compare.button'),
                          icon: const Icon(Icons.compare, size: 18),
                          tooltip: '직전 기록과 비교',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => context.pushNamed(
                            AppRoutes.compareDirection,
                            queryParameters: {
                              CompareQueryKeys.beforeRecordId:
                                  compareTarget.before.record.id,
                              CompareQueryKeys.afterRecordId: record.id,
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final direction in _stripDirections)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          left: 1,
                          right: 1,
                          bottom: 2,
                        ),
                        child: _StripCell(
                          direction: direction,
                          photo: byDirection[direction],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ElapsedBadge extends StatelessWidget {
  final int days;

  const _ElapsedBadge({required this.days});

  @override
  Widget build(BuildContext context) {
    // 정보를 나타내는 배지이므로 행동을 뜻하는 primary를 쓰지 않는다.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp2),
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.colors.secondaryContainer,
        borderRadius: AppRadius.fullAll,
      ),
      child: Text(
        '+$days일',
        style: context.numericTexts.labelSmall.copyWith(
          color: context.colors.onSecondaryContainer,
        ),
      ),
    );
  }
}

/// 스트립 한 칸. 사진이 없으면 자리만 남겨 비교 가능 여부를 미리 알린다.
class _StripCell extends StatelessWidget {
  final BodyDirection direction;
  final BodyPhoto? photo;

  const _StripCell({required this.direction, this.photo});

  @override
  Widget build(BuildContext context) {
    final current = photo;

    if (current == null) {
      return Semantics(
        identifier: 'records.strip.${direction.key}.empty',
        label: '${direction.label} 사진 없음',
        child: AspectRatio(
          aspectRatio: 3 / 4,
          child: Container(
            decoration: BoxDecoration(
              color: context.colors.surfaceContainer,
              border: Border.all(color: context.colors.outlineVariant),
              borderRadius: AppRadius.xsAll,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.remove, size: 16, color: context.colors.outline),
                const SizedBox(height: AppSpacing.sp1),
                Text(
                  direction.label,
                  style: context.texts.labelSmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 카드 폭의 1/4로 디코딩한다. 지정하지 않으면 원본 풀사이즈가 디코딩돼
    // 스크롤 중 메모리가 급증한다.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (MediaQuery.sizeOf(context).width / 4 * dpr).round();

    return Semantics(
      identifier: 'records.strip.${direction.key}',
      image: true,
      label: '${direction.label} 사진',
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: ClipRRect(
          borderRadius: AppRadius.xsAll,
          child: ColoredBox(
            color: context.photoColors.backdrop,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  File(current.filePath),
                  fit: BoxFit.cover,
                  cacheWidth: cacheWidth,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.image_not_supported_outlined,
                    color: context.photoColors.onChrome.withValues(alpha: 0.7),
                  ),
                ),
                PhotoGridOverlay(
                  settings: current.gridSettings,
                  semanticsIdentifier:
                      'records.strip.${direction.key}.grid.overlay',
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          context.photoColors.backdrop.withValues(alpha: 0),
                          context.photoColors.chromeGradientTop,
                        ],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 10, 4, 3),
                      child: Text(
                        direction.label,
                        textAlign: TextAlign.center,
                        style: context.texts.labelSmall?.copyWith(
                          color: context.photoColors.onChrome,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 방향 모아보기. 같은 방향만 큰 타일로 세로 나열한다.
class _DirectionGallery extends StatelessWidget {
  final List<RecordWithPhotos> entries;
  final BodyDirection direction;

  const _DirectionGallery({required this.entries, required this.direction});

  @override
  Widget build(BuildContext context) {
    final rows = collectByDirection(entries, direction);

    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sp6),
          child: Text(
            '${direction.label} 사진이 없습니다',
            style: context.texts.titleMedium,
          ),
        ),
      );
    }

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (MediaQuery.sizeOf(context).width * dpr).round();

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sp3,
        0,
        AppSpacing.sp3,
        AppSpacing.sp6,
      ),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sp3),
      itemBuilder: (context, index) => _DirectionTile(
        row: rows[index],
        index: index,
        cacheWidth: cacheWidth,
      ),
    );
  }
}

class _DirectionTile extends StatelessWidget {
  final DirectionRow row;
  final int index;
  final int cacheWidth;

  const _DirectionTile({
    required this.row,
    required this.index,
    required this.cacheWidth,
  });

  @override
  Widget build(BuildContext context) {
    final dateLabel = formatDayLabel(row.record.shotAt);

    return Semantics(
      identifier: 'records.direction.item.$index',
      button: true,
      label: '$dateLabel ${row.photo.direction.label} 사진',
      child: InkWell(
        key: ValueKey('records.direction.item.$index'),
        onTap: () => context.pushNamed(
          AppRoutes.photoView,
          pathParameters: {
            AppParams.recordId: row.record.id,
            AppParams.photoId: row.photo.id,
          },
        ),
        child: ClipRRect(
          borderRadius: AppRadius.mdAll,
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: ColoredBox(
              color: context.photoColors.backdrop,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 모아보기는 변화를 훑어보는 화면이므로 원본 비율을 보존한다.
                  Image.file(
                    File(row.photo.filePath),
                    fit: BoxFit.contain,
                    cacheWidth: cacheWidth,
                    errorBuilder: (_, _, _) => Icon(
                      Icons.image_not_supported_outlined,
                      color: context.photoColors.onChrome.withValues(
                        alpha: 0.7,
                      ),
                    ),
                  ),
                  PhotoGridOverlay(
                    settings: row.photo.gridSettings,
                    semanticsIdentifier:
                        'records.direction.item.$index.grid.overlay',
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            context.photoColors.backdrop.withValues(alpha: 0),
                            context.photoColors.chromeGradientTop,
                          ],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.sp3,
                          AppSpacing.sp4,
                          AppSpacing.sp3,
                          AppSpacing.sp2,
                        ),
                        child: Row(
                          children: [
                            Text(
                              dateLabel,
                              style: context.numericTexts.bodyMedium.copyWith(
                                color: context.photoColors.onChrome,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            if ((row.daysSincePrevious ?? 0) > 0)
                              Text(
                                '+${row.daysSincePrevious}일',
                                style: context.numericTexts.bodySmall.copyWith(
                                  color: context.photoColors.onChrome,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyRecords extends StatelessWidget {
  const _EmptyRecords();

  @override
  Widget build(BuildContext context) {
    // RefreshIndicator가 동작하려면 비어 있어도 스크롤 가능해야 한다.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sp6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 브래킷(실선) 안에 인물(점선) — "이 프레임을 채운다".
                  BrandSymbol(
                    size: 88,
                    color: context.colors.primaryContainer,
                    figureColor: context.colors.primary,
                    style: BrandSymbolStyle.outlined,
                  ),
                  const SizedBox(height: AppSpacing.sp4),
                  Text('아직 기록이 없습니다', style: context.texts.titleMedium),
                  const SizedBox(height: AppSpacing.sp1),
                  Text(
                    '촬영 화면에서 정면·좌측면·우측면·후면을\n한 번에 기록해 보세요.',
                    textAlign: TextAlign.center,
                    style: context.texts.bodyMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sp5),
                  Semantics(
                    identifier: 'records.empty.capture.button',
                    button: true,
                    label: '촬영 화면으로',
                    child: FilledButton.icon(
                      key: const ValueKey('records.empty.capture.button'),
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.photo_camera),
                      label: const Text('촬영하기'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
