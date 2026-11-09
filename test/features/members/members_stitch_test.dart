import 'package:bodymark/core/models/models.dart';
import 'package:bodymark/core/theme/app_theme.dart';
import 'package:bodymark/features/members/lesson_screens.dart';
import 'package:bodymark/features/members/member.dart';
import 'package:bodymark/features/members/member_providers.dart';
import 'package:bodymark/features/members/member_screens.dart';
import 'package:bodymark/features/members/ui.dart';
import 'package:bodymark/features/records/providers/records_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

final _at = DateTime(2026, 11, 4, 15);

Member _member(
  String id,
  String name, {
  String precautions = '',
  String goal = '',
  String reason = '',
}) => Member(
  id: id,
  name: name,
  precautions: precautions,
  goal: goal,
  reason: reason,
  createdAt: _at,
  updatedAt: _at,
);

RecordWithPhotos _lesson(
  String id,
  String? memberId,
  DateTime at, {
  Map<String, int> phases = const {},
  String memo = '',
}) {
  final photos = <BodyPhoto>[];
  for (final e in phases.entries) {
    for (var i = 0; i < e.value; i++) {
      photos.add(
        BodyPhoto(
          id: '$id-${e.key}-$i',
          recordId: id,
          filePath: 'photos/202611/$id-${e.key}-$i.jpg',
          direction: BodyDirection.values[i % 4],
          phase: e.key,
          capturedAt: at,
          createdAt: at,
        ),
      );
    }
  }
  return RecordWithPhotos(
    record: PhotoRecord(
      id: id,
      memberId: memberId,
      shotAt: at,
      memo: memo,
      createdAt: at,
      updatedAt: at,
    ),
    photos: photos,
  );
}

/// 화면을 GoRouter 안에서 띄운다. [routes]로 이동 대상 화면을 바꿔 끼운다.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required String initial,
  required List<Member> members,
  List<RecordWithPhotos> lessons = const [],
  List<RouteBase> extraRoutes = const [],
  Size size = const Size(360, 800),
  double textScale = 1,
  List<Override> overrides = const [],
  DateTime? clock,
  Widget Function(String memberId)? lessonNewBuilder,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final membersState = StateProvider<List<Member>>((ref) => members);
  final container = ProviderContainer(
    overrides: [
      membersProvider.overrideWith((ref) async => ref.watch(membersState)),
      timelineProvider.overrideWith((ref) async => lessons),
      clockProvider.overrideWithValue(() => clock ?? _at),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  _membersState = membersState;
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(path: '/', builder: (_, _) => const MembersScreen()),
      GoRoute(path: '/records', builder: (_, _) => const LessonRecordsScreen()),
      GoRoute(
        path: '/members/:id',
        builder: (_, s) =>
            MemberDetailScreen(memberId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/members/:id/lessons/new',
        builder: (_, s) =>
            lessonNewBuilder?.call(s.pathParameters['id']!) ??
            LessonEditorScreen(memberId: s.pathParameters['id']!),
      ),
      ...extraRoutes,
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light,
        locale: const Locale('ko', 'KR'),
        supportedLocales: const [Locale('ko', 'KR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

late StateProvider<List<Member>> _membersState;

void main() {
  group('도우미', () {
    test('이니셜은 성을 빼고 이름 두 글자, 영문은 단어 첫 글자', () {
      expect(memberInitials('김서연'), '서연');
      expect(memberInitials('Lee Test'), 'LT');
      expect(memberInitials('민'), '민');
    });
    test('주의 키워드는 첫 구절만', () {
      expect(cautionKeyword('손목 부하 주의 · 산후 6개월'), '손목 부하 주의');
      expect(cautionKeyword(''), '');
    });
    test('짧은 일시와 구분 요약', () {
      expect(shortLessonDate(_at), '11.04 오후 3:00');
      final item = _lesson('r', 'm', _at, phases: {'before': 4, 'after': 2});
      expect(phaseSummary(item.photos), '수업 전 4장 · 수업 후 2장');
    });
  });

  testWidgets('02 회원 목록은 총 인원·최근 레슨·주의 칩을 보여 준다', (tester) async {
    await _pump(
      tester,
      initial: '/',
      members: [
        _member('m1', '김서연', precautions: '손목 부하 주의 · 산후 6개월'),
        _member('m2', '이지민'),
      ],
      lessons: [_lesson('r1', 'm1', _at)],
    );
    expect(find.text('전체 회원 2명'), findsOneWidget);
    expect(find.text('최근 레슨 11.04 오후 3:00'), findsOneWidget);
    expect(find.text('아직 레슨 기록이 없어요'), findsOneWidget);
    expect(find.byKey(const ValueKey('members.m1.caution')), findsOneWidget);
    expect(find.text('손목 부하 주의'), findsOneWidget);
    expect(find.text('서연'), findsOneWidget);
    // 최근 레슨순: 레슨이 있는 회원이 먼저.
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('members.m1.card'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('members.m2.card'))).dy,
      ),
    );
  });

  testWidgets('01 회원이 없으면 검색창 없이 첫 등록 안내만 보인다', (tester) async {
    await _pump(tester, initial: '/', members: const []);
    expect(find.byKey(const ValueKey('members.search.field')), findsNothing);
    expect(find.text('첫 회원을 등록해보세요'), findsOneWidget);
    expect(find.text('회원 등록하기'), findsOneWidget);
  });

  testWidgets('03 검색 결과가 없으면 검색 지우기로 목록이 돌아온다', (tester) async {
    await _pump(tester, initial: '/', members: [_member('m1', '김서연')]);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('members.search.field')),
        matching: find.byType(TextField),
      ),
      '없는이름',
    );
    await tester.pumpAndSettle();
    expect(find.text('검색 결과가 없어요'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('members.empty.add.button')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('members.empty.clear.button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('members.m1.card')), findsOneWidget);
  });

  testWidgets('05 바로 촬영은 그 회원의 새 레슨에서 촬영 준비를 연다', (tester) async {
    final container = await _pump(
      tester,
      initial: '/members/m1',
      members: [_member('m1', '김서연')],
    );
    await tester.tap(find.byKey(const ValueKey('members.capture.button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('screen.capture.preparation')),
      findsOneWidget,
    );
    expect(container.read(quickCaptureRequestProvider), isNull);
    // 촬영 준비를 닫으면 같은 회원의 레슨 작성 화면이 남는다.
    Navigator.of(
      tester.element(find.byKey(const ValueKey('screen.capture.preparation'))),
    ).pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('screen.lessons.edit')), findsOneWidget);
  });

  testWidgets('05 주의사항은 앰버 블록, 레슨 수와 수업 전/후 요약이 보인다', (tester) async {
    await _pump(
      tester,
      initial: '/members/m1',
      members: [
        _member('m1', '김서연', precautions: '손목 부하 주의 · 산후 6개월\n장시간 무릎 꿇기 피하기'),
      ],
      lessons: [
        _lesson('r1', 'm1', _at, phases: {'before': 4, 'after': 4}),
        _lesson('r2', 'm1', _at.subtract(const Duration(days: 2))),
      ],
    );
    expect(find.text('손목 부하 주의 · 산후 6개월'), findsOneWidget);
    expect(find.text('장시간 무릎 꿇기 피하기'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('members.detail.caution')));
    await tester.pumpAndSettle();
    expect(find.text('장시간 무릎 꿇기 피하기'), findsOneWidget);
    expect(find.textContaining('레슨 기록 2'), findsOneWidget);
    expect(find.text('체형 사진 8장 (수업 전 4장 · 수업 후 4장)'), findsOneWidget);
    expect(find.text('수업 후 체형 사진'), findsOneWidget);
    expect(find.text('상세보기'), findsOneWidget);
  });

  testWidgets('06 레슨이 없으면 카드 안 빈 상태를 보여 준다', (tester) async {
    await _pump(
      tester,
      initial: '/members/m1',
      members: [_member('m1', '김서연')],
    );
    expect(find.byKey(const ValueKey('members.lessons.empty')), findsOneWidget);
    expect(find.textContaining('사진 없이 일지만 남겨도 좋아요.'), findsOneWidget);
  });

  testWidgets('42 회원 삭제 확인은 함께 지워질 레슨·사진 수를 알려 준다', (tester) async {
    await _pump(
      tester,
      initial: '/members/m1',
      members: [_member('m1', '김서연')],
      lessons: [
        _lesson('r1', 'm1', _at, phases: {'before': 4}),
        _lesson('r2', 'm1', _at, phases: {'after': 2}),
      ],
    );
    final delete = find.byKey(const ValueKey('members.delete.button'));
    await tester.scrollUntilVisible(
      delete,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(delete);
    await tester.pumpAndSettle();
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(find.text('이 회원과 기록을 삭제할까요?'), findsOneWidget);
    expect(find.text('김서연 회원의 레슨 기록 2개와 사진 6장이 함께 삭제돼요.'), findsOneWidget);
    expect(find.text('회원 삭제'), findsWidgets);
    await tester.tap(
      find.byKey(const ValueKey('common.confirm.cancel.button')),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('11 레슨 일시는 한 시트에서 날짜와 시각을 함께 바꾼다', (tester) async {
    await _pump(
      tester,
      initial: '/members/m1/lessons/new',
      members: [_member('m1', '김서연')],
    );
    expect(find.text('2026.11.04 (수) 오후 3:00'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lessons.date.field')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lessons.dateSheet')), findsOneWidget);
    expect(find.byType(CalendarDatePicker), findsOneWidget);
    // 두 번째 다이얼로그 없이 같은 시트에서 날짜·오전/오후를 고른다.
    await tester.tap(find.text('5'));
    await tester.tap(find.text('오전'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('lessons.dateSheet.apply.button')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lessons.dateSheet')), findsNothing);
    expect(find.text('2026.11.05 (목) 오전 3:00'), findsOneWidget);
  });

  testWidgets('07 저장은 하단 고정 버튼이고 빈 일지는 버튼 위에 안내한다', (tester) async {
    await _pump(
      tester,
      initial: '/members/m1/lessons/new',
      members: [_member('m1', '김서연', precautions: '손목 부하 주의')],
    );
    expect(
      find.byKey(const ValueKey('lessons.caution.status')),
      findsOneWidget,
    );
    expect(find.byType(SegmentedButton<String>), findsOneWidget);
    final barFinder = find.byKey(const ValueKey('lessons.save.bar'));
    expect(tester.getRect(barFinder).bottom, 800);
    await tester.tap(find.byKey(const ValueKey('lessons.save.button')));
    await tester.pumpAndSettle();
    final error = find.byKey(const ValueKey('lessons.save.error'));
    expect(find.descendant(of: barFinder, matching: error), findsOneWidget);
    expect(find.text('일지 또는 사진을 추가해주세요.'), findsOneWidget);
  });

  testWidgets('14 삭제된 회원으로 걸린 필터는 전체 회원으로 돌아간다', (tester) async {
    final container = await _pump(
      tester,
      initial: '/records',
      members: [_member('m1', '김서연'), _member('m2', '이지민')],
      lessons: [
        _lesson('r1', 'm1', _at, memo: '서연 일지'),
        _lesson('r2', 'm2', _at, memo: '지민 일지'),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('lessons.member.filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이지민').last);
    await tester.pumpAndSettle();
    expect(find.byTooltip('회원 필터: 이지민'), findsOneWidget);
    expect(find.text('총 1개의 레슨 기록'), findsOneWidget);

    container.read(_membersState.notifier).state = [_member('m1', '김서연')];
    await tester.pumpAndSettle();
    expect(find.byTooltip('회원 필터: 전체 회원'), findsOneWidget);
    expect(find.text('총 2개의 레슨 기록'), findsOneWidget);
  });

  testWidgets('14 필터로 0건이면 필터 지우기를 제공한다', (tester) async {
    await _pump(
      tester,
      initial: '/records',
      members: [_member('m1', '김서연')],
      lessons: [_lesson('r1', 'm1', _at, memo: '서연 일지')],
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('lessons.search.field')),
        matching: find.byType(TextField),
      ),
      '없는말',
    );
    await tester.pumpAndSettle();
    expect(find.text('조건에 맞는 기록이 없어요'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('lessons.records.clear.button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('총 1개의 레슨 기록'), findsOneWidget);
  });

  testWidgets('15 기록 불러오기 실패는 다시 불러오기를 제공한다', (tester) async {
    var calls = 0;
    await _pump(
      tester,
      initial: '/records',
      members: [_member('m1', '김서연')],
      overrides: [
        timelineProvider.overrideWith((ref) async {
          calls++;
          throw StateError('db');
        }),
      ],
    );
    expect(find.text('기록을 불러오지 못했어요'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('lessons.records.error.retry.button')),
    );
    await tester.pumpAndSettle();
    expect(calls, greaterThan(1));
  });

  List<Override> detailOverrides(RecordWithPhotos item) => [
    recordProvider.overrideWith(
      (ref, id) async => id == item.record.id ? item.record : null,
    ),
    recordPhotosProvider.overrideWith((ref, id) async => item.photos),
  ];
  final detailRoute = GoRoute(
    path: '/lessons/:id',
    builder: (_, s) => LessonDetailScreen(recordId: s.pathParameters['id']!),
  );

  testWidgets('13 사진 있는 상세는 구분별 4열 묶음과 전후 비교를 보여 준다', (tester) async {
    final item = _lesson('r1', 'm1', _at, phases: {'before': 4, 'after': 4});
    await _pump(
      tester,
      initial: '/lessons/r1',
      members: [_member('m1', '김서연')],
      extraRoutes: [detailRoute],
      overrides: detailOverrides(item),
    );
    expect(find.byKey(const ValueKey('lessons.detail.date')), findsOneWidget);
    expect(find.text('사진 8장'), findsOneWidget);
    final section = find.byKey(const ValueKey('lessons.photos.section'));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('lessons.group.after.header')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.descendant(of: section, matching: find.text('수업 전 (4장 완료)')),
      findsOneWidget,
    );
    expect(find.text('수업 후 (4장 완료)'), findsOneWidget);
    expect(find.text('전후 비교'), findsOneWidget);
    // 한 묶음 네 장은 같은 줄에 같은 너비로 놓인다.
    final tiles = [
      for (var i = 0; i < 4; i++)
        tester.getRect(
          find.byKey(ValueKey('lessons.photo.r1-before-$i.button')),
        ),
    ];
    for (final r in tiles) {
      expect(r.top, tiles.first.top);
      expect(r.width, closeTo(tiles.first.width, 0.01));
    }
  });

  testWidgets('41 레슨 삭제 확인은 일시와 사진 수를 알려 준다', (tester) async {
    final item = _lesson('r1', 'm1', _at, phases: {'before': 4, 'after': 4});
    await _pump(
      tester,
      initial: '/lessons/r1',
      members: [_member('m1', '김서연')],
      extraRoutes: [detailRoute],
      overrides: detailOverrides(item),
    );
    final delete = find.byKey(const ValueKey('lessons.delete.button'));
    await tester.scrollUntilVisible(
      delete,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(delete);
    await tester.pumpAndSettle();
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(find.text('이 레슨 기록을 삭제할까요?'), findsOneWidget);
    expect(find.textContaining('11.04 오후 3:00 레슨의 일지와 사진 8장'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('common.confirm.cancel.button')),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('12 사진 없는 상세는 사진 추가 진입을 제공한다', (tester) async {
    final item = _lesson('r1', 'm1', _at, memo: '호흡 위주');
    await _pump(
      tester,
      initial: '/lessons/r1',
      members: [_member('m1', '김서연')],
      extraRoutes: [detailRoute],
      overrides: detailOverrides(item),
    );
    expect(find.text('수업 일지'), findsOneWidget);
    expect(find.text('사진 없이 작성한 레슨 기록이에요.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('lessons.photos.add.button')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('lessons.edit.button')), findsOneWidget);
  });

  testWidgets('43 기존 기록 연결은 회원을 미리 고르지 않는다', (tester) async {
    final item = _lesson('r1', null, _at, phases: {'regular': 2});
    await _pump(
      tester,
      initial: '/link',
      members: [_member('m1', '김서연'), _member('m2', '이지민')],
      extraRoutes: [
        GoRoute(
          path: '/link',
          builder: (_, _) => LinkRecordScreen(record: item.record),
        ),
      ],
      overrides: detailOverrides(item),
    );
    FilledButton save() => tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const ValueKey('lessons.link.save.button')),
        matching: find.byType(FilledButton),
      ),
    );
    expect(save().onPressed, isNull);
    expect(find.text('11.04 오후 3:00 · 사진 2장'), findsOneWidget);
    expect(find.textContaining('촬영 시각(15:00)'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('lessons.link.later.button')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('lessons.link.m2.radio')));
    await tester.pumpAndSettle();
    expect(save().onPressed, isNotNull);
  });

  testWidgets('레슨 상세는 320dp·2배 글꼴에서 넘치지 않는다', (tester) async {
    final item = _lesson('r1', 'm1', _at, phases: {'before': 4, 'after': 4});
    await _pump(
      tester,
      initial: '/lessons/r1',
      size: const Size(320, 640),
      textScale: 2,
      members: [_member('m1', '김서연')],
      extraRoutes: [detailRoute],
      overrides: detailOverrides(item),
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  /// [screen]을 버튼으로 push하고 pop 결과를 [onResult]로 받는다.
  GoRoute launcher<T>(Widget screen, void Function(T?) onResult) => GoRoute(
    path: '/launch',
    builder: (context, _) => Scaffold(
      body: Center(
        child: Builder(
          builder: (context) => TextButton(
            key: const ValueKey('test.launch'),
            onPressed: () async => onResult(
              await Navigator.of(
                context,
              ).push<T>(MaterialPageRoute(builder: (_) => screen)),
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    ),
  );

  testWidgets('16/17 촬영 준비는 최근 기록을 추천하고 기준 없이 촬영으로 바꿀 수 있다', (tester) async {
    LessonCaptureContext? result;
    await _pump(
      tester,
      initial: '/launch',
      members: [_member('m1', '김서연')],
      lessons: [
        _lesson('r1', 'm1', _at, phases: {'before': 4}),
        _lesson(
          'r0',
          'm1',
          _at.subtract(const Duration(days: 7)),
          phases: {'regular': 4},
        ),
      ],
      extraRoutes: [
        launcher<LessonCaptureContext>(
          CapturePreparationScreen(
            memberId: 'm1',
            phase: 'before',
            lessonAt: _at,
          ),
          (r) => result = r,
        ),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('test.launch')));
    await tester.pumpAndSettle();
    expect(find.text('김서연 회원'), findsOneWidget);
    expect(find.text('오늘 수업 전 4장'), findsOneWidget);
    expect(find.text('추천'), findsOneWidget);
    expect(find.text('1. 정면'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('capture.baseline.change.button')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('capture.baseline.sheet')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('capture.baseline.r0')), findsOneWidget);
    expect(find.text('같은 회원의 사진만 표시돼요.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('capture.baseline.none')));
    await tester.pumpAndSettle();
    expect(find.text('기준 없이 촬영'), findsOneWidget);

    await tester.tap(find.text('수업 후'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('capture.start.button')));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.useBaseline, isFalse);
    expect(result!.phase, 'after');
    expect(result!.lessonAt, _at);
  });

  testWidgets('16 기본값은 추천 기록을 기준으로 넘긴다', (tester) async {
    LessonCaptureContext? result;
    await _pump(
      tester,
      initial: '/launch',
      members: [_member('m1', '김서연')],
      lessons: [
        _lesson('r1', 'm1', _at, phases: {'before': 4}),
      ],
      extraRoutes: [
        launcher<LessonCaptureContext>(
          CapturePreparationScreen(
            memberId: 'm1',
            phase: 'before',
            lessonAt: _at,
          ),
          (r) => result = r,
        ),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('test.launch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('capture.start.button')));
    await tester.pumpAndSettle();
    expect(result!.useBaseline, isTrue);
    expect(result!.baselineRecordId, 'r1');
  });

  testWidgets('25 사진 연결은 구분·방향을 골라 원본 경로 그대로 넘긴다', (tester) async {
    List<PendingLessonPhoto>? result;
    await _pump(
      tester,
      initial: '/launch',
      members: [_member('m1', '김서연')],
      extraRoutes: [
        launcher<List<PendingLessonPhoto>>(
          AssignPhotosScreen(
            paths: const ['/no/such/a.jpg', '/no/such/b.jpg'],
            phase: 'before',
            memberName: '김서연',
            lessonAt: _at,
          ),
          (r) => result = r,
        ),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('test.launch')));
    await tester.pumpAndSettle();
    // 없는 파일이라 EXIF를 못 읽는다. 실제 파일 I/O가 끝나게 기다린다.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('김서연 · 11.04 오후 3:00 레슨'), findsOneWidget);
    expect(find.text('실제 촬영 시각 확인 불가'), findsWidgets);
    await tester.tap(find.text('수업 후'));
    await tester.pumpAndSettle();
    final summary = find.byKey(const ValueKey('lessons.assign.summary'));
    await tester.scrollUntilVisible(
      summary,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('[수업 후] 사진으로 연결돼요'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('lessons.assign.0.direction.back')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.byKey(const ValueKey('lessons.assign.0.direction.back')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('lessons.photos.attach.button')),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(result, hasLength(2));
    expect(result![0].path, '/no/such/a.jpg');
    expect(result![0].direction, BodyDirection.back);
    expect(result![0].phase, 'after');
    expect(result![1].direction, BodyDirection.leftSide);
    expect(result![0].capturedAt, isNull);
  });

  for (final (name, screen) in [
    (
      '촬영 준비',
      CapturePreparationScreen(memberId: 'm1', phase: 'before', lessonAt: _at)
          as Widget,
    ),
    (
      '사진 연결',
      AssignPhotosScreen(
        paths: const ['/no/such/a.jpg'],
        phase: 'before',
        memberName: '김서연',
        lessonAt: _at,
      ),
    ),
  ]) {
    testWidgets('$name은 320dp·2배 글꼴에서 넘치지 않는다', (tester) async {
      await _pump(
        tester,
        initial: '/launch',
        size: const Size(320, 640),
        textScale: 2,
        members: [_member('m1', '김서연')],
        lessons: [
          _lesson('r1', 'm1', _at, phases: {'before': 4, 'after': 4}),
        ],
        extraRoutes: [launcher<Object>(screen, (_) {})],
      );
      await tester.tap(find.byKey(const ValueKey('test.launch')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('바로 촬영 요청은 돌아오면 비워져 레슨 기록하기가 촬영을 열지 않는다', (tester) async {
    final container = await _pump(
      tester,
      initial: '/members/m1',
      members: [_member('m1', '김서연')],
    );
    await tester.tap(find.byKey(const ValueKey('members.capture.button')));
    await tester.pumpAndSettle();
    final prep = find.byKey(const ValueKey('screen.capture.preparation'));
    Navigator.of(tester.element(prep)).pop();
    await tester.pumpAndSettle();
    Navigator.of(
      tester.element(find.byKey(const ValueKey('screen.lessons.edit'))),
    ).pop();
    await tester.pumpAndSettle();
    expect(container.read(quickCaptureRequestProvider), isNull);

    await tester.tap(find.byKey(const ValueKey('members.lesson.add.button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('screen.lessons.edit')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('screen.capture.preparation')),
      findsNothing,
    );
  });

  testWidgets('레슨 화면이 요청을 읽지 못하고 닫혀도 돌아오면 요청이 비워진다', (tester) async {
    final container = await _pump(
      tester,
      initial: '/members/m1',
      members: [_member('m1', '김서연')],
      // 요청을 소비하지 않는 대체 화면.
      lessonNewBuilder: (_) =>
          const Scaffold(key: ValueKey('test.lesson.stub')),
    );
    await tester.tap(find.byKey(const ValueKey('members.capture.button')));
    await tester.pumpAndSettle();
    expect(container.read(quickCaptureRequestProvider), 'm1');
    Navigator.of(
      tester.element(find.byKey(const ValueKey('test.lesson.stub'))),
    ).pop();
    await tester.pumpAndSettle();
    expect(container.read(quickCaptureRequestProvider), isNull);
  });

  testWidgets('날짜 시트를 바꾸지 않고 적용하면 초까지 원래 값이고 변경으로 보지 않는다', (tester) async {
    final withSeconds = DateTime(2026, 11, 4, 15, 0, 37, 250);
    await _pump(
      tester,
      initial: '/members/m1',
      clock: withSeconds,
      members: [_member('m1', '김서연')],
    );
    await tester.tap(find.byKey(const ValueKey('members.lesson.add.button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lessons.date.field')));
    await tester.pumpAndSettle();
    final sheet = tester.element(
      find.byKey(const ValueKey('lessons.dateSheet')),
    );
    // 시트 상태의 반환값을 직접 확인한다.
    final state = sheet.findAncestorStateOfType<State<LessonDateSheet>>();
    expect((state as dynamic).value, withSeconds);
    await tester.tap(
      find.byKey(const ValueKey('lessons.dateSheet.apply.button')),
    );
    await tester.pumpAndSettle();
    // 변경이 없으므로 뒤로 가도 "작성한 내용을 버릴까요?"가 뜨지 않는다.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('작성한 내용을 버릴까요?'), findsNothing);
    expect(find.byKey(const ValueKey('screen.members.detail')), findsOneWidget);
  });

  testWidgets('10 키보드가 열려도 저장 바는 키보드 위에 보인다', (tester) async {
    await _pump(
      tester,
      initial: '/members/m1/lessons/new',
      members: [_member('m1', '김서연')],
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final save = tester.getRect(
      find.byKey(const ValueKey('lessons.save.button')),
    );
    expect(save.bottom, lessThanOrEqualTo(800 - 300));
    expect(save.top, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  for (final (name, path) in [
    ('회원 목록', '/'),
    ('회원 상세', '/members/m1'),
    ('레슨 작성', '/members/m1/lessons/new'),
    ('전체 기록', '/records'),
  ]) {
    testWidgets('$name은 320dp·2배 글꼴에서 넘치지 않는다', (tester) async {
      await _pump(
        tester,
        initial: path,
        size: const Size(320, 640),
        textScale: 2,
        members: [
          _member(
            'm1',
            '김서연',
            precautions: '손목 부하 주의 · 산후 6개월',
            goal: '편안한 일상 움직임',
            reason: '출산 후 운동 재개',
          ),
        ],
        lessons: [
          _lesson(
            'r1',
            'm1',
            _at,
            phases: {'before': 4, 'after': 4},
            memo: '호흡 위주',
          ),
        ],
      );
      expect(tester.takeException(), isNull);
    });
  }
}
