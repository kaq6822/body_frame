import 'dart:async';

import 'package:bodymark/core/korean_text.dart';
import 'package:bodymark/core/services/app_image_picker.dart';
import 'package:bodymark/core/theme/app_theme.dart';
import 'package:bodymark/features/home/home_screen.dart';
import 'package:bodymark/features/members/member.dart';
import 'package:bodymark/features/members/member_providers.dart';
import 'package:bodymark/features/records/providers/records_providers.dart';
import 'package:bodymark/features/settings/providers/settings_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../videos/video_fakes.dart';
import 'home_fixtures.dart';

Finder key(String id) => find.byKey(ValueKey(id));

Future<GoRouter> _pump(
  WidgetTester tester, {
  Future<List<Member>> Function()? members,
  Future<List<RecordWithPhotos>> Function()? lessons,
  int unlinked = 0,
  double textScale = 1,
  DateTime Function()? clock,
  AppImagePicker? picker,
  ImagePickerRequestStore? store,
}) async {
  Widget stub(GoRouterState s) => Scaffold(body: Text('at ${s.uri}'));
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      for (final path in [
        '/members',
        '/members/new',
        '/members/:id',
        '/members/:id/lessons/new',
        '/members/:id/compare',
        '/lessons/:id',
        '/records',
      ])
        GoRoute(path: path, builder: (_, s) => stub(s)),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(clock ?? () => now),
        membersProvider.overrideWith(
          (ref) => members?.call() ?? Future.value(_members),
        ),
        // 미연결 기록 수는 홈이 같은 타임라인에서 센다.
        timelineProvider.overrideWith(
          (ref) async => [
            ...await (lessons?.call() ?? Future.value(_lessons())),
            for (var i = 0; i < unlinked; i++)
              lesson(null, DateTime(2026, 9, 1), id: 'unlinked$i'),
          ],
        ),
        // 홈은 이 값을 쓰지 않는다. 설정과 어긋나도 홈 띠는 타임라인을 따른다.
        unlinkedRecordCountProvider.overrideWith((ref) async => 99),
        appImagePickerProvider.overrideWithValue(picker ?? FakeVideoPicker()),
        imagePickerRequestStoreProvider.overrideWithValue(
          store ?? MemoryRequestStore(),
        ),
      ],
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
  return router;
}

final _members = [
  member('m1', name: '김서연'),
  member('m2', name: '박지훈'),
  member('m3', name: '이하늘'),
];

List<RecordWithPhotos> _lessons() => [
  lesson('m1', DateTime(2026, 11, 10, 15), phases: ['before']),
  lesson('m2', DateTime(2026, 11, 10, 9, 30)),
  // 오늘 9:30에 m1이 이미 레슨을 기록했다. 가장 최근 레슨이기도 하다.
  lesson(
    'm1',
    DateTime(2026, 11, 17, 9, 30),
    id: 'latest',
    phases: ['before', 'before', 'after', 'after', 'after'],
    videos: 1,
    memo: '호흡',
  ),
  lesson('m3', DateTime(2026, 10, 1, 10)),
];

Future<void> reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('머리에 워드마크·오늘 날짜·회원 추가가 있다', (tester) async {
    await _pump(tester);
    expect(key(HomeScreen.screenId), findsOneWidget);
    expect(key('home.brand.wordmark'), findsOneWidget);
    expect(find.text('11월 17일 화요일'), findsOneWidget);
    await tester.tap(key('home.member.add.button'));
    await tester.pumpAndSettle();
    expect(find.text('at /members/new'), findsOneWidget);
  });

  testWidgets('오늘 예상 회원은 시각순이고 오늘 기록한 회원은 표시와 함께 뒤에 있다', (tester) async {
    final router = await _pump(tester);
    expect(key('home.expected.section'), findsOneWidget);
    expect(
      find.textContaining(keepPhrasesWhole('지난 4주 화요일 기록 기준')),
      findsOneWidget,
    );
    // m1은 보통 m2보다 늦지만 오늘 이미 기록해 아래로 간다.
    final m1 = tester.getTopLeft(key('home.expected.m1.row')).dy;
    final m2 = tester.getTopLeft(key('home.expected.m2.row')).dy;
    expect(m2, lessThan(m1));
    expect(key('home.expected.m1.done'), findsOneWidget);
    expect(key('home.expected.m1.lesson.button'), findsNothing);
    expect(find.textContaining('보통 '), findsNWidgets(2));
    expect(find.textContaining('지난주 11.10'), findsNWidgets(2));

    await tester.tap(key('home.expected.m2.lesson.button'));
    await tester.pumpAndSettle();
    expect(find.text('at /members/m2/lessons/new'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(key('home.expected.m1.row'));
    await tester.pumpAndSettle();
    expect(find.text('at /members/m1'), findsOneWidget);
  });

  testWidgets('예상 회원이 없으면 짧은 빈 상태와 회원 목록 링크를 보인다', (tester) async {
    await _pump(
      tester,
      lessons: () async => [lesson('m1', DateTime(2026, 11, 16, 10))],
    );
    expect(key('home.expected.empty'), findsOneWidget);
    await tester.tap(key('home.expected.members.button'));
    await tester.pumpAndSettle();
    expect(find.text('at /members'), findsOneWidget);
  });

  testWidgets('예상 회원은 5명까지 보이고 "+N명 더"로 그 자리에서 펼친다', (tester) async {
    final many = [for (var i = 0; i < 7; i++) member('x$i', name: '회원$i')];
    await _pump(
      tester,
      members: () async => many,
      lessons: () async => [
        for (var i = 0; i < 7; i++)
          lesson('x$i', DateTime(2026, 11, 10, 8 + i)),
      ],
    );
    for (var i = 0; i < 5; i++) {
      expect(key('home.expected.x$i.row'), findsOneWidget);
    }
    expect(key('home.expected.x5.row'), findsNothing);
    await reveal(tester, key('home.expected.more.button'));
    expect(find.text('+2명 더'), findsOneWidget);
    // 회원 목록으로 보내지 않고 이 자리에서 펼치고 접는다.
    await tester.tap(key('home.expected.more.button'));
    await tester.pumpAndSettle();
    expect(key('home.expected.x5.row'), findsOneWidget);
    expect(key('home.expected.x6.row'), findsOneWidget);
    expect(find.text('접기'), findsOneWidget);
    expect(find.textContaining('at /'), findsNothing);
    await tester.tap(key('home.expected.more.button'));
    await tester.pumpAndSettle();
    expect(key('home.expected.x5.row'), findsNothing);
    expect(find.text('+2명 더'), findsOneWidget);
  });

  testWidgets('방금 레슨한 회원은 요약·전후 썸네일 4개·레슨 보기·변화 비교를 보인다', (tester) async {
    final router = await _pump(tester);
    await reveal(tester, key('home.recent.open.button'));
    expect(key('home.recent.section'), findsOneWidget);
    expect(find.text('사진 5장 · 동영상 1개 · 일지'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is KeyedSubtree &&
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('home.recent.photo.'),
      ),
      findsNWidgets(4),
    );
    expect(key('home.recent.compare.button'), findsOneWidget);
    await tester.tap(key('home.recent.open.button'));
    await tester.pumpAndSettle();
    expect(find.text('at /lessons/latest'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(key('home.recent.compare.button'));
    await tester.pumpAndSettle();
    expect(find.text('at /members/m1/compare'), findsOneWidget);
  });

  testWidgets('사진 기록이 2개 미만이면 변화 비교를 숨기고 일지만이면 썸네일도 없다', (tester) async {
    await _pump(
      tester,
      lessons: () async => [
        lesson('m1', DateTime(2026, 11, 16, 18), memo: '메모'),
      ],
    );
    await reveal(tester, key('home.recent.open.button'));
    expect(find.text('일지'), findsOneWidget);
    expect(key('home.recent.compare.button'), findsNothing);
  });

  testWidgets('이번 주 숫자 3칸은 기록 탭으로 간다', (tester) async {
    await _pump(tester);
    await reveal(tester, key('home.week.members.button'));
    expect(
      find.textContaining(keepPhrasesWhole('11.16 월 – 11.22 일')),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(key('home.week.lessons.button')).label,
      contains('이번 주 레슨 1'),
    );
    expect(
      tester.getSemantics(key('home.week.photos.button')).label,
      contains('이번 주 사진 기록 2'),
    );
    expect(
      tester.getSemantics(key('home.week.members.button')).label,
      contains('이번 주 회원 1'),
    );
    await tester.tap(key('home.week.photos.button'));
    await tester.pumpAndSettle();
    expect(find.text('at /records'), findsOneWidget);
  });

  testWidgets('한동안 기록이 없는 회원은 경과일 pill과 함께 보이고 없으면 섹션을 숨긴다', (tester) async {
    await _pump(tester);
    await reveal(tester, key('home.idle.m3.row'));
    expect(find.text('47일 경과'), findsOneWidget);
    await tester.tap(key('home.idle.m3.row'));
    await tester.pumpAndSettle();
    expect(find.text('at /members/m3'), findsOneWidget);

    await _pump(
      tester,
      members: () async => [member('m1')],
      lessons: () async => [lesson('m1', DateTime(2026, 11, 16))],
    );
    expect(key('home.idle.section'), findsNothing);
  });

  testWidgets('등록 14일 이상 지난 레슨 없는 회원만 "아직 레슨 없음"으로 보인다', (tester) async {
    await _pump(
      tester,
      members: () async => [
        member('m9', name: '오래된회원', createdAt: DateTime(2026, 10, 1)),
        // 방금 등록한 회원은 idle로 보지 않는다.
        member('m10', name: '새회원', createdAt: DateTime(2026, 11, 15)),
      ],
      lessons: () async => const [],
    );
    expect(key('home.recent.section'), findsNothing);
    await reveal(tester, key('home.idle.m9.row'));
    expect(find.text('아직 레슨 없음'), findsOneWidget);
    expect(key('home.idle.m10.row'), findsNothing);
  });

  testWidgets('회원 미연결 기록이 있으면 안내 띠로 기록 탭 미연결 필터를 연다', (tester) async {
    await _pump(tester, unlinked: 2);
    expect(key('home.unlinked.banner'), findsOneWidget);
    await tester.tap(key('home.unlinked.banner'));
    await tester.pumpAndSettle();
    expect(find.text('at /records?member=unlinked'), findsOneWidget);
  });

  testWidgets('미연결 기록이 없으면 안내 띠가 없다', (tester) async {
    await _pump(tester);
    expect(key('home.unlinked.banner'), findsNothing);
  });

  testWidgets('회원이 없으면 첫 회원 등록 빈 상태 하나만 보인다', (tester) async {
    await _pump(
      tester,
      members: () async => const [],
      lessons: () async => const [],
      unlinked: 3,
    );
    expect(key('home.empty'), findsOneWidget);
    for (final id in [
      'home.expected.section',
      'home.recent.section',
      'home.week.section',
      'home.idle.section',
      'home.unlinked.banner',
    ]) {
      expect(key(id), findsNothing, reason: id);
    }
    await tester.tap(key('home.empty.add.button'));
    await tester.pumpAndSettle();
    expect(find.text('at /members/new'), findsOneWidget);
  });

  testWidgets('불러오는 중과 실패를 구분하고 다시 시도한다', (tester) async {
    final gate = Completer<List<Member>>();
    final retryGate = Completer<List<Member>>();
    var calls = 0;
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const HomeScreen())],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          membersProvider.overrideWith((ref) {
            calls++;
            return calls == 1 ? gate.future : retryGate.future;
          }),
          timelineProvider.overrideWith((ref) async => _lessons()),
          unlinkedRecordCountProvider.overrideWith((ref) async => 0),
          appImagePickerProvider.overrideWithValue(FakeVideoPicker()),
          imagePickerRequestStoreProvider.overrideWithValue(
            MemoryRequestStore(),
          ),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pump();
    expect(key('home.loading'), findsOneWidget);

    gate.completeError(StateError('실패'));
    await tester.pumpAndSettle();
    expect(key('home.error'), findsOneWidget);

    // 다시 시도하는 동안에는 실패 안내 대신 진행 표시를 보여 중복 재시도를 막는다.
    await tester.tap(key('home.error.retry.button'));
    await tester.pump();
    expect(key('home.loading'), findsOneWidget);
    expect(key('home.error'), findsNothing);

    retryGate.complete(_members);
    await tester.pumpAndSettle();
    expect(key('home.expected.section'), findsOneWidget);
  });

  testWidgets('320dp·2배 글꼴에서 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, textScale: 2, unlinked: 12);
    expect(tester.takeException(), isNull);
    for (final id in [
      'home.recent.compare.button',
      'home.week.members.button',
      'home.idle.m3.row',
    ]) {
      await reveal(tester, key(id));
      expect(tester.takeException(), isNull, reason: id);
    }
  });

  testWidgets('기록을 연결하고 돌아오면 미연결 안내 띠가 사라진다', (tester) async {
    final records = [
      ..._lessons(),
      lesson(null, DateTime(2026, 9, 1), id: 'u1'),
    ];
    await _pump(tester, lessons: () async => [...records]);
    expect(key('home.unlinked.banner'), findsOneWidget);
    await tester.tap(key('home.unlinked.banner'));
    await tester.pumpAndSettle();

    // 기록 연결 화면이 하는 일: 기록에 회원을 붙이고 타임라인을 새로 읽힌다.
    final linked = records.indexWhere((x) => x.record.id == 'u1');
    records[linked] = lesson('m1', DateTime(2026, 9, 1), id: 'u1');
    final container = ProviderScope.containerOf(
      tester.element(find.text('at /records?member=unlinked')),
    );
    container.invalidate(timelineProvider);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(key('home.unlinked.banner'), findsNothing);
  });

  testWidgets('자정을 넘겨 앱으로 돌아오면 날짜와 요약을 다시 계산한다', (tester) async {
    var clock = DateTime(2026, 11, 17, 23, 50);
    await _pump(
      tester,
      clock: () => clock,
      members: () async => [member('m1', name: '김서연')],
      lessons: () async => [
        lesson('m1', DateTime(2026, 11, 11, 10)), // 수요일
      ],
    );
    expect(find.text('11월 17일 화요일'), findsOneWidget);
    expect(key('home.expected.empty'), findsOneWidget);

    clock = DateTime(2026, 11, 18, 0, 20);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('11월 18일 수요일'), findsOneWidget);
    // 수요일이 되어 지난주 수요일 회원이 예상 회원으로 뜬다.
    expect(key('home.expected.m1.row'), findsOneWidget);
    await reveal(tester, key('home.week.members.button'));
    expect(
      find.textContaining(keepPhrasesWhole('11.16 월 – 11.22 일')),
      findsOneWidget,
    );
  });

  testWidgets('가로 화면·2배 글꼴에서 복구 배너가 떠도 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(640, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(
      tester,
      textScale: 2,
      unlinked: 3,
      picker: FakeVideoPicker(lostVideoPath: '/picker/cache/lost.jpg'),
      store: MemoryRequestStore()
        ..value = ImagePickerRequestContext.galleryImport(),
    );
    expect(key('members.recoveredPhotos.banner'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await reveal(tester, key('home.week.members.button'));
    expect(tester.takeException(), isNull);
  });
}
