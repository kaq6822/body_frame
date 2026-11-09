import 'package:bodymark/core/models/models.dart';
import 'package:bodymark/core/theme/app_theme.dart';
import 'package:bodymark/features/members/lesson_records_screen.dart';
import 'package:bodymark/features/members/member.dart';
import 'package:bodymark/features/members/member_providers.dart';
import 'package:bodymark/features/members/member_screens.dart';
import 'package:bodymark/features/members/ui.dart';
import 'package:bodymark/features/records/providers/records_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _at = DateTime(2026, 11, 4, 15);

Member _member({String reason = '', String goal = ''}) => Member(
  id: 'm1',
  name: '김서연',
  reason: reason,
  goal: goal,
  createdAt: _at,
  updatedAt: _at,
);

RecordWithPhotos _item(int photos) => RecordWithPhotos(
  record: PhotoRecord(
    id: 'r1',
    memberId: 'm1',
    shotAt: _at,
    createdAt: _at,
    updatedAt: _at,
  ),
  photos: [
    for (var i = 0; i < photos; i++)
      BodyPhoto(
        id: 'p$i',
        recordId: 'r1',
        filePath: 'photos/202611/p$i.jpg',
        direction: BodyDirection.values[i % BodyDirection.values.length],
        phase: 'before',
        createdAt: _at,
      ),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  Widget home,
  Member member,
  int photos,
) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        membersProvider.overrideWith((ref) async => [member]),
        timelineProvider.overrideWith((ref) async => [_item(photos)]),
      ],
      child: MaterialApp(theme: AppTheme.light, home: home),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('lessonDate는 요일을 포함한다', () {
    expect(lessonDate(_at), '2026.11.04 (수) 오후 3:00');
  });

  testWidgets('회원 상세에서 사진 4장이 같은 너비로 모두 보인다', (tester) async {
    await _pump(tester, const MemberDetailScreen(memberId: 'm1'), _member(), 4);
    final tiles = find.descendant(
      of: find.byKey(const ValueKey('lessons.thumbnails.row')),
      matching: find.byType(AspectRatio),
    );
    expect(tiles, findsNWidgets(4));
    final rects = [for (var i = 0; i < 4; i++) tester.getRect(tiles.at(i))];
    for (final r in rects) {
      expect(r.width, closeTo(rects.first.width, 0.01));
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(360));
    }
    expect(find.text('+1'), findsNothing);
  });

  testWidgets('사진이 4장을 넘으면 +N을 보여 준다', (tester) async {
    await _pump(tester, const MemberDetailScreen(memberId: 'm1'), _member(), 6);
    expect(find.text('+2'), findsOneWidget);
  });

  testWidgets('운동 배경이 비면 한 줄 안내만 보여 준다', (tester) async {
    await _pump(tester, const MemberDetailScreen(memberId: 'm1'), _member(), 0);
    expect(find.text('운동 배경·목표가 아직 없어요'), findsOneWidget);
    expect(find.textContaining('미입력'), findsNothing);
  });

  testWidgets('값이 있는 항목만 라벨과 값으로 보여 준다', (tester) async {
    await _pump(
      tester,
      const MemberDetailScreen(memberId: 'm1'),
      _member(goal: '체형 교정'),
      0,
    );
    expect(find.text('운동 목표'), findsOneWidget);
    expect(find.text('체형 교정'), findsOneWidget);
    expect(find.text('운동 시작 배경'), findsNothing);
  });

  testWidgets('기록 필터 행은 검색 필드와 왼쪽 선이 같다', (tester) async {
    await _pump(tester, const LessonRecordsScreen(), _member(), 1);
    final search = tester.getTopLeft(
      find.byKey(const ValueKey('lessons.search.field')),
    );
    final member = tester.getTopLeft(
      find.byKey(const ValueKey('lessons.member.filter')),
    );
    expect(member.dx, search.dx);
  });

  testWidgets('회원 필터는 현재 값으로 읽히고 동작 없는 버튼이 따로 잡히지 않는다', (tester) async {
    // 실기기 TalkBack에서 "메뉴 표시"로만 읽히던 문제.
    final semantics = tester.ensureSemantics();
    await _pump(tester, const LessonRecordsScreen(), _member(), 1);
    expect(find.byTooltip('회원 필터: 전체 회원'), findsOneWidget);
    expect(find.byTooltip('메뉴 표시'), findsNothing);
    // 모양만 빌린 안쪽 버튼은 의미 트리에서 빠져 별도 버튼으로 읽히지 않는다.
    expect(find.bySemanticsLabel('전체 회원'), findsNothing);
    semantics.dispose();
  });
}
