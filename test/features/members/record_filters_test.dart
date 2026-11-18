import 'package:bodymark/core/korean_text.dart';
import 'package:bodymark/core/models/models.dart';
import 'package:bodymark/core/theme/app_theme.dart';
import 'package:bodymark/features/members/lesson_records_screen.dart';
import 'package:bodymark/features/members/member.dart';
import 'package:bodymark/features/members/member_providers.dart';
import 'package:bodymark/features/members/widgets/member_filter_sheet.dart';
import 'package:bodymark/features/members/widgets/record_range_calendar.dart';
import 'package:bodymark/features/records/providers/records_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-11-17(화).
final _now = DateTime(2026, 11, 17, 14);

Member _member(String id, String name) =>
    Member(id: id, name: name, createdAt: _now, updatedAt: _now);

RecordWithPhotos _lesson(String id, String? memberId, DateTime at) =>
    RecordWithPhotos(
      record: PhotoRecord(
        id: id,
        memberId: memberId,
        shotAt: at,
        memo: '$id 메모',
        createdAt: at,
        updatedAt: at,
      ),
      photos: const [],
    );

final _members = [
  _member('m3', '박하늘'),
  _member('m2', '이지민'),
  _member('m1', '김서연'),
  _member('m4', '가나다'),
];

final _lessons = [
  _lesson('r1', 'm1', DateTime(2026, 11, 3, 10)),
  _lesson('r2', 'm1', DateTime(2026, 11, 17, 9)),
  _lesson('r3', 'm2', DateTime(2026, 10, 20, 18)),
  _lesson('r4', null, DateTime(2026, 11, 10, 11)),
];

Future<void> _pump(
  WidgetTester tester, {
  List<Member>? members,
  List<RecordWithPhotos>? lessons,
  String? initialMemberFilter,
  Size size = const Size(360, 800),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        membersProvider.overrideWith((ref) async => members ?? _members),
        timelineProvider.overrideWith((ref) async => lessons ?? _lessons),
        clockProvider.overrideWithValue(() => _now),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('ko', 'KR'),
        supportedLocales: const [Locale('ko', 'KR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: LessonRecordsScreen(initialMemberFilter: initialMemberFilter),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _key(String id) => find.byKey(ValueKey(id));

/// 가로로 스크롤되는 프리셋 줄이나 큰 글꼴에서 가려진 칸도 보이게 한 뒤 누른다.
Future<void> _tap(WidgetTester tester, String id) async {
  await tester.ensureVisible(_key(id));
  await tester.pumpAndSettle();
  await tester.tap(_key(id));
  await tester.pumpAndSettle();
}

String _summary(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: _key('lessons.date.sheet.summary'),
        matching: find.byType(Text),
      ),
    )
    .data!;

String _monthLabel(WidgetTester tester) =>
    tester.widget<Text>(_key('lessons.date.month.label')).data!;

Finder _dot(String yyyymmdd) => _key('lessons.date.day.$yyyymmdd.dot');

DateTimeRange _r(DateTime a, DateTime b) => DateTimeRange(start: a, end: b);

void main() {
  group('기간 도우미', () {
    test('달력은 일요일부터 6줄 42칸이다', () {
      // 2026-11-01은 일요일이라 첫 칸이 1일이다.
      final nov = monthGridDays(DateTime(2026, 11));
      expect(nov, hasLength(42));
      expect(nov.first, DateTime(2026, 11, 1));
      expect(nov.last, DateTime(2026, 12, 12));
      // 2026-08-01은 토요일. 31일까지 6줄을 다 쓴다.
      final aug = monthGridDays(DateTime(2026, 8));
      expect(aug.first, DateTime(2026, 7, 26));
      expect(aug[6], DateTime(2026, 8, 1));
      expect(aug[36], DateTime(2026, 8, 31));
      // 2027-02-01은 월요일. 앞 칸은 지난 해 1월 31일이다.
      final feb = monthGridDays(DateTime(2027, 2));
      expect(feb.first, DateTime(2027, 1, 31));
      expect(feb[1], DateTime(2027, 2, 1));
      // 12월 달력은 다음 해 1월로 이어진다.
      expect(monthGridDays(DateTime(2026, 12)).last, DateTime(2027, 1, 9));
    });

    test('날짜별 기록 수는 회원 필터를 따른다', () {
      final lessons = [
        ..._lessons,
        _lesson('r5', 'm1', DateTime(2026, 11, 17, 19)),
      ];
      expect(recordCountsByDay(lessons, null), {
        DateTime(2026, 11, 3): 1,
        DateTime(2026, 11, 17): 2,
        DateTime(2026, 10, 20): 1,
        DateTime(2026, 11, 10): 1,
      });
      expect(recordCountsByDay(lessons, ''), hasLength(4));
      expect(recordCountsByDay(lessons, 'm1'), {
        DateTime(2026, 11, 3): 1,
        DateTime(2026, 11, 17): 2,
      });
      expect(recordCountsByDay(lessons, unlinkedMemberFilter), {
        DateTime(2026, 11, 10): 1,
      });
      expect(recordCountsByDay(lessons, 'nobody'), isEmpty);
    });

    test('프리셋은 now 기준이고 이번 주는 월요일부터 일요일까지다', () {
      expect(
        presetRange(RecordRangePreset.today, _now),
        _r(DateTime(2026, 11, 17), DateTime(2026, 11, 17)),
      );
      expect(
        presetRange(RecordRangePreset.week, _now),
        _r(DateTime(2026, 11, 16), DateTime(2026, 11, 22)),
      );
      // 일요일은 그 주의 마지막 날, 월요일은 첫날이다.
      expect(
        presetRange(RecordRangePreset.week, DateTime(2026, 11, 22, 23)),
        _r(DateTime(2026, 11, 16), DateTime(2026, 11, 22)),
      );
      expect(
        presetRange(RecordRangePreset.week, DateTime(2026, 11, 16)),
        _r(DateTime(2026, 11, 16), DateTime(2026, 11, 22)),
      );
      expect(
        presetRange(RecordRangePreset.month, _now),
        _r(DateTime(2026, 11, 1), DateTime(2026, 11, 30)),
      );
      expect(
        presetRange(RecordRangePreset.lastMonth, _now),
        _r(DateTime(2026, 10, 1), DateTime(2026, 10, 31)),
      );
      expect(
        presetRange(RecordRangePreset.threeMonths, _now),
        _r(DateTime(2026, 8, 17), DateTime(2026, 11, 17)),
      );
    });

    test('프리셋은 해와 달 경계를 넘는다', () {
      final jan = DateTime(2027, 1, 5);
      expect(
        presetRange(RecordRangePreset.lastMonth, jan),
        _r(DateTime(2026, 12, 1), DateTime(2026, 12, 31)),
      );
      expect(
        presetRange(RecordRangePreset.threeMonths, jan),
        _r(DateTime(2026, 10, 5), DateTime(2027, 1, 5)),
      );
      expect(
        presetRange(RecordRangePreset.week, DateTime(2027, 1, 3)),
        _r(DateTime(2026, 12, 28), DateTime(2027, 1, 3)),
      );
      // 석 달 전에 같은 날이 없으면 그달 마지막 날로 맞춘다.
      expect(
        presetRange(RecordRangePreset.threeMonths, DateTime(2026, 5, 31)),
        _r(DateTime(2026, 2, 28), DateTime(2026, 5, 31)),
      );
      expect(
        presetRange(RecordRangePreset.month, DateTime(2028, 2, 10)),
        _r(DateTime(2028, 2, 1), DateTime(2028, 2, 29)),
      );
    });

    test('기간은 시작일 0시부터 끝 날짜 하루 끝까지 포함한다', () {
      final r = _r(DateTime(2026, 11, 3), DateTime(2026, 11, 17));
      expect(inDayRange(DateTime(2026, 11, 3), r), isTrue);
      expect(inDayRange(DateTime(2026, 11, 17, 23, 59, 59), r), isTrue);
      expect(inDayRange(DateTime(2026, 11, 18), r), isFalse);
      expect(inDayRange(DateTime(2026, 11, 2, 23, 59), r), isFalse);
      expect(countInRange(recordCountsByDay(_lessons, null), r), 3);
    });

    test('기간 라벨은 하루면 날짜 하나, 해가 다르면 연도를 붙인다', () {
      expect(
        recordRangeLabel(
          _r(DateTime(2026, 11, 3), DateTime(2026, 11, 17)),
          _now,
        ),
        '11.03 ~ 11.17',
      );
      expect(
        recordRangeLabel(
          _r(DateTime(2026, 11, 3), DateTime(2026, 11, 3)),
          _now,
        ),
        '11.03',
      );
      expect(
        recordRangeLabel(
          _r(DateTime(2025, 12, 30), DateTime(2026, 1, 2)),
          _now,
        ),
        '2025.12.30 ~ 01.02',
      );
    });

    test('회원 선택 순서는 최근 레슨순, 기록 없는 회원은 이름순으로 뒤에 둔다', () {
      final entries = memberFilterEntries(_members, _lessons);
      expect(
        [for (final e in entries) e.member.name],
        ['김서연', '이지민', '가나다', '박하늘'],
      );
      expect(entries.first.count, 2);
      expect(entries.first.latest, DateTime(2026, 11, 17, 9));
      expect(entries.last.latest, isNull);
    });
  });

  group('회원 선택 시트', () {
    testWidgets('최근 레슨순으로 보이고 미연결 기록이 있으면 미연결 줄을 보인다', (tester) async {
      await _pump(tester);
      await _tap(tester, 'lessons.member.filter');
      expect(_key('lessons.member.sheet'), findsOneWidget);
      expect(find.text('회원 선택'), findsOneWidget);
      final ids = [
        'lessons.member.option.all',
        'lessons.member.option.unlinked',
        'lessons.member.option.m1',
        'lessons.member.option.m2',
        'lessons.member.option.m4',
        'lessons.member.option.m3',
      ];
      final tops = [for (final id in ids) tester.getTopLeft(_key(id)).dy];
      for (var i = 1; i < tops.length; i++) {
        expect(tops[i], greaterThan(tops[i - 1]), reason: ids[i]);
      }
      final sheet = _key('lessons.member.sheet');
      Finder inSheet(String text) =>
          find.descendant(of: sheet, matching: find.text(text));
      expect(inSheet('기록 4개'), findsOneWidget);
      expect(inSheet('기록 1개'), findsOneWidget);
      expect(inSheet('기록 2개 · 최근 11.17'), findsOneWidget);
      expect(inSheet('기록 1개 · 최근 10.20'), findsOneWidget);
      expect(inSheet('기록 없음'), findsNWidgets(2));
      // 현재 값(전체 회원)에만 체크 표시가 있다.
      expect(
        find.descendant(
          of: _key('lessons.member.option.all'),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
    });

    testWidgets('미연결 기록이 없으면 미연결 줄을 숨긴다', (tester) async {
      await _pump(tester, lessons: _lessons.take(3).toList());
      await _tap(tester, 'lessons.member.filter');
      expect(_key('lessons.member.option.all'), findsOneWidget);
      expect(_key('lessons.member.option.unlinked'), findsNothing);
    });

    testWidgets('이름으로 찾고 결과가 없으면 안내한다', (tester) async {
      await _pump(tester);
      await _tap(tester, 'lessons.member.filter');
      await tester.enterText(_key('lessons.member.sheet.search'), '지민');
      await tester.pumpAndSettle();
      expect(_key('lessons.member.option.m2'), findsOneWidget);
      expect(_key('lessons.member.option.m1'), findsNothing);
      expect(_key('lessons.member.option.all'), findsNothing);

      await tester.enterText(_key('lessons.member.sheet.search'), 'ZZ');
      await tester.pumpAndSettle();
      expect(_key('lessons.member.option.m2'), findsNothing);
      expect(find.text(keepPhrasesWhole("'ZZ'와 일치하는 회원이 없어요")), findsOneWidget);
    });

    testWidgets('영문 이름은 대소문자 없이 찾는다', (tester) async {
      await _pump(tester, members: [_member('m9', 'Lee Test'), ..._members]);
      await _tap(tester, 'lessons.member.filter');
      await tester.enterText(_key('lessons.member.sheet.search'), 'lee');
      await tester.pumpAndSettle();
      expect(_key('lessons.member.option.m9'), findsOneWidget);
      expect(_key('lessons.member.option.m1'), findsNothing);
    });

    testWidgets('고르면 바로 적용하고 닫히며, 칩의 해제 버튼은 전체 회원으로 돌린다', (tester) async {
      await _pump(tester);
      expect(_key('lessons.member.clear.button'), findsNothing);
      await _tap(tester, 'lessons.member.filter');
      await _tap(tester, 'lessons.member.option.m1');
      expect(_key('lessons.member.sheet'), findsNothing);
      expect(find.byTooltip('회원 필터: 김서연'), findsOneWidget);
      expect(find.text('총 2개의 레슨 기록'), findsOneWidget);

      // 다시 열면 고른 회원에 체크가 있다.
      await _tap(tester, 'lessons.member.filter');
      expect(
        find.descendant(
          of: _key('lessons.member.option.m1'),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      await _tap(tester, 'lessons.member.option.unlinked');
      expect(find.byTooltip('회원 필터: 회원 미연결'), findsOneWidget);
      expect(find.text('총 1개의 레슨 기록'), findsOneWidget);

      await _tap(tester, 'lessons.member.clear.button');
      expect(_key('lessons.member.sheet'), findsNothing);
      expect(find.byTooltip('회원 필터: 전체 회원'), findsOneWidget);
      expect(find.text('총 4개의 레슨 기록'), findsOneWidget);
      expect(_key('lessons.member.clear.button'), findsNothing);
    });

    testWidgets('미연결 필터로 열면 칩에 해제 버튼이 있다', (tester) async {
      await _pump(tester, initialMemberFilter: unlinkedMemberFilter);
      expect(find.byTooltip('회원 필터: 회원 미연결'), findsOneWidget);
      expect(_key('lessons.member.clear.button'), findsOneWidget);
      final clear = tester.getSize(_key('lessons.member.clear.button'));
      expect(clear.width, greaterThanOrEqualTo(48));
      expect(clear.height, greaterThanOrEqualTo(48));
    });
  });

  group('기간 시트', () {
    testWidgets('기록이 있는 날에만 점이 있고 회원 필터를 따른다', (tester) async {
      await _pump(tester);
      await _tap(tester, 'lessons.date.filter');
      expect(_key('lessons.date.sheet'), findsOneWidget);
      expect(_monthLabel(tester), '2026년 11월');
      expect(_dot('20261103'), findsOneWidget);
      expect(_dot('20261110'), findsOneWidget);
      expect(_dot('20261117'), findsOneWidget);
      expect(_dot('20261104'), findsNothing);
      expect(
        tester.getSemantics(_key('lessons.date.day.20261117')).label,
        '11월 17일, 기록 1개, 오늘',
      );
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await _tap(tester, 'lessons.member.filter');
      await _tap(tester, 'lessons.member.option.m1');
      await _tap(tester, 'lessons.date.filter');
      expect(_dot('20261103'), findsOneWidget);
      expect(_dot('20261117'), findsOneWidget);
      // 미연결 기록 날은 김서연 필터에서 점이 없다.
      expect(_dot('20261110'), findsNothing);
      expect(
        tester.getSemantics(_key('lessons.date.day.20261110')).label,
        '11월 10일, 기록 없음',
      );
    });

    testWidgets('처음 달은 고른 회원의 최근 기록 달이다', (tester) async {
      await _pump(tester);
      await _tap(tester, 'lessons.member.filter');
      await _tap(tester, 'lessons.member.option.m2');
      await _tap(tester, 'lessons.date.filter');
      expect(_monthLabel(tester), '2026년 10월');
      expect(_dot('20261020'), findsOneWidget);
    });

    testWidgets('기록이 없으면 처음 달은 오늘이 든 달이다', (tester) async {
      await _pump(tester, lessons: const []);
      await _tap(tester, 'lessons.date.filter');
      expect(_monthLabel(tester), '2026년 11월');
    });

    testWidgets('시작·끝을 차례로 고르고 적용하면 목록과 칩이 바뀐다', (tester) async {
      await _pump(tester);
      await _tap(tester, 'lessons.date.filter');
      FilledButton apply() => tester.widget<FilledButton>(
        find.descendant(
          of: _key('lessons.date.sheet.apply'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(apply().onPressed, isNull);
      expect(_summary(tester), keepPhrasesWhole('시작일을 골라주세요'));

      await _tap(tester, 'lessons.date.day.20261110');
      expect(_summary(tester), '11.10 · 기록 1개');
      expect(apply().onPressed, isNotNull);
      // 시작보다 앞을 누르면 새 시작일이 된다.
      await _tap(tester, 'lessons.date.day.20261103');
      expect(_summary(tester), '11.03 · 기록 1개');
      await _tap(tester, 'lessons.date.day.20261117');
      expect(_summary(tester), '11.03 ~ 11.17 · 기록 3개');
      expect(
        tester.getSemantics(_key('lessons.date.day.20261110')).label,
        '11월 10일, 기록 1개, 선택 기간',
      );
      // 세 번째 누르면 처음부터 다시 고른다.
      await _tap(tester, 'lessons.date.day.20261104');
      expect(_summary(tester), '11.04 · 기록 0개');
      await _tap(tester, 'lessons.date.day.20261117');
      expect(_summary(tester), '11.04 ~ 11.17 · 기록 2개');
      expect(find.text('기록 2개 보기'), findsOneWidget);

      await _tap(tester, 'lessons.date.sheet.apply');
      expect(_key('lessons.date.sheet'), findsNothing);
      expect(find.text('총 2개의 레슨 기록'), findsOneWidget);
      expect(find.text('11.04 ~ 11.17'), findsOneWidget);
      expect(find.byTooltip('기간 필터: 11.04 ~ 11.17'), findsOneWidget);
      expect(find.text('r3 메모'), findsNothing);
    });

    testWidgets('선택 기간 안의 날에는 보이는 띠가 깔린다', (tester) async {
      await _pump(tester);
      await _tap(tester, 'lessons.date.filter');
      await _tap(tester, 'lessons.date.day.20261103');
      await _tap(tester, 'lessons.date.day.20261117');
      Iterable<Size> bands(String id) => tester
          .widgetList<ColoredBox>(
            find.descendant(of: _key(id), matching: find.byType(ColoredBox)),
          )
          .where((b) => b.color != Colors.transparent)
          .map((b) => tester.getSize(find.byWidget(b)));
      // 기간 안의 날은 양쪽 반칸 모두 띠가 있고, 높이가 0이면 안 보인다.
      final inside = bands('lessons.date.day.20261110').toList();
      expect(inside, hasLength(2));
      expect(inside.every((s) => s.height > 0 && s.width > 0), isTrue);
      // 기간 밖의 날에는 띠가 없다.
      expect(bands('lessons.date.day.20261120'), isEmpty);
    });

    testWidgets('시작일만 고르고 적용하면 그날 하루만 본다', (tester) async {
      await _pump(tester);
      await _tap(tester, 'lessons.date.filter');
      await _tap(tester, 'lessons.date.day.20261117');
      await _tap(tester, 'lessons.date.sheet.apply');
      expect(find.text('총 1개의 레슨 기록'), findsOneWidget);
      expect(find.text('r2 메모'), findsOneWidget);
    });

    testWidgets('프리셋은 기간과 달을 옮기고 다시 열면 그 기간 달에서 시작한다', (tester) async {
      await _pump(tester);
      await _tap(tester, 'lessons.date.filter');
      await _tap(tester, 'lessons.date.preset.lastMonth');
      expect(_monthLabel(tester), '2026년 10월');
      expect(_summary(tester), '10.01 ~ 10.31 · 기록 1개');
      await _tap(tester, 'lessons.date.preset.week');
      expect(_monthLabel(tester), '2026년 11월');
      expect(_summary(tester), '11.16 ~ 11.22 · 기록 1개');
      await _tap(tester, 'lessons.date.preset.lastMonth');
      await _tap(tester, 'lessons.date.sheet.apply');
      expect(find.text('총 1개의 레슨 기록'), findsOneWidget);
      expect(find.text('r3 메모'), findsOneWidget);

      await _tap(tester, 'lessons.date.filter');
      expect(_monthLabel(tester), '2026년 10월');
      expect(_summary(tester), '10.01 ~ 10.31 · 기록 1개');
    });

    testWidgets('화살표와 좌우 밀기로 달을 옮기고 해를 넘긴다', (tester) async {
      await _pump(tester);
      await _tap(tester, 'lessons.date.filter');
      await _tap(tester, 'lessons.date.month.next');
      expect(_monthLabel(tester), '2026년 12월');
      await _tap(tester, 'lessons.date.month.next');
      expect(_monthLabel(tester), '2027년 1월');
      await _tap(tester, 'lessons.date.month.prev');
      expect(_monthLabel(tester), '2026년 12월');
      await tester.fling(_key('lessons.date.grid'), const Offset(200, 0), 1000);
      await tester.pumpAndSettle();
      expect(_monthLabel(tester), '2026년 11월');
      await tester.fling(
        _key('lessons.date.grid'),
        const Offset(-200, 0),
        1000,
      );
      await tester.pumpAndSettle();
      expect(_monthLabel(tester), '2026년 12월');
      // 다른 달 날짜는 칸에 그리지 않는다.
      expect(_key('lessons.date.day.20261130'), findsNothing);
    });

    testWidgets('초기화와 칩의 해제 버튼은 전체 기간으로 돌린다', (tester) async {
      await _pump(tester);
      expect(_key('lessons.date.reset.button'), findsNothing);
      await _tap(tester, 'lessons.date.filter');
      await _tap(tester, 'lessons.date.preset.today');
      await _tap(tester, 'lessons.date.sheet.apply');
      expect(find.text('총 1개의 레슨 기록'), findsOneWidget);
      expect(find.text('11.17'), findsOneWidget);

      await _tap(tester, 'lessons.date.filter');
      await _tap(tester, 'lessons.date.sheet.clear');
      expect(_key('lessons.date.sheet'), findsNothing);
      expect(find.text('전체 기간'), findsOneWidget);
      expect(find.text('총 4개의 레슨 기록'), findsOneWidget);

      await _tap(tester, 'lessons.date.filter');
      await _tap(tester, 'lessons.date.preset.month');
      await _tap(tester, 'lessons.date.sheet.apply');
      expect(find.text('총 3개의 레슨 기록'), findsOneWidget);
      await _tap(tester, 'lessons.date.reset.button');
      expect(_key('lessons.date.sheet'), findsNothing);
      expect(find.text('총 4개의 레슨 기록'), findsOneWidget);
      expect(_key('lessons.date.reset.button'), findsNothing);
    });

    testWidgets('그냥 닫으면 기간이 바뀌지 않는다', (tester) async {
      await _pump(tester);
      await _tap(tester, 'lessons.date.filter');
      await _tap(tester, 'lessons.date.day.20261117');
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(_key('lessons.date.sheet'), findsNothing);
      expect(find.text('전체 기간'), findsOneWidget);
      expect(find.text('총 4개의 레슨 기록'), findsOneWidget);
    });
  });

  group('320dp·2배 글꼴', () {
    const size = Size(320, 640);

    testWidgets('필터를 건 기록 화면이 넘치지 않는다', (tester) async {
      await _pump(
        tester,
        members: [
          _member('m1', '김서연 아주 긴 이름의 회원님'),
          ..._members.where((m) => m.id != 'm1'),
        ],
        size: size,
        textScale: 2,
      );
      await _tap(tester, 'lessons.member.filter');
      await _tap(tester, 'lessons.member.option.m1');
      await _tap(tester, 'lessons.date.filter');
      await _tap(tester, 'lessons.date.preset.3months');
      await _tap(tester, 'lessons.date.sheet.apply');
      expect(tester.takeException(), isNull);
      expect(_key('lessons.member.clear.button'), findsOneWidget);
      expect(_key('lessons.date.reset.button'), findsOneWidget);
      for (final id in [
        'lessons.member.filter',
        'lessons.member.clear.button',
        'lessons.date.filter',
        'lessons.date.reset.button',
      ]) {
        final rect = tester.getRect(_key(id));
        expect(rect.left, greaterThanOrEqualTo(0), reason: id);
        expect(rect.right, lessThanOrEqualTo(320), reason: id);
      }
    });

    testWidgets('회원 선택 시트가 넘치지 않는다', (tester) async {
      await _pump(tester, size: size, textScale: 2);
      await _tap(tester, 'lessons.member.filter');
      expect(tester.takeException(), isNull);
      await tester.enterText(_key('lessons.member.sheet.search'), '없는회원이름');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('기간 시트가 넘치지 않는다', (tester) async {
      await _pump(tester, size: size, textScale: 2);
      await _tap(tester, 'lessons.date.filter');
      expect(tester.takeException(), isNull);
      await _tap(tester, 'lessons.date.day.20261103');
      await _tap(tester, 'lessons.date.day.20261117');
      expect(tester.takeException(), isNull);
      expect(find.text('기록 3개 보기'), findsOneWidget);
      final apply = tester.getRect(_key('lessons.date.sheet.apply'));
      expect(apply.right, lessThanOrEqualTo(320));
      expect(apply.bottom, lessThanOrEqualTo(640));
    });
  });
}
