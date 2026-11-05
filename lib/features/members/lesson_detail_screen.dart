import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/models.dart';
import '../../core/providers.dart';
import '../../core/router/app_routes.dart';
import '../records/providers/records_providers.dart';
import 'member_providers.dart';
import 'ui.dart';

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
    if (!await confirm(
      context,
      '레슨을 삭제할까요?',
      '이 레슨의 일지와 사진이 모두 삭제돼요. 회원 정보와 다른 레슨은 유지돼요.',
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

  @override
  Widget build(BuildContext context) => mark(
    'screen.lessons.detail',
    Scaffold(
      appBar: AppBar(title: const Text('레슨 기록')),
      body: ref
          .watch(recordProvider(widget.recordId))
          .when(
            loading: () => busy('lessons.detail.loading'),
            error: (_, _) => failure(
              'lessons.detail.error',
              '기록을 불러오지 못했어요.',
              () => ref.invalidate(recordProvider(widget.recordId)),
            ),
            data: (r) {
              if (r == null) return const Center(child: Text('기록을 찾을 수 없어요.'));
              final member = ref
                  .watch(membersProvider)
                  .valueOrNull
                  ?.where((m) => m.id == r.memberId)
                  .firstOrNull;
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    member?.name ?? r.label ?? '회원 미연결',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  section(
                    r.memberId == null ? '기존 기록 일시' : '실제 레슨 일시',
                    Text(
                      lessonDate(r.shotAt),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (r.memberId != null)
                    mark(
                      'lessons.edit.button',
                      OutlinedButton.icon(
                        onPressed: deleting
                            ? null
                            : () => context.push(
                                '/members/${r.memberId}/lessons/${r.id}/edit',
                              ),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('수정'),
                      ),
                    )
                  else
                    action(
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
                  const SizedBox(height: 16),
                  if ((r.condition ?? '').isNotEmpty)
                    section('오늘의 컨디션', Text(r.condition!)),
                  section(
                    '수업 일지 메모',
                    Text((r.memo ?? '').isEmpty ? '작성한 메모가 없어요.' : r.memo!),
                  ),
                  ref
                      .watch(recordPhotosProvider(r.id))
                      .when(
                        loading: () => busy('lessons.photos.loading'),
                        error: (_, _) => failure(
                          'lessons.photos.error',
                          '사진을 불러오지 못했어요.',
                          () => ref.invalidate(recordPhotosProvider(r.id)),
                        ),
                        data: (photos) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final phase in phases.entries)
                              if (photos.any((p) => p.phase == phase.key))
                                section(
                                  '${phase.value} 사진',
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 16,
                                    children: [
                                      for (final p in photos.where(
                                        (p) => p.phase == phase.key,
                                      ))
                                        SizedBox(
                                          width: 140,
                                          child: mark(
                                            'lessons.photo.${p.id}.button',
                                            InkWell(
                                              onTap: () => context.pushNamed(
                                                AppRoutes.photoView,
                                                pathParameters: {
                                                  AppParams.recordId: r.id,
                                                  AppParams.photoId: p.id,
                                                },
                                              ),
                                              child: Column(
                                                children: [
                                                  AspectRatio(
                                                    aspectRatio: 3 / 4,
                                                    child: Image.file(
                                                      File(p.filePath),
                                                      fit: BoxFit.contain,
                                                      errorBuilder: (_, _, _) =>
                                                          const Icon(
                                                            Icons
                                                                .broken_image_outlined,
                                                          ),
                                                    ),
                                                  ),
                                                  Text(p.direction.label),
                                                  Text(
                                                    p.capturedAt == null
                                                        ? '촬영 시각 정보 없음'
                                                        : lessonDate(
                                                            p.capturedAt!,
                                                          ),
                                                    style: const TextStyle(
                                                      fontSize: 12,
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
                            if (photos.isEmpty)
                              const Text('사진 없이 작성한 레슨 기록이에요.'),
                          ],
                        ),
                      ),
                  const SizedBox(height: 20),
                  Text(
                    '작성 ${lessonDate(r.createdAt)}\n수정 ${lessonDate(r.updatedAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (r.memberId != null)
                    mark(
                      'lessons.compare.button',
                      OutlinedButton.icon(
                        onPressed: () =>
                            context.push('/members/${r.memberId}/compare'),
                        icon: const Icon(Icons.compare),
                        label: const Text('변화 비교'),
                      ),
                    ),
                  if (error != null)
                    failure('lessons.delete.error', error!, () => remove(r)),
                  if (deleting) busy('lessons.delete.busy', '삭제하고 있어요'),
                  mark(
                    'lessons.delete.button',
                    TextButton(
                      onPressed: deleting ? null : () => remove(r),
                      child: const Text('레슨 삭제'),
                    ),
                  ),
                ],
              );
            },
          ),
    ),
  );
}

class LinkRecordScreen extends ConsumerStatefulWidget {
  final PhotoRecord record;
  const LinkRecordScreen({super.key, required this.record});
  @override
  ConsumerState<LinkRecordScreen> createState() => _LinkRecordState();
}

class _LinkRecordState extends ConsumerState<LinkRecordScreen> {
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

  @override
  Widget build(BuildContext context) => mark(
    'screen.lessons.link',
    Scaffold(
      appBar: AppBar(title: const Text('기존 기록 연결')),
      body: ref
          .watch(membersProvider)
          .when(
            loading: () => busy('lessons.link.loading'),
            error: (_, _) => failure(
              'lessons.link.error',
              '회원을 불러오지 못했어요.',
              () => ref.invalidate(membersProvider),
            ),
            data: (members) => ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text('이 사진 기록을 연결할 회원과 실제 레슨 일시를 확인해주세요. 원본 사진은 유지돼요.'),
                const SizedBox(height: 16),
                if (members.isEmpty) const Text('먼저 회원을 등록해주세요.'),
                for (final m in members)
                  mark(
                    'lessons.link.${m.id}.radio',
                    ListTile(
                      title: Text(m.name),
                      leading: Icon(
                        selected == m.id
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      selected: selected == m.id,
                      onTap: saving
                          ? null
                          : () => setState(() => selected = m.id),
                    ),
                  ),
                mark(
                  'lessons.link.date',
                  OutlinedButton(
                    onPressed: saving
                        ? null
                        : () async {
                            final d = await pickLessonDate(context, date);
                            if (d != null && mounted) setState(() => date = d);
                          },
                    child: Text('실제 레슨 일시\n${lessonDate(date)}'),
                  ),
                ),
                if (error != null)
                  failure('lessons.link.save.error', error!, save),
                action(
                  'lessons.link.save.button',
                  saving ? '연결 중' : '회원에게 연결',
                  selected == null || saving ? null : save,
                ),
              ],
            ),
          ),
    ),
  );
}
