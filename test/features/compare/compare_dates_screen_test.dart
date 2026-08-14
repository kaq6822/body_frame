import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/features/compare/compare_dates_screen.dart';
import 'package:body_frame/features/compare/compare_direction_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'test_router.dart';

void main() {
  late FakePhotoRecordRepository records;
  late FakeBodyPhotoRepository photos;

  setUp(() {
    records = FakePhotoRecordRepository();
    photos = FakeBodyPhotoRepository();
    records.records['r1'] = PhotoRecord(
      id: 'r1',
      shotAt: DateTime(2026, 1, 1),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    records.records['r2'] = PhotoRecord(
      id: 'r2',
      shotAt: DateTime(2026, 3, 1),
      createdAt: DateTime(2026, 3, 1),
      updatedAt: DateTime(2026, 3, 1),
    );
  });

  Widget buildApp() {
    final router = createCompareTestRouter(initialLocation: '/compare');
    return ProviderScope(
      overrides: [
        photoRecordRepositoryProvider.overrideWithValue(records),
        bodyPhotoRepositoryProvider.overrideWithValue(photos),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('촬영 기록이 2개 이상이면 최신순 기본값이 채워지고 다음으로 진행할 수 있다', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey(CompareDatesScreen.screenId)),
      findsOneWidget,
    );
    // 최근 촬영순 정렬이므로 이후=2026.03.01, 이전=2026.01.01이 기본값.
    expect(find.textContaining('2026.03.01'), findsOneWidget);
    expect(find.textContaining('2026.01.01'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('compare.dates.next.button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey(CompareDirectionScreen.screenId)),
      findsOneWidget,
    );
  });

  testWidgets('이전/이후 교환 버튼을 누르면 날짜가 서로 바뀐다', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('이전: 2026.01.01'), findsOneWidget);
    expect(find.text('이후: 2026.03.01'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('compare.swap.button')));
    await tester.pumpAndSettle();

    expect(find.text('이전: 2026.03.01'), findsOneWidget);
    expect(find.text('이후: 2026.01.01'), findsOneWidget);
  });

  testWidgets('상대편에 선택된 촬영 기록은 날짜 선택 목록에서 비활성화된다', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    // 기본값에서 이후 기록은 r2이므로 이전 기록 목록의 r2는 선택할 수 없다.
    await tester.tap(find.byKey(const ValueKey('compare.before.date.button')));
    await tester.pumpAndSettle();

    final unavailableTile = tester.widget<ListTile>(
      find.byKey(const ValueKey('compare.before.date.option.r2')),
    );
    expect(unavailableTile.enabled, isFalse);
    expect(unavailableTile.onTap, isNull);
  });

  testWidgets('같은 날 기록이 여러 건이면 목록에서 등록 시각으로 구분한다', (tester) async {
    // 촬영 한 건이 기록 하나라 같은 날 여러 건이 생길 수 있다.
    records.records['r3'] = PhotoRecord(
      id: 'r3',
      shotAt: DateTime(2026, 3, 1),
      createdAt: DateTime(2026, 3, 1, 18, 40),
      updatedAt: DateTime(2026, 3, 1, 18, 40),
    );

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('compare.after.date.button')));
    await tester.pumpAndSettle();

    expect(find.text('18:40 등록'), findsOneWidget);
    // 촬영일이 겹치지 않는 기록에는 시각을 덧붙이지 않는다.
    final unique = tester.widget<ListTile>(
      find.byKey(const ValueKey('compare.after.date.option.r1')),
    );
    expect(unique.subtitle, isNull);
  });

  test('촬영일이 겹치는 기록만 골라낸다', () {
    final duplicated = duplicatedDateRecordIds([
      PhotoRecord(
        id: 'a',
        shotAt: DateTime(2026, 3, 1, 9),
        createdAt: DateTime(2026, 3, 1, 9),
        updatedAt: DateTime(2026, 3, 1, 9),
      ),
      PhotoRecord(
        id: 'b',
        shotAt: DateTime(2026, 3, 1, 21),
        createdAt: DateTime(2026, 3, 1, 21),
        updatedAt: DateTime(2026, 3, 1, 21),
      ),
      PhotoRecord(
        id: 'c',
        shotAt: DateTime(2026, 2, 1),
        createdAt: DateTime(2026, 2, 1),
        updatedAt: DateTime(2026, 2, 1),
      ),
    ]);

    expect(duplicated, {'a', 'b'});
  });

  testWidgets('촬영 기록이 1개뿐이면 다음으로 진행할 수 없고 안내가 표시된다', (tester) async {
    records.records.remove('r2');
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('비교하려면 촬영 기록이 2개 이상 필요합니다.'), findsOneWidget);
  });
}
