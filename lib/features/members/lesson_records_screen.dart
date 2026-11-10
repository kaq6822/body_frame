import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_tokens.dart';
import '../records/providers/records_providers.dart';
import '../../core/widgets/status_pill.dart';
import 'member.dart';
import 'member_providers.dart';
import 'ui.dart';

/// 레슨 한 건 요약 카드. [memberName]을 주면 전체 기록 목록용(이름이 제목)이다.
class LessonCard extends StatelessWidget {
  final RecordWithPhotos item;
  final String? memberName;
  const LessonCard({super.key, required this.item, this.memberName});

  /// 카드에 보여 줄 사진 묶음. 수업 후 → 정기 → 수업 전 순으로 하나만 고른다.
  static (String, List<BodyPhoto>) _shownGroup(List<BodyPhoto> photos) {
    for (final phase in const ['after', 'regular', 'before']) {
      final group = photos.where((p) => p.phase == phase).toList();
      if (group.isNotEmpty) {
        group.sort((a, b) => a.direction.index.compareTo(b.direction.index));
        return (phase, group);
      }
    }
    return ('', [...photos]);
  }

  @override
  Widget build(BuildContext context) {
    final r = item.record;
    final colors = context.colors;
    final photos = item.photos;
    final summary = phaseSummary(photos);
    final subtitle = photos.isEmpty
        ? '수업 일지'
        : summary.isEmpty
        ? '체형 사진 ${photos.length}장'
        : '체형 사진 ${photos.length}장 ($summary)';
    final (phase, group) = _shownGroup(photos);
    final dateStyle = memberName == null
        ? context.numericTexts.titleMedium.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          )
        : context.numericTexts.bodySmall.copyWith(
            color: colors.onSurfaceVariant,
          );
    final secondary = context.texts.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    return mark(
      'lessons.${r.id}.card',
      Card(
        margin: const EdgeInsets.only(bottom: AppSpacing.sp3),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/lessons/${r.id}'),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sp4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (memberName != null)
                            Wrap(
                              spacing: AppSpacing.sp2,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  memberName!,
                                  style: context.texts.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (r.memberId != null)
                                  const StatusPill(label: '회원')
                                else if (memberName != '회원 미연결')
                                  const StatusPill(label: '회원 미연결'),
                              ],
                            ),
                          Text(lessonDate(r.shotAt), style: dateStyle),
                          if (memberName == null)
                            Text(subtitle, style: secondary),
                        ],
                      ),
                    ),
                    if (photos.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.sp2),
                        child: Text(
                          '상세보기',
                          style: context.texts.labelLarge?.copyWith(
                            color: colors.primary,
                          ),
                        ),
                      )
                    else
                      Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
                  ],
                ),
                if ((r.condition ?? '').isNotEmpty ||
                    (r.memo ?? '').isNotEmpty ||
                    photos.isNotEmpty)
                  const Divider(height: AppSpacing.sp6),
                if ((r.condition ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sp2),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: StatusPill(
                        label: '컨디션: ${r.condition!}',
                        tone: StatusPillTone.warning,
                        icon: Icons.info_outline,
                      ),
                    ),
                  ),
                if ((r.memo ?? '').isNotEmpty)
                  Text(r.memo!, maxLines: 3, overflow: TextOverflow.ellipsis),
                if (photos.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sp3),
                  Text(
                    memberName == null
                        ? '${phases[phase] ?? ''} 체형 사진'.trim()
                        : subtitle,
                    style: context.texts.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sp2),
                  _PhotoStrip(photos: group),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoStrip extends StatelessWidget {
  static const _max = 4;
  final List<BodyPhoto> photos;
  const _PhotoStrip({required this.photos});
  @override
  Widget build(BuildContext context) {
    final extra = photos.length - _max;
    final shown = photos.take(_max).toList();
    return Row(
      key: const ValueKey('lessons.thumbnails.row'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _max; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sp2),
          Expanded(
            child: i < shown.length
                ? _Thumb(photo: shown[i], extra: i == _max - 1 ? extra : 0)
                : const SizedBox.shrink(),
          ),
        ],
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  final BodyPhoto photo;
  final int extra;
  const _Thumb({required this.photo, required this.extra});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AspectRatio(
        aspectRatio: 3 / 4,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.photoColors.backdrop,
            borderRadius: AppRadius.smAll,
          ),
          child: ClipRRect(
            borderRadius: AppRadius.smAll,
            child: Stack(
              fit: StackFit.expand,
              children: [
                LayoutBuilder(
                  builder: (context, box) => Image.file(
                    File(photo.filePath),
                    fit: BoxFit.contain,
                    // 썸네일 크기로만 디코딩한다. 원본 해상도로 카드마다 4장을
                    // 디코딩하면 긴 목록에서 메모리와 스크롤이 무거워진다.
                    cacheWidth: box.maxWidth.isFinite
                        ? (box.maxWidth *
                                  MediaQuery.devicePixelRatioOf(context))
                              .round()
                        : null,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image_outlined),
                  ),
                ),
                if (extra > 0)
                  ColoredBox(
                    color: Colors.black54,
                    child: Center(
                      child: Text(
                        '+$extra',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.sp1),
      Text(
        photo.direction.label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    ],
  );
}

class LessonRecordsScreen extends ConsumerStatefulWidget {
  /// 처음 열 때 적용할 회원 필터. 'unlinked'면 회원 미연결 기록만 보여 준다.
  final String? initialMemberFilter;

  const LessonRecordsScreen({super.key, this.initialMemberFilter});
  @override
  ConsumerState<LessonRecordsScreen> createState() => _LessonRecordsState();
}

class _LessonRecordsState extends ConsumerState<LessonRecordsScreen> {
  final search = TextEditingController();
  String query = '';
  late String? memberId = widget.initialMemberFilter;
  DateTimeRange? range;
  String shortDate(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  bool filtered(String? member) =>
      query.isNotEmpty || (member ?? '').isNotEmpty || range != null;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void clearFilters() => setState(() {
    search.clear();
    query = '';
    memberId = null;
    range = null;
  });

  String memberFilterLabel(AsyncValue<List<Member>> members, String? member) {
    if (member == null || member == '') return '전체 회원';
    if (member == 'unlinked') return '회원 미연결';
    return members.valueOrNull
            ?.where((m) => m.id == member)
            .firstOrNull
            ?.name ??
        '전체 회원';
  }

  /// 칩 모양 필터 라벨. 선택된 값이 있으면 주요 색 옅은 면으로 표시한다.
  Widget _chip(IconData icon, String label, bool active) {
    final colors = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sp3,
          vertical: AppSpacing.sp2,
        ),
        decoration: BoxDecoration(
          color: active
              ? colors.primaryContainer
              : colors.surfaceContainerLowest,
          border: Border.all(color: active ? colors.primary : colors.outline),
          borderRadius: AppRadius.fullAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: active ? colors.onPrimaryContainer : colors.onSurface,
            ),
            const SizedBox(width: AppSpacing.sp1),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: context.texts.labelLarge?.copyWith(
                  color: active ? colors.onPrimaryContainer : colors.onSurface,
                ),
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down,
              size: 18,
              color: active ? colors.onPrimaryContainer : colors.onSurface,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: range,
    );
    if (r != null && mounted) setState(() => range = r);
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(membersProvider);
    // 선택했던 회원이 삭제되면 라벨은 '전체 회원'인데 필터는 남아 빈 목록이 되던
    // 문제. 상태는 그대로 두고, 사라진 회원이면 화면에서는 전체 회원으로 본다.
    final loaded = members.valueOrNull;
    final selectedMember =
        loaded != null &&
            memberId != null &&
            memberId != '' &&
            memberId != 'unlinked' &&
            loaded.every((m) => m.id != memberId)
        ? null
        : memberId;
    return mark(
      'screen.lessons.records',
      Scaffold(
        appBar: AppBar(title: const Text('기록')),
        bottomNavigationBar: const MainNavigation(1),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sp4,
                AppSpacing.sp2,
                AppSpacing.sp4,
                AppSpacing.sp2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  mark(
                    'lessons.search.field',
                    TextField(
                      controller: search,
                      onChanged: (v) => setState(() => query = v.toLowerCase()),
                      onTapOutside: (_) => FocusScope.of(context).unfocus(),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: '메모 또는 회원 검색',
                        suffixIcon: query.isEmpty
                            ? null
                            : mark(
                                'lessons.search.clear.button',
                                IconButton(
                                  tooltip: '검색어 지우기',
                                  onPressed: () => setState(() {
                                    search.clear();
                                    query = '';
                                  }),
                                  icon: const Icon(Icons.close),
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sp3),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: AppSpacing.sp2,
                      runSpacing: AppSpacing.sp2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        mark(
                          'lessons.member.filter',
                          PopupMenuButton<String>(
                            // 기본 툴팁("메뉴 표시")이 스크린리더 이름을 덮지 않게
                            // 현재 필터 값을 그대로 읽힌다.
                            tooltip:
                                '회원 필터: ${memberFilterLabel(members, selectedMember)}',
                            initialValue: selectedMember ?? '',
                            onSelected: (v) => setState(() => memberId = v),
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: '',
                                child: Text('전체 회원'),
                              ),
                              const PopupMenuItem(
                                value: 'unlinked',
                                child: Text('회원 미연결'),
                              ),
                              for (final m in members.valueOrNull ?? [])
                                PopupMenuItem(value: m.id, child: Text(m.name)),
                            ],
                            // 메뉴는 PopupMenuButton이 연다. 칩은 모양만 그리므로
                            // 스크린리더에 따로 잡히지 않게 의미에서 뺀다.
                            child: ExcludeSemantics(
                              child: _chip(
                                Icons.person_outline,
                                memberFilterLabel(members, selectedMember),
                                (selectedMember ?? '').isNotEmpty,
                              ),
                            ),
                          ),
                        ),
                        mark(
                          'lessons.date.filter',
                          Semantics(
                            button: true,
                            label: range == null
                                ? '기간 필터: 전체 기간'
                                : '기간 필터: ${shortDate(range!.start)}부터 ${shortDate(range!.end)}까지',
                            excludeSemantics: true,
                            child: InkWell(
                              borderRadius: AppRadius.fullAll,
                              onTap: pickRange,
                              child: _chip(
                                Icons.calendar_month,
                                range == null
                                    ? '전체 기간'
                                    : '${shortDate(range!.start)} ~ ${shortDate(range!.end)}',
                                range != null,
                              ),
                            ),
                          ),
                        ),
                        if (range != null)
                          mark(
                            'lessons.date.reset.button',
                            TextButton(
                              onPressed: () => setState(() => range = null),
                              child: const Text('기간 초기화'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ref
                  .watch(timelineProvider)
                  .when(
                    loading: () => busy('lessons.records.loading'),
                    error: (_, _) => loadFailure(
                      'lessons.records.error',
                      '기록을 불러오지 못했어요',
                      '저장된 레슨 목록을 가져오다 문제가 생겼어요. 검색 조건은 그대로 유지돼요.',
                      () => ref.invalidate(timelineProvider),
                    ),
                    data: (items) {
                      if (members.hasError) {
                        return loadFailure(
                          'lessons.members.error',
                          '회원 이름을 불러오지 못했어요',
                          '다시 불러오면 기록과 회원 이름을 함께 보여 드려요.',
                          () => ref.invalidate(membersProvider),
                        );
                      }
                      final names = {
                        for (final m in members.valueOrNull ?? []) m.id: m.name,
                      };
                      final list = items.where((x) {
                        final r = x.record;
                        return (selectedMember == null ||
                                selectedMember == '' ||
                                (selectedMember == 'unlinked'
                                    ? r.memberId == null
                                    : r.memberId == selectedMember)) &&
                            (range == null ||
                                !r.shotAt.isBefore(range!.start) &&
                                    r.shotAt.isBefore(
                                      range!.end.add(const Duration(days: 1)),
                                    )) &&
                            '${names[r.memberId] ?? r.label ?? ''} ${r.memo ?? ''} ${r.condition ?? ''}'
                                .toLowerCase()
                                .contains(query);
                      }).toList();
                      if (list.isEmpty) {
                        return filtered(selectedMember)
                            ? EmptyState(
                                identifier: 'lessons.records.empty',
                                icon: Icons.filter_alt_off_outlined,
                                title: '조건에 맞는 기록이 없어요',
                                body: '검색어나 필터를 바꿔보세요.',
                                actions: [
                                  mark(
                                    'lessons.records.clear.button',
                                    OutlinedButton(
                                      onPressed: clearFilters,
                                      child: const Text('필터 지우기'),
                                    ),
                                  ),
                                ],
                              )
                            : EmptyState(
                                identifier: 'lessons.records.empty',
                                icon: Icons.description_outlined,
                                title: '아직 레슨 기록이 없어요',
                                body: '회원 화면에서 레슨을 기록해주세요.',
                                actions: [
                                  mark(
                                    'lessons.records.members.button',
                                    FilledButton.icon(
                                      onPressed: () => context.go('/'),
                                      icon: const Icon(Icons.people_outline),
                                      label: const Text('회원 보기'),
                                    ),
                                  ),
                                ],
                              );
                      }
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.sp4,
                          AppSpacing.sp2,
                          AppSpacing.sp4,
                          AppSpacing.sp4,
                        ),
                        children: [
                          mark(
                            'lessons.records.count',
                            Text(
                              '총 ${list.length}개의 레슨 기록',
                              style: context.texts.bodySmall?.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sp3),
                          for (final item in list)
                            LessonCard(
                              item: item,
                              memberName:
                                  names[item.record.memberId] ??
                                  item.record.label ??
                                  '회원 미연결',
                            ),
                        ],
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
