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
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/status_pill.dart';

enum _MemberSort {
  recent('최근 레슨순'),
  name('이름순'),
  created('등록순');

  final String label;
  const _MemberSort(this.label);
}

class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({super.key});
  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen> {
  final search = TextEditingController();
  String query = '';
  _MemberSort sort = _MemberSort.recent;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void clearSearch() => setState(() {
    search.clear();
    query = '';
  });

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(membersProvider);
    // 최근 레슨은 보조 정보다. 기록을 못 불러와도 회원 목록은 그대로 보여 준다.
    final latest = <String, DateTime>{};
    for (final x in ref.watch(timelineProvider).valueOrNull ?? const []) {
      final id = x.record.memberId;
      if (id == null) continue;
      final at = latest[id];
      if (at == null || x.record.shotAt.isAfter(at)) {
        latest[id] = x.record.shotAt;
      }
    }
    final hasMembers = members.valueOrNull?.isNotEmpty ?? false;
    return mark(
      'screen.members.list',
      Scaffold(
        appBar: AppBar(
          title: const Text('회원'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sp3),
              child: mark(
                'members.add.button',
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sp3,
                    ),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  onPressed: () => context.push('/members/new'),
                  icon: const Icon(Icons.add),
                  label: const Text('회원 추가'),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: const MainNavigation(0),
        body: Column(
          children: [
            if (ref
                    .watch(appImagePickerCoordinatorProvider)
                    ?.context
                    .operation ==
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
            // 회원이 없으면 검색할 대상도 없어 첫 등록 안내만 보여 준다.
            if (hasMembers || query.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sp4,
                  AppSpacing.sp2,
                  AppSpacing.sp4,
                  AppSpacing.sp2,
                ),
                child: mark(
                  'members.search.field',
                  TextField(
                    controller: search,
                    onChanged: (v) => setState(() => query = v.trim()),
                    onTapOutside: (_) => FocusScope.of(context).unfocus(),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: '이름·목표·메모 검색',
                      suffixIcon: query.isEmpty
                          ? null
                          : mark(
                              'members.search.clear.button',
                              IconButton(
                                tooltip: '검색어 지우기',
                                onPressed: clearSearch,
                                icon: const Icon(Icons.close),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: members.when(
                loading: () => busy('members.loading.status'),
                error: (_, _) => loadFailure(
                  'members.error.status',
                  '회원을 불러오지 못했어요',
                  '저장된 회원 목록을 가져오다 문제가 생겼어요. 다시 시도해주세요.',
                  () => ref.invalidate(membersProvider),
                ),
                data: (all) {
                  final q = query.toLowerCase();
                  final shown = all
                      .where(
                        (m) => '${m.name} ${m.goal} ${m.memo}'
                            .toLowerCase()
                            .contains(q),
                      )
                      .toList();
                  if (shown.isEmpty) {
                    return query.isEmpty
                        ? EmptyState(
                            identifier: 'members.empty.status',
                            icon: Icons.person_add_alt_1,
                            title: '첫 회원을 등록해보세요',
                            body: '레슨 일지와 선택한 사진을 회원별로 모아보세요.',
                            actions: [
                              mark(
                                'members.empty.add.button',
                                FilledButton.icon(
                                  onPressed: () => context.push('/members/new'),
                                  icon: const Icon(Icons.add),
                                  label: const Text('회원 등록하기'),
                                ),
                              ),
                            ],
                          )
                        : EmptyState(
                            identifier: 'members.empty.status',
                            icon: Icons.person_search,
                            title: '검색 결과가 없어요',
                            body: '이름이나 메모를 바꿔 검색해보세요.',
                            actions: [
                              mark(
                                'members.empty.clear.button',
                                OutlinedButton(
                                  onPressed: clearSearch,
                                  child: const Text('검색 지우기'),
                                ),
                              ),
                              mark(
                                'members.empty.add.button',
                                FilledButton.icon(
                                  onPressed: () => context.push('/members/new'),
                                  icon: const Icon(Icons.add),
                                  label: const Text('회원 추가'),
                                ),
                              ),
                            ],
                          );
                  }
                  switch (sort) {
                    case _MemberSort.recent:
                      final none = DateTime(0);
                      shown.sort((a, b) {
                        final c = (latest[b.id] ?? none).compareTo(
                          latest[a.id] ?? none,
                        );
                        return c != 0 ? c : a.name.compareTo(b.name);
                      });
                    case _MemberSort.name:
                      shown.sort((a, b) => a.name.compareTo(b.name));
                    case _MemberSort.created:
                      shown.sort((a, b) => b.createdAt.compareTo(a.createdAt));
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.sp4,
                      0,
                      AppSpacing.sp4,
                      AppSpacing.sp4,
                    ),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: mark(
                              'members.count.label',
                              Text(
                                '전체 회원 ${shown.length}명',
                                style: context.texts.bodySmall?.copyWith(
                                  color: context.colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                          mark(
                            'members.sort.menu',
                            PopupMenuButton<_MemberSort>(
                              tooltip: '정렬: ${sort.label}',
                              initialValue: sort,
                              onSelected: (v) => setState(() => sort = v),
                              itemBuilder: (_) => [
                                for (final v in _MemberSort.values)
                                  PopupMenuItem(value: v, child: Text(v.label)),
                              ],
                              child: ExcludeSemantics(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: AppSpacing.minTouchTarget,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        sort.label,
                                        style: context.texts.labelLarge
                                            ?.copyWith(
                                              color: context
                                                  .colors
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                      Icon(
                                        Icons.expand_more,
                                        color: context.colors.onSurfaceVariant,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      for (final m in shown)
                        _MemberCard(member: m, latest: latest[m.id]),
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

class _MemberCard extends StatelessWidget {
  final Member member;
  final DateTime? latest;
  const _MemberCard({required this.member, required this.latest});

  @override
  Widget build(BuildContext context) {
    final m = member;
    final colors = context.colors;
    final caution = cautionKeyword(m.precautions);
    final sub = [m.goal, m.memo].where((s) => s.isNotEmpty).join(' · ');
    return mark(
      'members.${m.id}.card',
      Card(
        margin: const EdgeInsets.only(bottom: AppSpacing.sp3),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/members/${m.id}'),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sp4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    MemberAvatar(m.name, active: latest != null),
                    const SizedBox(width: AppSpacing.sp3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: AppSpacing.sp2,
                            runSpacing: AppSpacing.sp1,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                m.name,
                                style: context.texts.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (caution.isNotEmpty)
                                StatusPill(
                                  label: caution,
                                  tone: StatusPillTone.warning,
                                  icon: Icons.info_outline,
                                  identifier: 'members.${m.id}.caution',
                                ),
                            ],
                          ),
                          if (sub.isNotEmpty)
                            Text(
                              sub,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: context.texts.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
                  ],
                ),
                const Divider(height: AppSpacing.sp6),
                mark(
                  'members.${m.id}.recent',
                  Row(
                    children: [
                      Icon(
                        Icons.schedule,
                        size: 16,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.sp1),
                      Expanded(
                        child: Text(
                          latest == null
                              ? '아직 레슨 기록이 없어요'
                              : '최근 레슨 ${shortLessonDate(latest!)}',
                          style: context.numericTexts.bodySmall.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
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

class MemberEditorScreen extends ConsumerStatefulWidget {
  final String? memberId;
  const MemberEditorScreen({super.key, this.memberId});
  @override
  ConsumerState<MemberEditorScreen> createState() => _MemberEditorState();
}

class _MemberEditorState extends ConsumerState<MemberEditorScreen> {
  /// 순서는 키 `members.edit.<i>.field`와 묶여 있다:
  /// 0 이름, 1 시작 배경, 2 목표, 3 주의 키워드, 4 회원 전달, 5 강사 관찰, 6 구분 메모.
  final fields = List.generate(8, (_) => TextEditingController());
  final nameFocus = FocusNode();
  Member? original;
  bool loaded = false, saving = false, dirty = false, leaving = false;
  String? error, nameError;
  @override
  void dispose() {
    for (final f in fields) {
      f.dispose();
    }
    nameFocus.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    if (fields[0].text.trim().isEmpty) {
      setState(() => nameError = '이름을 입력해주세요.');
      nameFocus.requestFocus();
      return;
    }
    setState(() {
      saving = true;
      error = null;
      nameError = null;
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

  Widget field(
    int i,
    String label, {
    bool required = false,
    String? helper,
    String? hint,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sp4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.sp2,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text.rich(
              TextSpan(
                text: label,
                children: [
                  if (required)
                    TextSpan(
                      text: ' *',
                      style: TextStyle(color: context.colors.primary),
                    ),
                ],
              ),
              style: context.texts.labelLarge,
            ),
            if (helper != null)
              Text(
                helper,
                style: context.texts.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sp1),
        mark(
          'members.edit.$i.field',
          TextField(
            controller: fields[i],
            focusNode: i == 0 ? nameFocus : null,
            enabled: !saving,
            minLines: lines,
            maxLines: lines == 1 ? 1 : lines + 2,
            textInputAction: lines == 1
                ? TextInputAction.next
                : TextInputAction.newline,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            onChanged: (_) => setState(() {
              dirty = true;
              if (i == 0) nameError = null;
            }),
            decoration: InputDecoration(
              hintText: hint,
              errorText: i == 0 ? nameError : null,
            ),
          ),
        ),
      ],
    ),
  );

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
          body: loadFailure(
            'members.edit.error.status',
            '회원 정보를 불러오지 못했어요',
            '잠시 후 다시 시도해주세요.',
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
          body: const EmptyState(
            identifier: 'members.edit.missing.status',
            icon: Icons.person_off_outlined,
            title: '회원을 찾을 수 없어요',
          ),
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
    final hasCare = [3, 4, 5].any((i) => fields[i].text.isNotEmpty);
    return PopScope(
      canPop: leaving || !dirty && !saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || saving) return;
        if (await confirm(
              context,
              '작성한 내용을 버릴까요?',
              '저장하지 않은 회원 정보가 사라져요.',
              button: '변경 내용 버리기',
              cancel: '계속 작성',
              destructive: true,
              preferCancel: true,
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
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sp3),
                child: mark(
                  'members.save.button',
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(64, 40),
                      tapTargetSize: MaterialTapTargetSize.padded,
                    ),
                    onPressed: saving ? null : save,
                    child: Text(saving ? '저장 중' : '저장'),
                  ),
                ),
              ),
            ],
            bottom: saving
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(4),
                    child: mark(
                      'members.save.busy',
                      const LinearProgressIndicator(
                        semanticsLabel: '회원 정보를 저장하고 있어요',
                      ),
                    ),
                  )
                : null,
          ),
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.sp4),
            children: [
              if (error != null) failure('members.save.error', error!, save),
              mark(
                'members.edit.basic.section',
                panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('기본 정보', style: context.texts.titleMedium),
                      const SizedBox(height: AppSpacing.sp1),
                      Text(
                        '회원 식별과 운동 목적을 기록해요.',
                        style: context.texts.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sp4),
                      field(0, '이름', required: true, hint: '예: 김서연'),
                      field(
                        6,
                        '구분 메모 (선택)',
                        helper: '동명이인 구분에 쓰여요',
                        hint: '예: 평일 오전반, 소개 회원',
                      ),
                      field(
                        1,
                        '운동 시작 배경 (선택)',
                        hint: '예: 출산 후 운동 재개',
                        lines: 2,
                      ),
                      field(
                        2,
                        '운동 목표 (선택)',
                        hint: '예: 허리 부담 없는 코어 강화',
                        lines: 2,
                      ),
                    ],
                  ),
                ),
              ),
              mark(
                'members.edit.care.section',
                Card(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sp4),
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    initiallyExpanded: hasCare,
                    maintainState: true,
                    shape: const Border(),
                    collapsedShape: const Border(),
                    tilePadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sp4,
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(
                      AppSpacing.sp4,
                      0,
                      AppSpacing.sp4,
                      AppSpacing.sp2,
                    ),
                    title: Text(
                      '주의사항 및 관찰 내용',
                      style: context.texts.titleMedium,
                    ),
                    subtitle: Text(
                      original == null
                          ? '선택'
                          : '선택 · 최근 수정 ${lessonDate(original!.updatedAt)}',
                    ),
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 18,
                            color: context.colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: AppSpacing.sp2),
                          Expanded(
                            child: Text(
                              '수업에 필요한 내용만 기록해주세요. 진단을 대신하지 않아요.',
                              style: context.texts.bodySmall?.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sp4),
                      field(3, '주의 키워드', hint: '예: 손목 부하 주의 · 산후 6개월'),
                      field(
                        4,
                        '회원 전달 내용',
                        hint: '예: 지난 수업 후 손목이 조금 불편했어요.',
                        lines: 3,
                      ),
                      field(
                        5,
                        '강사 관찰 및 조치 계획',
                        hint: '예: 네발기기 자세 시 손목 꺾임 관찰, 다음 수업 전 확인',
                        lines: 4,
                      ),
                    ],
                  ),
                ),
              ),
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
    final lessons = ref
        .read(timelineProvider)
        .valueOrNull
        ?.where((x) => x.record.memberId == m.id)
        .toList();
    final photoCount = lessons?.fold<int>(0, (n, x) => n + x.photos.length);
    if (!await confirm(
      context,
      '이 회원과 기록을 삭제할까요?',
      lessons == null
          ? '${m.name} 회원의 레슨 기록과 사진이 함께 삭제돼요.'
          : '${m.name} 회원의 레슨 기록 ${lessons.length}개와 사진 $photoCount장이 함께 삭제돼요.',
      button: '회원 삭제',
      icon: Icons.person_remove_outlined,
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

  void quickCapture(Member m) {
    final request = ref.read(quickCaptureRequestProvider.notifier);
    request.state = m.id;
    // 레슨 화면이 요청을 읽지 못하고 닫혀도 값이 남지 않게, 돌아오면 비운다.
    // 남아 있으면 나중의 '레슨 기록하기'가 촬영을 저절로 연다.
    context.push('/members/${m.id}/lessons/new').whenComplete(() {
      if (request.state == m.id) request.state = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = ref
        .watch(membersProvider)
        .valueOrNull
        ?.where((x) => x.id == widget.memberId)
        .firstOrNull;
    return mark(
      'screen.members.detail',
      Scaffold(
        appBar: AppBar(
          title: m == null
              ? const Text('회원')
              : Row(
                  children: [
                    Flexible(
                      child: Text(
                        m.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sp2),
                    const StatusPill(label: '회원'),
                  ],
                ),
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
              error: (_, _) => loadFailure(
                'members.detail.error',
                '회원을 불러오지 못했어요',
                '잠시 후 다시 시도해주세요.',
                () => ref.invalidate(membersProvider),
              ),
              data: (_) {
                if (m == null) {
                  return const EmptyState(
                    identifier: 'members.detail.missing',
                    icon: Icons.person_off_outlined,
                    title: '회원을 찾을 수 없어요',
                  );
                }
                final lessons = ref.watch(timelineProvider);
                final list = lessons.valueOrNull
                    ?.where((x) => x.record.memberId == m.id)
                    .toList();
                return ListView(
                  padding: const EdgeInsets.all(AppSpacing.sp4),
                  children: [
                    _MemberProfileCard(member: m),
                    if (error != null)
                      failure('members.delete.error', error!, () => remove(m)),
                    if (deleting)
                      busy('members.delete.busy', '회원 기록을 삭제하고 있어요'),
                    _TwoActions(
                      primary: mark(
                        'members.lesson.add.button',
                        FilledButton.icon(
                          onPressed: deleting
                              ? null
                              : () => context.push(
                                  '/members/${m.id}/lessons/new',
                                ),
                          icon: const Icon(Icons.edit_note),
                          label: const Text('레슨 기록하기'),
                        ),
                      ),
                      secondary: mark(
                        'members.capture.button',
                        OutlinedButton.icon(
                          onPressed: deleting ? null : () => quickCapture(m),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('바로 촬영'),
                        ),
                      ),
                    ),
                    SectionHeader(
                      title: '레슨 기록',
                      count: list?.length,
                      identifier: 'members.lessons.header',
                      trailing: mark(
                        'members.compare.button',
                        TextButton.icon(
                          onPressed: () =>
                              context.push('/members/${m.id}/compare'),
                          icon: const Icon(Icons.compare_arrows),
                          label: const Text('변화 비교'),
                        ),
                      ),
                    ),
                    lessons.when(
                      loading: () => busy('members.lessons.loading'),
                      error: (_, _) => failure(
                        'members.lessons.error',
                        '레슨 기록을 불러오지 못했어요.',
                        () => ref.invalidate(timelineProvider),
                      ),
                      data: (_) {
                        if (list!.isEmpty) {
                          return panel(
                            child: const EmptyState(
                              identifier: 'members.lessons.empty',
                              icon: Icons.description_outlined,
                              title: '아직 레슨 기록이 없어요',
                              body: '사진 없이 일지만 남겨도 좋아요.\n오늘 수업 내용을 기록해보세요.',
                              compact: true,
                            ),
                          );
                        }
                        return Column(
                          children: [
                            for (final item in list) LessonCard(item: item),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: AppSpacing.sp6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: mark(
                        'members.delete.button',
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: context.colors.error,
                          ),
                          onPressed: deleting ? null : () => remove(m),
                          icon: const Icon(Icons.person_remove_outlined),
                          label: const Text('회원 삭제'),
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
}

/// 나란히 두 버튼(보조는 오른쪽). 큰 글꼴에서는 세로로 쌓는다.
class _TwoActions extends StatelessWidget {
  final Widget primary, secondary;
  const _TwoActions({required this.primary, required this.secondary});
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          primary,
          const SizedBox(height: AppSpacing.sp2),
          secondary,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: primary),
        const SizedBox(width: AppSpacing.sp3),
        Expanded(child: secondary),
      ],
    );
  }
}

/// 운동 배경·목표(2열) + 주의사항 앰버 블록(펼치면 회원 전달·강사 관찰).
class _MemberProfileCard extends StatefulWidget {
  final Member member;
  const _MemberProfileCard({required this.member});
  @override
  State<_MemberProfileCard> createState() => _MemberProfileCardState();
}

class _MemberProfileCardState extends State<_MemberProfileCard> {
  bool expanded = false;

  Widget _value(String label, String value) => Column(
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
        value,
        style: context.texts.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final semantic = context.semanticColors;
    final colors = context.colors;
    final basics = [
      if (m.reason.isNotEmpty) ('운동 시작 배경', m.reason),
      if (m.goal.isNotEmpty) ('운동 목표', m.goal),
    ];
    final details = [
      if (m.report.isNotEmpty) ('회원 전달', '“${m.report}”'),
      if (m.observation.isNotEmpty) ('강사 관찰', m.observation),
    ];
    final caution = m.precautions.split('\n').first.trim();
    final rest = m.precautions.split('\n').skip(1).join('\n').trim();
    final hasBlock = caution.isNotEmpty || details.isNotEmpty;
    final canExpand = rest.isNotEmpty || details.isNotEmpty;
    final warn = caution.isNotEmpty;
    final fg = warn ? semantic.onWarningContainer : colors.onSurfaceVariant;
    return mark(
      'members.detail.profile',
      panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (basics.isEmpty)
              Text(
                '운동 배경·목표가 아직 없어요',
                style: context.texts.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              )
            else
              LayoutBuilder(
                builder: (context, box) {
                  // 두 항목은 반씩 나눠 쓰고, 좁으면 한 줄씩 쌓인다.
                  final w = basics.length == 1 || box.maxWidth < 280
                      ? box.maxWidth
                      : (box.maxWidth - AppSpacing.sp4) / 2;
                  return Wrap(
                    spacing: AppSpacing.sp4,
                    runSpacing: AppSpacing.sp3,
                    children: [
                      for (final b in basics)
                        SizedBox(width: w, child: _value(b.$1, b.$2)),
                    ],
                  );
                },
              ),
            if (m.memo.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sp3),
              _value('구분 메모', m.memo),
            ],
            if (hasBlock) ...[
              const Divider(height: AppSpacing.sp6),
              mark(
                'members.detail.caution',
                Material(
                  color: warn
                      ? semantic.warningContainer
                      : colors.surfaceContainerLow,
                  borderRadius: AppRadius.mdAll,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: canExpand
                        ? () => setState(() => expanded = !expanded)
                        : null,
                    child: Semantics(
                      button: canExpand,
                      expanded: canExpand ? expanded : null,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.sp3),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  warn
                                      ? Icons.info_outline
                                      : Icons.chat_bubble_outline,
                                  size: 20,
                                  color: fg,
                                ),
                                const SizedBox(width: AppSpacing.sp2),
                                Expanded(
                                  child: Text(
                                    warn ? caution : '회원 전달 · 강사 관찰',
                                    style: context.texts.labelLarge?.copyWith(
                                      color: fg,
                                    ),
                                  ),
                                ),
                                if (canExpand)
                                  Icon(
                                    expanded
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                    color: fg,
                                  ),
                              ],
                            ),
                            if (expanded) ...[
                              if (rest.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: AppSpacing.sp2,
                                  ),
                                  child: Text(rest),
                                ),
                              for (final d in details)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: AppSpacing.sp3,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        d.$1,
                                        style: context.texts.labelMedium
                                            ?.copyWith(
                                              color: colors.onSurfaceVariant,
                                            ),
                                      ),
                                      Text(d.$2),
                                    ],
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
