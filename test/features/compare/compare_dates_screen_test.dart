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
      memberId: 'm1',
      shotAt: DateTime(2026, 1, 1),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    records.records['r2'] = PhotoRecord(
      id: 'r2',
      memberId: 'm1',
      shotAt: DateTime(2026, 3, 1),
      createdAt: DateTime(2026, 3, 1),
      updatedAt: DateTime(2026, 3, 1),
    );
  });

  Widget buildApp() {
    final router = createCompareTestRouter(initialLocation: '/members/m1/compare');
    return ProviderScope(
      overrides: [
        photoRecordRepositoryProvider.overrideWithValue(records),
        bodyPhotoRepositoryProvider.overrideWithValue(photos),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('촬영 기록이 2개 이상이면 최신순 기본값이 채워지고 다음으로 진행할 수 있다',
      (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey(CompareDatesScreen.screenId)), findsOneWidget);
    // 최근 촬영순 정렬이므로 이후=2026.03.01, 이전=2026.01.01이 기본값.
    expect(find.textContaining('2026.03.01'), findsOneWidget);
    expect(find.textContaining('2026.01.01'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('compare.dates.next.button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey(CompareDirectionScreen.screenId)), findsOneWidget);
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

  testWidgets('촬영 기록이 1개뿐이면 다음으로 진행할 수 없고 안내가 표시된다', (tester) async {
    records.records.remove('r2');
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('비교하려면 촬영 기록이 2개 이상 필요합니다.'), findsOneWidget);
  });
}
