import '../../core/services/app_image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../records/providers/records_providers.dart';
import 'member.dart';
import 'member_providers.dart';
import 'lesson_screens.dart';
import 'ui.dart';

class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({super.key});
  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen> {
  String query = '';
  @override
  Widget build(BuildContext context) => mark(
    'screen.members.list',
    Scaffold(
      appBar: AppBar(
        title: const Text('회원'),
        actions: [
          mark(
            'members.add.button',
            IconButton(
              tooltip: '회원 등록',
              onPressed: () => context.push('/members/new'),
              icon: const Icon(Icons.person_add_alt),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const MainNavigation(0),
      body: Column(
        children: [
          if (ref.watch(appImagePickerCoordinatorProvider)?.context.operation ==
              ImagePickerOperation.galleryImport)
            mark(
              'members.recoveredPhotos.banner',
              MaterialBanner(
                content: const Text('중단된 사진 선택을 복구했어요. 확인 후 회원에게 연결할 수 있어요.'),
                actions: [
                  TextButton(
                    onPressed: () => context.push('/import'),
                    child: const Text('사진 확인'),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: mark(
              'members.search.field',
              TextField(
                onChanged: (v) => setState(() => query = v.trim()),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '이름, 목표, 메모 검색',
                ),
              ),
            ),
          ),
          Expanded(
            child: ref
                .watch(membersProvider)
                .when(
                  loading: () => busy('members.loading.status'),
                  error: (_, _) => failure(
                    'members.error.status',
                    '회원을 불러오지 못했어요.',
                    () => ref.invalidate(membersProvider),
                  ),
                  data: (members) {
                    final shown = members
                        .where(
                          (m) => '${m.name} ${m.goal} ${m.memo}'
                              .toLowerCase()
                              .contains(query.toLowerCase()),
                        )
                        .toList();
                    if (shown.isEmpty) {
                      return mark(
                        'members.empty.status',
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.people_outline, size: 48),
                                const SizedBox(height: 16),
                                Text(
                                  query.isEmpty ? '첫 회원을 등록해보세요' : '검색 결과가 없어요',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  query.isEmpty
                                      ? '회원별 레슨과 변화를 한곳에 기록해요.'
                                      : '다른 이름이나 단어로 검색해주세요.',
                                ),
                                if (query.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 20),
                                    child: action(
                                      'members.empty.add.button',
                                      '회원 등록',
                                      () => context.push('/members/new'),
                                      icon: Icons.add,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                    return ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        Text('회원 ${shown.length}명'),
                        const SizedBox(height: 12),
                        for (final m in shown)
                          mark(
                            'members.${m.id}.card',
                            panel(
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  child: Text(m.name.characters.first),
                                ),
                                title: Text(
                                  m.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  m.goal.isEmpty ? '회원 기록 보기' : m.goal,
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => context.push('/members/${m.id}'),
                              ),
                            ),
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

class MemberEditorScreen extends ConsumerStatefulWidget {
  final String? memberId;
  const MemberEditorScreen({super.key, this.memberId});
  @override
  ConsumerState<MemberEditorScreen> createState() => _MemberEditorState();
}

class _MemberEditorState extends ConsumerState<MemberEditorScreen> {
  final fields = List.generate(8, (_) => TextEditingController());
  Member? original;
  bool loaded = false, saving = false, dirty = false, leaving = false;
  String? error;
  @override
  void dispose() {
    for (final f in fields) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    if (fields[0].text.trim().isEmpty) {
      setState(() => error = '회원 이름을 입력해주세요.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final now = ref.read(clockProvider)();
      final values = fields.map((f) => f.text.trim()).toList();
      final m = Member(
        id: original?.id ?? const Uuid().v4(),
        name: values[0],
        reason: values[1],
        goal: values[2],
        precautions: values[3],
        report: values[4],
        observation: values[5],
        memo: values[6],
        createdAt: original?.createdAt ?? now,
        updatedAt: now,
      );
      await ref.read(memberRepositoryProvider).save(m);
      ref.invalidate(membersProvider);
      if (!mounted) return;
      setState(() {
        dirty = false;
        leaving = true;
      });
      context.pop();
    } catch (_) {
      if (mounted) setState(() => error = '저장하지 못했어요. 입력 내용은 유지돼요.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(membersProvider);
    if (!loaded && widget.memberId != null) {
      if (members.isLoading) {
        return Scaffold(body: busy('members.edit.loading.status'));
      }
      if (members.hasError) {
        return Scaffold(
          appBar: AppBar(),
          body: failure(
            'members.edit.error.status',
            '회원 정보를 불러오지 못했어요.',
            () => ref.invalidate(membersProvider),
          ),
        );
      }
      original = members.value!
          .where((m) => m.id == widget.memberId)
          .firstOrNull;
      if (original == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('회원을 찾을 수 없어요.')),
        );
      }
      final m = original!;
      final values = [
        m.name,
        m.reason,
        m.goal,
        m.precautions,
        m.report,
        m.observation,
        m.memo,
      ];
      for (var i = 0; i < values.length; i++) {
        fields[i].text = values[i];
      }
    }
    loaded = true;
    return PopScope(
      canPop: leaving || !dirty && !saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || saving) return;
        if (await confirm(
              context,
              '작성을 그만둘까요?',
              '저장하지 않은 회원 정보가 사라져요.',
              button: '나가기',
            ) &&
            mounted) {
          setState(() => leaving = true);
          if (context.mounted) context.pop();
        }
      },
      child: mark(
        'screen.members.edit',
        Scaffold(
          appBar: AppBar(
            title: Text(original == null ? '회원 등록' : '회원 정보 수정'),
            actions: [
              mark(
                'members.save.button',
                TextButton(
                  onPressed: saving ? null : save,
                  child: Text(saving ? '저장 중' : '저장'),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (saving) busy('members.save.busy', '회원 정보를 저장하고 있어요'),
              if (error != null) failure('members.save.error', error!, save),
              for (var i = 0; i < 7; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: input(
                    'members.edit.$i.field',
                    fields[i],
                    [
                      '회원 이름',
                      '운동을 시작한 이유 (선택)',
                      '목표 (선택)',
                      '통증·주의사항 (선택)',
                      '회원이 전달한 내용 (선택)',
                      '강사의 관찰 (선택)',
                      '메모 (선택)',
                    ][i],
                    lines: i == 0 ? 1 : 3,
                    enabled: !saving,
                    hint: i == 3 ? '임신·산후 회복 등 수업에 필요한 참고 내용' : null,
                    onChanged: (_) => setState(() => dirty = true),
                  ),
                ),
              const Text('수업에 필요한 내용만 기록해주세요. 진단을 대신하지 않아요.'),
            ],
          ),
        ),
      ),
    );
  }
}

class MemberDetailScreen extends ConsumerStatefulWidget {
  final String memberId;
  const MemberDetailScreen({super.key, required this.memberId});
  @override
  ConsumerState<MemberDetailScreen> createState() => _MemberDetailState();
}

class _MemberDetailState extends ConsumerState<MemberDetailScreen> {
  bool deleting = false;
  String? error;
  Future<void> remove(Member m) async {
    if (!await confirm(
      context,
      '${m.name} 회원을 삭제할까요?',
      '이 회원의 모든 레슨 일지와 사진도 함께 삭제돼요. 되돌릴 수 없어요.',
    )) {
      return;
    }
    setState(() {
      deleting = true;
      error = null;
    });
    try {
      await ref.read(memberRepositoryProvider).delete(m.id);
      ref.invalidate(membersProvider);
      ref.invalidate(timelineProvider);
      if (mounted) context.go('/');
    } catch (_) {
      if (mounted) setState(() => error = '삭제를 완료하지 못했어요.');
    } finally {
      if (mounted) setState(() => deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) => mark(
    'screen.members.detail',
    Scaffold(
      appBar: AppBar(
        title: const Text('회원 상세'),
        actions: [
          mark(
            'members.edit.button',
            IconButton(
              tooltip: '회원 정보 수정',
              onPressed: deleting
                  ? null
                  : () => context.push('/members/${widget.memberId}/edit'),
              icon: const Icon(Icons.edit_outlined),
            ),
          ),
        ],
      ),
      body: ref
          .watch(membersProvider)
          .when(
            loading: () => busy('members.detail.loading'),
            error: (_, _) => failure(
              'members.detail.error',
              '회원을 불러오지 못했어요.',
              () => ref.invalidate(membersProvider),
            ),
            data: (members) {
              final m = members
                  .where((x) => x.id == widget.memberId)
                  .firstOrNull;
              if (m == null) return const Center(child: Text('회원을 찾을 수 없어요.'));
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    m.name,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text('회원 정보 확인 ${lessonDate(m.updatedAt)}'),
                  const SizedBox(height: 20),
                  if (error != null)
                    failure('members.delete.error', error!, () => remove(m)),
                  if (deleting) busy('members.delete.busy', '회원 기록을 삭제하고 있어요'),
                  section(
                    '운동 배경과 목표',
                    Text(
                      '시작 이유: ${m.reason.isEmpty ? '미입력' : m.reason}\n\n목표: ${m.goal.isEmpty ? '미입력' : m.goal}',
                    ),
                  ),
                  if (m.precautions.isNotEmpty)
                    section('통증·주의사항', Text(m.precautions)),
                  if (m.report.isNotEmpty || m.observation.isNotEmpty)
                    section(
                      '회원 전달 / 강사 관찰',
                      Text('회원 전달: ${m.report}\n\n강사 관찰: ${m.observation}'),
                    ),
                  if (m.memo.isNotEmpty) section('회원 메모', Text(m.memo)),
                  action(
                    'members.lesson.add.button',
                    '레슨 기록',
                    deleting
                        ? null
                        : () => context.push('/members/${m.id}/lessons/new'),
                    icon: Icons.add,
                  ),
                  const SizedBox(height: 12),
                  mark(
                    'members.compare.button',
                    OutlinedButton.icon(
                      onPressed: () => context.push('/members/${m.id}/compare'),
                      icon: const Icon(Icons.compare),
                      label: const Text('변화 비교'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('레슨 기록', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  ref
                      .watch(timelineProvider)
                      .when(
                        loading: () => busy('members.lessons.loading'),
                        error: (_, _) => failure(
                          'members.lessons.error',
                          '레슨 기록을 불러오지 못했어요.',
                          () => ref.invalidate(timelineProvider),
                        ),
                        data: (items) {
                          final list = items
                              .where((x) => x.record.memberId == m.id)
                              .toList();
                          if (list.isEmpty) {
                            return section(
                              '아직 레슨 기록이 없어요',
                              const Text('사진 없이 일지만 작성해도 좋아요.'),
                            );
                          }
                          return Column(
                            children: [
                              for (final item in list) LessonCard(item: item),
                            ],
                          );
                        },
                      ),
                  mark(
                    'members.delete.button',
                    TextButton(
                      onPressed: deleting ? null : () => remove(m),
                      child: const Text('회원 삭제'),
                    ),
                  ),
                ],
              );
            },
          ),
    ),
  );
}
