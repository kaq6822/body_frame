import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models/models.dart';
import '../../core/router/app_routes.dart';
import '../../core/widgets/async_value_view.dart';
import 'providers/home_providers.dart';

/// 홈 타임라인 화면.
///
/// 앱을 열면 곧바로 촬영 기록이 최신순으로 보인다. 사람을 먼저 고르는 단계
/// 없이 촬영 버튼 한 번으로 촬영 세션에 진입한다.
class HomeScreen extends ConsumerWidget {
  static const screenId = 'screen.home';

  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeline = ref.watch(timelineProvider);

    return Semantics(
      identifier: screenId,
      container: true,
      label: '내 기록',
      child: Scaffold(
        key: const ValueKey(screenId),
        appBar: AppBar(
          title: const Text('내 기록'),
          actions: [
            Semantics(
              identifier: 'home.compare.button',
              button: true,
              label: '전후 비교',
              child: IconButton(
                key: const ValueKey('home.compare.button'),
                icon: const Icon(Icons.compare),
                tooltip: '전후 비교',
                onPressed: () => context.pushNamed(AppRoutes.compareDates),
              ),
            ),
            Semantics(
              identifier: 'home.import.button',
              button: true,
              label: '갤러리에서 등록',
              child: IconButton(
                key: const ValueKey('home.import.button'),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                tooltip: '갤러리에서 등록',
                onPressed: () => context.pushNamed(AppRoutes.galleryImport),
              ),
            ),
            Semantics(
              identifier: 'home.settings.button',
              button: true,
              label: '설정',
              child: IconButton(
                key: const ValueKey('home.settings.button'),
                icon: const Icon(Icons.settings_outlined),
                tooltip: '설정',
                onPressed: () => context.pushNamed(AppRoutes.settings),
              ),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async => ref.invalidate(timelineProvider),
          child: AsyncValueView<List<RecordWithPhotos>>(
            value: timeline,
            statusId: 'screen.home.status',
            onRetry: () => ref.invalidate(timelineProvider),
            builder: (entries) => entries.isEmpty
                ? const _EmptyTimeline()
                : _Timeline(entries: entries),
          ),
        ),
        floatingActionButton: Semantics(
          identifier: 'home.capture.button',
          button: true,
          label: '촬영',
          child: FloatingActionButton.extended(
            key: const ValueKey('home.capture.button'),
            onPressed: () => context.pushNamed(AppRoutes.captureSession),
            icon: const Icon(Icons.photo_camera),
            label: const Text('촬영'),
          ),
        ),
      ),
    );
  }
}

class _EmptyTimeline extends StatelessWidget {
  const _EmptyTimeline();

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
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.photo_camera_outlined, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    '아직 기록이 없습니다',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '촬영 버튼을 눌러 정면·좌측면·우측면·후면을\n한 번에 기록해 보세요.',
                    textAlign: TextAlign.center,
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

class _Timeline extends StatelessWidget {
  final List<RecordWithPhotos> entries;

  const _Timeline({required this.entries});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: entries.length,
      itemBuilder: (context, index) =>
          _RecordCard(entry: entries[index], index: index),
    );
  }
}

/// 촬영 기록 1건. 사진은 [timelineProvider]가 한 번에 조회해 그룹핑한 결과를
/// 그대로 받으므로 이 위젯은 별도 쿼리를 하지 않는다(N+1 방지).
class _RecordCard extends StatelessWidget {
  final RecordWithPhotos entry;
  final int index;

  const _RecordCard({required this.entry, required this.index});

  @override
  Widget build(BuildContext context) {
    final record = entry.record;
    final photos = entry.orderedPhotos;
    final dateLabel = DateFormat('yyyy.MM.dd').format(record.shotAt);
    final label = record.label?.trim();
    final hasLabel = label != null && label.isNotEmpty;

    return Semantics(
      identifier: 'home.record.item.$index',
      button: true,
      label: '$dateLabel 촬영 기록',
      child: Card(
        key: ValueKey('home.record.item.$index'),
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.pushNamed(
            AppRoutes.recordDetail,
            pathParameters: {AppParams.recordId: record.id},
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      dateLabel,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (hasLabel) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Chip(
                          key: ValueKey('home.record.label.$index'),
                          label: Text(label),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      '${photos.length}장',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (photos.isEmpty)
                  const Text('사진 없음')
                else
                  SizedBox(
                    height: 96,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: photos.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) =>
                          _DirectionThumb(photo: photos[i]),
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

class _DirectionThumb extends StatelessWidget {
  final BodyPhoto photo;

  const _DirectionThumb({required this.photo});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'home.record.thumb.${photo.direction.key}',
      image: true,
      label: '${photo.direction.label} 사진',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(photo.filePath),
              width: 64,
              height: 72,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 64,
                height: 72,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.image_not_supported_outlined),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            photo.direction.label,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
