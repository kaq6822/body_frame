import 'package:bodymark/core/models/models.dart';
import 'package:bodymark/core/router/app_routes.dart';
import 'package:bodymark/features/members/member.dart';
import 'package:bodymark/features/members/member_compare_screen.dart';
import 'package:bodymark/features/members/member_providers.dart';
import 'package:bodymark/features/records/providers/records_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

final _at = DateTime(2026, 11, 4, 15);

RecordWithPhotos _item(
  String id,
  DateTime shotAt, {
  List<BodyDirection> directions = const [BodyDirection.front],
}) => RecordWithPhotos(
  record: PhotoRecord(
    id: id,
    memberId: 'm1',
    shotAt: shotAt,
    createdAt: shotAt,
    updatedAt: shotAt,
  ),
  photos: [
    for (final d in directions)
      BodyPhoto(
        id: 'photo-$id-${d.key}',
        recordId: id,
        filePath: 'photos/202611/$id-${d.key}.jpg',
        direction: d,
        phase: 'before',
        createdAt: shotAt,
      ),
  ],
);

void main() {
  Map<String, String>? received;

  Widget app(List<RecordWithPhotos> items) {
    received = null;
    final router = GoRouter(
      initialLocation: '/compare-select',
      routes: [
        GoRoute(
          path: '/compare-select',
          builder: (_, _) => const MemberCompareScreen(memberId: 'm1'),
        ),
        GoRoute(
          path: '/compare/view',
          name: AppRoutes.compareView,
          builder: (_, state) {
            received = state.uri.queryParameters;
            return const SizedBox(key: ValueKey('compare.view.stub'));
          },
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        timelineProvider.overrideWith((ref) async => items),
        membersProvider.overrideWith(
          (ref) async => [
            Member(id: 'm1', name: '김서연', createdAt: _at, updatedAt: _at),
          ],
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> tapCard(WidgetTester tester, String key) async {
    final card = find.byKey(ValueKey('members.compare.$key'));
    // 목록은 지연 생성되므로 아직 만들어지지 않은 카드는 스크롤해 가져온다.
    await tester.scrollUntilVisible(
      card,
      80,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('members.compare.list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(card);
    await tester.pump();
  }

  FilledButton openButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.descendant(
      of: find.byKey(const ValueKey('members.compare.open.button')),
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    ),
  );

  testWidgets('비교하기는 방향과 두 사진을 함께 넘긴다', (tester) async {
    // 실기기에서 방향이 빠져 비교 화면이 재선택 안내만 띄운 문제를 고정한다.
    await tester.pumpWidget(
      app([_item('r1', _at), _item('r2', _at.add(const Duration(days: 7)))]),
    );
    await tester.pumpAndSettle();

    expect(find.text('김서연 회원'), findsOneWidget);
    expect(find.text('선택됨 0/2'), findsOneWidget);
    expect(openButton(tester).onPressed, isNull);
    expect(
      find.byKey(const ValueKey('members.compare.open.reason')),
      findsOneWidget,
    );

    await tapCard(tester, 'r1:before');
    await tapCard(tester, 'r2:before');
    expect(find.text('선택됨 2/2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('members.compare.open.button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('compare.view.stub')), findsOneWidget);
    expect(received, {
      AppParams.direction: BodyDirection.front.key,
      AppParams.beforePhotoId: 'photo-r1-front',
      AppParams.afterPhotoId: 'photo-r2-front',
    });
  });

  testWidgets('늦은 기록을 먼저 골라도 이른 기록이 이전(A)이 된다', (tester) async {
    await tester.pumpWidget(
      app([_item('r2', _at.add(const Duration(days: 7))), _item('r1', _at)]),
    );
    await tester.pumpAndSettle();

    await tapCard(tester, 'r2:before');
    await tapCard(tester, 'r1:before');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('members.compare.r1:before.badge')),
        matching: find.text('A 이전'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('members.compare.r2:before.badge')),
        matching: find.text('B 이후'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('members.compare.open.button')));
    await tester.pumpAndSettle();
    expect(received?[AppParams.beforePhotoId], 'photo-r1-front');
    expect(received?[AppParams.afterPhotoId], 'photo-r2-front');
  });

  testWidgets('두 기록에 함께 있는 방향만 고를 수 있다', (tester) async {
    await tester.pumpWidget(
      app([
        _item(
          'r1',
          _at,
          directions: const [BodyDirection.front, BodyDirection.leftSide],
        ),
        _item(
          'r2',
          _at.add(const Duration(days: 7)),
          directions: const [BodyDirection.leftSide, BodyDirection.back],
        ),
      ]),
    );
    await tester.pumpAndSettle();
    await tapCard(tester, 'r1:before');
    await tapCard(tester, 'r2:before');

    expect(
      find.byKey(const ValueKey('members.compare.direction.leftSide')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('members.compare.direction.front')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('members.compare.open.button')));
    await tester.pumpAndSettle();
    expect(received?[AppParams.direction], BodyDirection.leftSide.key);
  });

  testWidgets('같은 방향이 없으면 어느 기록에 무엇이 있는지 알려주고 다시 고르게 한다', (tester) async {
    await tester.pumpWidget(
      app([
        _item('r1', _at),
        _item(
          'r2',
          _at.add(const Duration(days: 7)),
          directions: const [BodyDirection.back],
        ),
      ]),
    );
    await tester.pumpAndSettle();
    await tapCard(tester, 'r1:before');
    await tapCard(tester, 'r2:before');

    expect(
      find.byKey(const ValueKey('members.compare.noDirection')),
      findsOneWidget,
    );
    expect(find.textContaining('정면'), findsWidgets);
    expect(find.textContaining('후면'), findsWidgets);
    expect(openButton(tester).onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey('members.compare.reset.button')),
    );
    await tester.pump();
    expect(find.text('선택됨 0/2'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('members.compare.noDirection')),
      findsNothing,
    );
  });

  testWidgets('사진 기록이 하나뿐이면 선택 UI 대신 추가 안내를 보여준다', (tester) async {
    await tester.pumpWidget(app([_item('r1', _at)]));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('members.compare.notEnough')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('members.compare.add.button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('members.compare.back.button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('members.compare.r1:before')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('members.compare.open.button')),
      findsNothing,
    );
  });

  for (final size in const [Size(320, 640), Size(640, 360)]) {
    testWidgets(
      '큰 글꼴(2배) ${size.width.toInt()}x${size.height.toInt()}에서도 넘치지 않는다',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          app([
            _item('r1', _at, directions: DirectionStepperOrder.all),
            _item(
              'r2',
              _at.add(const Duration(days: 7)),
              directions: DirectionStepperOrder.all,
            ),
          ]),
        );
        await tester.pumpAndSettle();
        await tapCard(tester, 'r1:before');
        await tapCard(tester, 'r2:before');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}

abstract final class DirectionStepperOrder {
  static const all = [
    BodyDirection.front,
    BodyDirection.leftSide,
    BodyDirection.rightSide,
    BodyDirection.back,
  ];
}
