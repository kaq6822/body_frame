import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/korean_text.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/status_pill.dart';
import '../members/member.dart';
import '../members/member_providers.dart';
import '../members/ui.dart';
import '../records/providers/records_providers.dart';
import 'home_logic.dart';
import 'recovered_picker_banners.dart';

/// 앱 첫 화면. 오늘 올 것으로 보이는 회원, 방금 한 레슨, 이번 주 기록, 한동안
/// 기록이 없는 회원을 요약한다. 장식용 숫자는 두지 않고 모든 카드가 다음
/// 행동(레슨 기록·상세·비교·기록 탭)으로 이어진다.
///
/// 예약 기능이 없어 "오늘 예상 회원"은 지난 기록으로 추정하고 근거를 밝힌다.
class HomeScreen extends ConsumerStatefulWidget {
  static const screenId = 'screen.home';
  const HomeScreen({super.key});

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  /// 처음 보이는 예상 회원 수. 넘치면 "+N명 더"로 펼친다.
  static const maxExpected = 5;
  static const maxIdle = 3;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  /// 마지막으로 그린 날짜. 자정을 넘겨 복귀하면 다시 계산한다.
  DateTime? _shownDay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final now = ref.read(clockProvider)();
    final day = DateTime(now.year, now.month, now.day);
    // 날짜가 바뀌었으면 오늘 날짜·예상 회원·이번 주·경과일을 새로 계산한다.
    if (day != _shownDay) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider)();
    _shownDay = DateTime(now.year, now.month, now.day);
    final members = ref.watch(membersProvider);
    final timeline = ref.watch(timelineProvider);
    void retry() {
      ref.invalidate(membersProvider);
      ref.invalidate(timelineProvider);
    }

    final loading = members.isLoading || timeline.isLoading;
    final failed = members.hasError || timeline.hasError;
    final List<Widget> content;
    if (failed && !loading) {
      content = [
        loadFailure(
          'home.error',
          '홈 정보를 불러오지 못했어요',
          '저장된 회원과 레슨을 가져오다 문제가 생겼어요. 다시 시도해주세요.',
          retry,
        ),
      ];
    } else if (!members.hasValue || !timeline.hasValue || failed) {
      // 처음 불러오는 중이거나, 실패 뒤 다시 시도하는 중이다.
      content = [busy('home.loading')];
    } else if (members.value!.isEmpty) {
      content = [
        EmptyState(
          identifier: 'home.empty',
          icon: Icons.person_add_alt_1,
          title: '첫 회원을 등록해주세요',
          body: keepPhrasesWhole('회원을 등록하면 레슨과 체형 변화를 기록할 수 있어요.'),
          actions: [
            mark(
              'home.empty.add.button',
              FilledButton.icon(
                onPressed: () => context.push('/members/new'),
                icon: const Icon(Icons.add),
                label: const Text('회원 등록하기'),
              ),
            ),
          ],
        ),
      ];
    } else {
      content = homeSections(
        now: now,
        members: members.value!,
        lessons: timeline.value!,
      );
    }

    return mark(
      HomeScreen.screenId,
      Scaffold(
        appBar: AppBar(
          title: mark(
            'home.brand.wordmark',
            Text(
              'BodyMark',
              style: context.texts.titleLarge?.copyWith(
                color: context.colors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sp2),
              child: mark(
                'home.member.add.button',
                IconButton(
                  tooltip: '회원 추가',
                  onPressed: () => context.push('/members/new'),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: const MainNavigation(0),
        // 복구 배너와 날짜 머리도 스크롤 안에 둔다. 가로 화면·큰 글꼴에서
        // 배너가 떠도 고정 영역이 화면을 넘치지 않는다.
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sp4,
            0,
            AppSpacing.sp4,
            AppSpacing.sp4,
          ),
          children: [
            const RecoveredPickerBanners(),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sp3),
              child: mark(
                'home.today.label',
                Semantics(
                  header: true,
                  child: Text(
                    '${now.month}월 ${now.day}일 ${HomeScreen._weekdays[now.weekday - 1]}요일',
                    style: context.texts.headlineMedium,
                  ),
                ),
              ),
            ),
            ...content,
          ],
        ),
      ),
    );
  }
}

/// 회원이 있을 때의 홈 섹션들. 미연결 기록 수도 같은 타임라인에서 세어
/// 기록을 연결해 타임라인이 새로 읽히면 띠가 함께 갱신된다.
List<Widget> homeSections({
  required DateTime now,
  required List<Member> members,
  required List<RecordWithPhotos> lessons,
}) {
  final expected = expectedMembersToday(
    members: members,
    lessons: lessons,
    now: now,
  );
  final latest = latestMemberLesson(
    members: members,
    lessons: lessons,
    now: now,
  );
  final week = weekStats(members: members, lessons: lessons, now: now);
  final idle = idleMembers(members: members, lessons: lessons, now: now);
  final unlinked = lessons.where((x) => x.record.memberId == null).length;
  return [
    if (unlinked > 0) _UnlinkedBanner(count: unlinked),
    _ExpectedSection(now: now, expected: expected),
    if (latest != null)
      _RecentSection(
        lesson: latest,
        member: members.firstWhere((m) => m.id == latest.record.memberId),
        canCompare:
            photoRecordCount(
              lessons.where((x) => x.record.memberId == latest.record.memberId),
            ) >=
            2,
      ),
    _WeekSection(stats: week),
    if (idle.isNotEmpty) _IdleSection(idle: idle),
  ];
}

/// 카드 머리글: 아이콘 + 제목 + (선택) 보조 문구.
Widget _cardTitle(
  BuildContext context,
  IconData icon,
  String title, {
  String? caption,
}) => Padding(
  padding: const EdgeInsets.only(bottom: AppSpacing.sp3),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, size: 20, color: context.colors.primary),
          const SizedBox(width: AppSpacing.sp2),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: context.texts.titleMedium),
            ),
          ),
        ],
      ),
      if (caption != null)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sp1),
          child: Text(
            keepPhrasesWhole(caption),
            style: context.texts.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
    ],
  ),
);

String _two(int v) => v.toString().padLeft(2, '0');

/// "오후 3:00". 시각 덩어리가 줄바꿈으로 갈리지 않게 붙인다.
String _clock(DateTime d) =>
    '${keepPhrasesWhole(d.hour < 12 ? '오전' : '오후')} ${d.hour % 12 == 0 ? 12 : d.hour % 12}:${_two(d.minute)}';

class _UnlinkedBanner extends StatelessWidget {
  final int count;
  const _UnlinkedBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return mark(
      'home.unlinked.banner',
      Card(
        margin: const EdgeInsets.only(bottom: AppSpacing.sp4),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(
            '/records?${AppParams.memberFilter}=${AppParams.unlinkedMembers}',
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sp4),
            child: Row(
              children: [
                Icon(Icons.link, color: colors.primary),
                const SizedBox(width: AppSpacing.sp3),
                Expanded(
                  child: Text(
                    keepPhrasesWhole('회원이 연결되지 않은 기록 $count개가 있어요'),
                    style: context.texts.bodyMedium,
                  ),
                ),
                const SizedBox(width: AppSpacing.sp2),
                Text(
                  '연결하기',
                  style: context.texts.labelLarge?.copyWith(
                    color: colors.primary,
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

class _ExpectedSection extends StatefulWidget {
  final DateTime now;
  final List<ExpectedMember> expected;
  const _ExpectedSection({required this.now, required this.expected});

  @override
  State<_ExpectedSection> createState() => _ExpectedSectionState();
}

class _ExpectedSectionState extends State<_ExpectedSection> {
  /// "+N명 더"로 나머지를 펼쳤는지. 다른 화면으로 보내지 않고 이 자리에서 연다.
  bool expanded = false;

  DateTime get now => widget.now;
  List<ExpectedMember> get expected => widget.expected;

  String _subtitle(ExpectedMember e) {
    final last = e.lastSameWeekday;
    final weeks = (calendarDaysBetween(last, now) / 7).round();
    final when = weeks <= 1 ? '지난주' : '$weeks주 전';
    return '보통 ${_clock(last)} · $when ${last.month}.${_two(last.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final weekday = HomeScreen._weekdays[now.weekday - 1];
    final overflow = expected.length - HomeScreen.maxExpected;
    final shown = expanded || overflow <= 0
        ? expected
        : expected.take(HomeScreen.maxExpected).toList();
    final secondary = context.texts.bodySmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    return mark(
      'home.expected.section',
      panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cardTitle(
              context,
              Icons.event_available_outlined,
              '오늘 예상 회원',
              caption: '지난 4주 $weekday요일 기록 기준',
            ),
            if (expected.isEmpty) ...[
              mark(
                'home.expected.empty',
                Text(keepPhrasesWhole('오늘 요일에 기록된 회원이 없어요'), style: secondary),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: mark(
                  'home.expected.members.button',
                  TextButton.icon(
                    onPressed: () => context.go('/members'),
                    icon: const Icon(Icons.people_outline),
                    label: const Text('회원 목록 보기'),
                  ),
                ),
              ),
            ],
            for (final e in shown)
              mark(
                'home.expected.${e.member.id}.row',
                InkWell(
                  borderRadius: AppRadius.mdAll,
                  onTap: () => context.push('/members/${e.member.id}'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sp2,
                    ),
                    child: Row(
                      children: [
                        MemberAvatar(e.member.name, active: !e.recordedToday),
                        const SizedBox(width: AppSpacing.sp3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.member.name,
                                style: context.texts.titleSmall,
                              ),
                              Text(
                                _subtitle(e),
                                style: context.numericTexts.bodySmall.copyWith(
                                  color: context.colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sp2),
                        if (e.recordedToday)
                          StatusPill(
                            label: '오늘 기록함',
                            icon: Icons.check,
                            identifier: 'home.expected.${e.member.id}.done',
                          )
                        else
                          mark(
                            'home.expected.${e.member.id}.lesson.button',
                            FilledButton.tonal(
                              onPressed: () => context.push(
                                '/members/${e.member.id}/lessons/new',
                              ),
                              child: const Text('레슨 기록'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            if (overflow > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: mark(
                  'home.expected.more.button',
                  TextButton.icon(
                    onPressed: () => setState(() => expanded = !expanded),
                    icon: Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                    ),
                    label: Text(expanded ? '접기' : '+$overflow명 더'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RecentSection extends StatelessWidget {
  final RecordWithPhotos lesson;
  final Member member;
  final bool canCompare;
  const _RecentSection({
    required this.lesson,
    required this.member,
    required this.canCompare,
  });

  @override
  Widget build(BuildContext context) {
    final r = lesson.record;
    final photos = lesson.photos;
    final summary = [
      if (photos.isNotEmpty) '사진 ${photos.length}장',
      if (lesson.videos.isNotEmpty) '동영상 ${lesson.videos.length}개',
      if ((r.memo ?? '').trim().isNotEmpty ||
          (r.condition ?? '').trim().isNotEmpty)
        '일지',
    ].join(' · ');
    // 수업 전·후 사진이 있으면 그 사진만 전 → 후, 방향 순으로 최대 4장 보인다.
    final beforeAfter =
        photos.where((p) => p.phase == 'before' || p.phase == 'after').toList()
          ..sort((a, b) {
            if (a.phase != b.phase) return a.phase == 'before' ? -1 : 1;
            return a.direction.index.compareTo(b.direction.index);
          });
    final thumbs = beforeAfter.take(4).toList();
    return mark(
      'home.recent.section',
      panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cardTitle(context, Icons.history, '방금 레슨한 회원'),
            Row(
              children: [
                MemberAvatar(member.name),
                const SizedBox(width: AppSpacing.sp3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(member.name, style: context.texts.titleSmall),
                      Text(
                        lessonDateDisplay(r.shotAt),
                        style: context.numericTexts.bodySmall.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (summary.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sp2),
                child: mark(
                  'home.recent.summary',
                  Text(summary, style: context.texts.bodyMedium),
                ),
              ),
            if (thumbs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sp3),
                child: photoGrid([
                  for (final p in thumbs)
                    LessonPhotoThumb(
                      identifier: 'home.recent.photo.${p.id}',
                      path: p.filePath,
                      label: '${phases[p.phase]} ${p.direction.label}',
                    ),
                ]),
              ),
            const SizedBox(height: AppSpacing.sp3),
            Row(
              children: [
                Expanded(
                  child: mark(
                    'home.recent.open.button',
                    FilledButton.tonalIcon(
                      onPressed: () => context.push('/lessons/${r.id}'),
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('레슨 보기'),
                    ),
                  ),
                ),
                if (canCompare) ...[
                  const SizedBox(width: AppSpacing.sp3),
                  Expanded(
                    child: mark(
                      'home.recent.compare.button',
                      OutlinedButton.icon(
                        onPressed: () =>
                            context.push('/members/${member.id}/compare'),
                        icon: const Icon(Icons.compare_arrows),
                        label: const Text('변화 비교'),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekSection extends StatelessWidget {
  final WeekStats stats;
  const _WeekSection({required this.stats});

  @override
  Widget build(BuildContext context) {
    final start = stats.weekStart;
    Widget cell(String id, int value, String label) => Expanded(
      child: mark(
        'home.week.$id.button',
        Semantics(
          button: true,
          label: '이번 주 $label $value',
          excludeSemantics: true,
          child: InkWell(
            borderRadius: AppRadius.mdAll,
            onTap: () => context.go('/records'),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.sp2,
                horizontal: AppSpacing.sp1,
              ),
              child: Column(
                children: [
                  Text(
                    '$value',
                    style: context.numericTexts.headlineSmall.copyWith(
                      color: context.colors.onSurface,
                    ),
                  ),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: context.texts.labelMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return mark(
      'home.week.section',
      panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cardTitle(
              context,
              Icons.calendar_view_week_outlined,
              '이번 주',
              caption: '${start.month}.${_two(start.day)} 월요일부터',
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                cell('lessons', stats.lessons, '레슨'),
                cell('photos', stats.photoRecords, '사진 기록'),
                cell('members', stats.members, '회원'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IdleSection extends StatelessWidget {
  final List<IdleMember> idle;
  const _IdleSection({required this.idle});

  @override
  Widget build(BuildContext context) {
    return mark(
      'home.idle.section',
      panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cardTitle(
              context,
              Icons.hourglass_empty,
              '한동안 기록이 없는 회원',
              caption: '마지막 레슨 뒤 $idleThresholdDays일 이상 지난 회원',
            ),
            for (final e in idle.take(HomeScreen.maxIdle))
              mark(
                'home.idle.${e.member.id}.row',
                InkWell(
                  borderRadius: AppRadius.mdAll,
                  onTap: () => context.push('/members/${e.member.id}'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sp2,
                    ),
                    child: Row(
                      children: [
                        MemberAvatar(e.member.name, active: false),
                        const SizedBox(width: AppSpacing.sp3),
                        Expanded(
                          child: Text(
                            e.member.name,
                            style: context.texts.titleSmall,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sp2),
                        StatusPill(
                          label: e.days == null ? '아직 레슨 없음' : '${e.days}일 전',
                          tone: e.days == null
                              ? StatusPillTone.neutral
                              : StatusPillTone.warning,
                          identifier: 'home.idle.${e.member.id}.days',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
