import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/models.dart';
import '../../core/providers.dart';
import '../../core/router/app_routes.dart';
import '../records/providers/records_providers.dart';
import 'member_providers.dart';
import 'ui.dart';
import '../../core/widgets/bottom_action_bar.dart';
import '../../core/widgets/info_row.dart';
import '../../core/widgets/status_pill.dart';
import '../../core/theme/app_tokens.dart';

class LessonDetailScreen extends ConsumerStatefulWidget {
  final String recordId;
  const LessonDetailScreen({super.key, required this.recordId});
  @override
  ConsumerState<LessonDetailScreen> createState() => _LessonDetailState();
}

class _LessonDetailState extends ConsumerState<LessonDetailScreen> {
  bool deleting = false;
  String? error;
  Future<void> remove(PhotoRecord r) async {
    final count = ref.read(recordPhotosProvider(r.id)).valueOrNull?.length;
    final what = count == null || count == 0 ? '일지' : '일지와 사진 $count장';
    if (!await confirm(
      context,
      '이 레슨 기록을 삭제할까요?',
      '${shortLessonDate(r.shotAt)} 레슨의 $what이 함께 삭제돼요. 회원 정보와 다른 레슨은 그대로 남아요.',
      icon: Icons.delete_outline,
      destructive: true,
      warning: '삭제 후 되돌릴 수 없어요.',
    )) {
      return;
    }
    setState(() {
      deleting = true;
      error = null;
    });
    try {
      await ref.read(photoRecordRepositoryProvider).delete(r.id);
      ref.invalidate(timelineProvider);
      ref.invalidate(recordProvider(r.id));
      ref.invalidate(recordPhotosProvider(r.id));
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) setState(() => error = '삭제하지 못했어요. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => deleting = false);
    }
  }

  Widget cardTitle(IconData icon, String title, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sp3),
    child: Row(
      children: [
        Icon(icon, size: 20, color: context.colors.primary),
        const SizedBox(width: AppSpacing.sp2),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: context.texts.titleMedium),
          ),
        ),
        ?trailing,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final record = ref.watch(recordProvider(widget.recordId));
    final r = record.valueOrNull;
    final secondary = context.texts.bodySmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    return mark(
      'screen.lessons.detail',
      Scaffold(
        appBar: AppBar(
          title: const Text('레슨 기록'),
          actions: [
            if (r?.memberId != null)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sp2),
                child: mark(
                  'lessons.edit.button',
                  TextButton.icon(
                    onPressed: deleting
                        ? null
                        : () => context.push(
                            '/members/${r!.memberId}/lessons/${r.id}/edit',
                          ),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('수정'),
                  ),
                ),
              ),
          ],
        ),
        body: record.when(
          loading: () => busy('lessons.detail.loading'),
          error: (_, _) => loadFailure(
            'lessons.detail.error',
            '기록을 불러오지 못했어요',
            '잠시 후 다시 시도해주세요.',
            () => ref.invalidate(recordProvider(widget.recordId)),
          ),
          data: (r) {
            if (r == null) {
              return const EmptyState(
                identifier: 'lessons.detail.missing',
                icon: Icons.search_off,
                title: '기록을 찾을 수 없어요',
              );
            }
            final member = ref
                .watch(membersProvider)
                .valueOrNull
                ?.where((m) => m.id == r.memberId)
                .firstOrNull;
            final photosAsync = ref.watch(recordPhotosProvider(r.id));
            final photoCount = photosAsync.valueOrNull?.length ?? 0;
            void addPhotos() =>
                context.push('/members/${r.memberId}/lessons/${r.id}/edit');
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.sp4),
              children: [
                mark(
                  'lessons.detail.header',
                  panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: AppSpacing.sp2,
                          runSpacing: AppSpacing.sp1,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  if (r.memberId != null)
                                    TextSpan(text: '회원  ', style: secondary),
                                  TextSpan(
                                    text: member?.name ?? r.label ?? '회원 미연결',
                                    style: context.texts.titleLarge,
                                  ),
                                ],
                              ),
                            ),
                            StatusPill(
                              label: photoCount == 0
                                  ? '수업 일지'
                                  : '사진 $photoCount장',
                              tone: StatusPillTone.primary,
                              identifier: 'lessons.detail.kind',
                            ),
                          ],
                        ),
                        const Divider(height: AppSpacing.sp6),
                        InfoRow(
                          label: r.memberId == null ? '기존 기록 일시' : '실제 레슨 일시',
                          value: lessonDate(r.shotAt),
                          numeric: true,
                          identifier: 'lessons.detail.date',
                        ),
                        if ((r.condition ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.sp2),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: StatusPill(
                                label: '오늘의 컨디션: ${r.condition!}',
                                tone: StatusPillTone.warning,
                                icon: Icons.info_outline,
                                identifier: 'lessons.detail.condition',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (r.memberId == null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sp4),
                    child: action(
                      'lessons.link.button',
                      '회원에게 연결',
                      deleting
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => LinkRecordScreen(record: r),
                              ),
                            ),
                      icon: Icons.link,
                    ),
                  ),
                panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      cardTitle(Icons.edit_note, '수업 일지 메모'),
                      Text(
                        (r.memo ?? '').isEmpty ? '작성한 메모가 없어요.' : r.memo!,
                        style: (r.memo ?? '').isEmpty ? secondary : null,
                      ),
                    ],
                  ),
                ),
                photosAsync.when(
                  loading: () => busy('lessons.photos.loading'),
                  error: (_, _) => failure(
                    'lessons.photos.error',
                    '사진을 불러오지 못했어요.',
                    () => ref.invalidate(recordPhotosProvider(r.id)),
                  ),
                  data: (photos) => _photos(r, photos, addPhotos, secondary),
                ),
                if (member != null)
                  mark(
                    'lessons.member.open.button',
                    OutlinedButton.icon(
                      onPressed: () => context.push('/members/${member.id}'),
                      icon: const Icon(Icons.list),
                      label: Text('${member.name} 회원의 전체 기록 보기'),
                    ),
                  ),
                mark(
                  'lessons.detail.meta',
                  Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      title: Text('추가 정보', style: context.texts.labelLarge),
                      children: [
                        InfoRow(
                          label: '기록 작성',
                          value: lessonDate(r.createdAt),
                          numeric: true,
                        ),
                        InfoRow(
                          label: '마지막 수정',
                          value: lessonDate(r.updatedAt),
                          numeric: true,
                        ),
                      ],
                    ),
                  ),
                ),
                if (error != null)
                  failure('lessons.delete.error', error!, () => remove(r)),
                if (deleting) busy('lessons.delete.busy', '삭제하고 있어요'),
                const SizedBox(height: AppSpacing.sp4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: mark(
                    'lessons.delete.button',
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: context.colors.error,
                      ),
                      onPressed: deleting ? null : () => remove(r),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('레슨 삭제'),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _photos(
    PhotoRecord r,
    List<BodyPhoto> photos,
    VoidCallback addPhotos,
    TextStyle? secondary,
  ) {
    final linked = r.memberId != null;
    if (photos.isEmpty) {
      return panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cardTitle(Icons.photo_library_outlined, '체형 사진'),
            Text('사진 없이 작성한 레슨 기록이에요.', style: secondary),
            if (linked) ...[
              const SizedBox(height: AppSpacing.sp3),
              mark(
                'lessons.photos.add.button',
                OutlinedButton.icon(
                  onPressed: deleting ? null : addPhotos,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('사진 추가'),
                ),
              ),
            ],
          ],
        ),
      );
    }
    final hasBeforeAfter =
        photos.any((p) => p.phase == 'before') &&
        photos.any((p) => p.phase == 'after');
    return mark(
      'lessons.photos.section',
      panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cardTitle(
              Icons.photo_library_outlined,
              '체형 사진 (총 ${photos.length}장)',
            ),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sp2,
              runSpacing: AppSpacing.sp2,
              children: [
                Text(phaseSummary(photos), style: secondary),
                if (linked)
                  mark(
                    'lessons.compare.button',
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          context.push('/members/${r.memberId}/compare'),
                      icon: const Icon(Icons.compare),
                      label: Text(hasBeforeAfter ? '전후 비교' : '변화 비교'),
                    ),
                  ),
              ],
            ),
            for (final phase in phases.keys)
              if (photos.any((p) => p.phase == phase))
                ..._group(r, phase, photos),
            if (linked) ...[
              const SizedBox(height: AppSpacing.sp4),
              mark(
                'lessons.photos.add.button',
                OutlinedButton.icon(
                  onPressed: deleting ? null : addPhotos,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('이 레슨에 사진 추가하기'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _group(PhotoRecord r, String phase, List<BodyPhoto> photos) {
    final group = photos.where((p) => p.phase == phase).toList()
      ..sort((a, b) => a.direction.index.compareTo(b.direction.index));
    final times = group.map((p) => p.capturedAt).whereType<DateTime>().toList()
      ..sort();
    return [
      const Divider(height: AppSpacing.sp6),
      mark(
        'lessons.group.$phase.header',
        photoGroupHeader(context, phase, [
          for (final p in group) p.direction,
        ], times.firstOrNull),
      ),
      photoGrid([
        for (final p in group)
          LessonPhotoThumb(
            identifier: 'lessons.photo.${p.id}.button',
            path: p.filePath,
            label: p.direction.label,
            onTap: () => context.pushNamed(
              AppRoutes.photoView,
              pathParameters: {
                AppParams.recordId: r.id,
                AppParams.photoId: p.id,
              },
            ),
          ),
      ]),
    ];
  }
}

class LinkRecordScreen extends ConsumerStatefulWidget {
  final PhotoRecord record;
  const LinkRecordScreen({super.key, required this.record});
  @override
  ConsumerState<LinkRecordScreen> createState() => _LinkRecordState();
}

class _LinkRecordState extends ConsumerState<LinkRecordScreen> {
  /// 정책상 미리 고르지 않는다. 사용자가 회원을 직접 골라야 연결할 수 있다.
  String? selected, error;
  late DateTime date = widget.record.shotAt;
  bool saving = false;
  Future<void> save() async {
    if (selected == null || saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await ref
          .read(memberRepositoryProvider)
          .linkRecord(widget.record.id, selected!, date);
      ref.invalidate(recordProvider(widget.record.id));
      ref.invalidate(timelineProvider);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => error = '연결하지 못했어요. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget title(String text) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sp3),
    child: Semantics(
      header: true,
      child: Text(text, style: context.texts.titleMedium),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final secondary = context.texts.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final photos =
        ref.watch(recordPhotosProvider(widget.record.id)).valueOrNull ??
        const <BodyPhoto>[];
    final shotTimes =
        photos.map((p) => p.capturedAt).whereType<DateTime>().toList()..sort();
    final shotAt = shotTimes.firstOrNull ?? widget.record.shotAt;
    final members = ref.watch(membersProvider);
    final hasMembers = members.valueOrNull?.isNotEmpty ?? false;
    return mark(
      'screen.lessons.link',
      Scaffold(
        appBar: AppBar(title: const Text('기존 기록 연결')),
        bottomNavigationBar: hasMembers
            ? BottomActionBar(
                identifier: 'lessons.link.actions',
                leading: error == null
                    ? null
                    : mark(
                        'lessons.link.save.error',
                        Text(
                          error!,
                          style: context.texts.bodyMedium?.copyWith(
                            color: colors.error,
                          ),
                        ),
                      ),
                secondary: mark(
                  'lessons.link.later.button',
                  OutlinedButton(
                    onPressed: saving ? null : () => Navigator.pop(context),
                    child: const Text('나중에'),
                  ),
                ),
                primary: mark(
                  'lessons.link.save.button',
                  FilledButton(
                    onPressed: selected == null || saving ? null : save,
                    child: Text(saving ? '연결 중' : '선택한 기록 연결'),
                  ),
                ),
              )
            : null,
        body: members.when(
          loading: () => busy('lessons.link.loading'),
          error: (_, _) => loadFailure(
            'lessons.link.error',
            '회원을 불러오지 못했어요',
            '잠시 후 다시 시도해주세요.',
            () => ref.invalidate(membersProvider),
          ),
          data: (members) {
            if (members.isEmpty) {
              return EmptyState(
                identifier: 'lessons.link.empty',
                icon: Icons.person_add_alt_1,
                title: '먼저 회원을 등록해주세요',
                body: '등록한 회원에게 이 기록을 연결할 수 있어요.',
                actions: [
                  mark(
                    'lessons.link.addMember.button',
                    FilledButton.icon(
                      onPressed: () => context.push('/members/new'),
                      icon: const Icon(Icons.add),
                      label: const Text('회원 등록하기'),
                    ),
                  ),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.sp4),
              children: [
                Text(
                  '기존 사진 기록을 회원에게 연결해요. 원본 사진은 그대로 유지돼요.',
                  style: context.texts.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sp4),
                mark(
                  'lessons.link.record',
                  panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        title('연결할 기록'),
                        Row(
                          children: [
                            if (photos.isNotEmpty) ...[
                              SizedBox(
                                width: 56,
                                child: LessonPhotoThumb(
                                  identifier: 'lessons.link.record.thumb',
                                  path: photos.first.filePath,
                                  label: photos.first.direction.label,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sp3),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.record.label ?? '이름 없는 기록',
                                    style: context.texts.titleMedium,
                                  ),
                                  Text(
                                    '${shortLessonDate(widget.record.shotAt)} · 사진 ${photos.length}장',
                                    style: context.numericTexts.bodySmall
                                        .copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      title('연결할 회원'),
                      for (final m in members)
                        mark(
                          'lessons.link.${m.id}.radio',
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: MemberAvatar(m.name),
                            title: Text(m.name),
                            subtitle: m.memo.isEmpty ? null : Text(m.memo),
                            trailing: Icon(
                              selected == m.id
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: selected == m.id
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                            ),
                            selected: selected == m.id,
                            onTap: saving
                                ? null
                                : () => setState(() => selected = m.id),
                          ),
                        ),
                    ],
                  ),
                ),
                panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      title('레슨 일시'),
                      mark(
                        'lessons.link.date',
                        InkWell(
                          borderRadius: AppRadius.smAll,
                          onTap: saving
                              ? null
                              : () async {
                                  final d = await pickLessonDate(context, date);
                                  if (d != null && mounted) {
                                    setState(() => date = d);
                                  }
                                },
                          child: InfoRow(
                            label: '실제 레슨 일시',
                            value: lessonDate(date),
                            numeric: true,
                            trailing: IgnorePointer(
                              child: ExcludeSemantics(
                                child: OutlinedButton.icon(
                                  onPressed: saving ? null : () {},
                                  icon: const Icon(
                                    Icons.calendar_today,
                                    size: 18,
                                  ),
                                  label: const Text('일시 수정'),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sp1),
                      Text(
                        '촬영 시각(${clockTime(shotAt)})과 실제 수업 시각이 다르면 수정하세요.',
                        style: secondary,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
