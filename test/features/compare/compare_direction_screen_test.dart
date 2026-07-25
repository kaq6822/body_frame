import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/features/compare/compare_direction_screen.dart';
import 'package:body_frame/features/compare/compare_view_screen.dart';
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

  Widget buildApp(String location) {
    final router = createCompareTestRouter(initialLocation: location);
    return ProviderScope(
      overrides: [
        photoRecordRepositoryProvider.overrideWithValue(records),
        bodyPhotoRepositoryProvider.overrideWithValue(photos),
        memberRepositoryProvider.overrideWithValue(FakeMemberRepository()),
        gridSettingsServiceProvider.overrideWithValue(
          FakeGridSettingsService(),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  const location =
      '/members/m1/compare/direction'
      '?beforeRecordId=r1&afterRecordId=r2';

  testWidgets('공통 방향만 선택 가능하고, 선택 후 다음으로 전후 비교 화면에 진입한다', (tester) async {
    photos.photos['bp1'] = BodyPhoto(
      id: 'bp1',
      recordId: 'r1',
      filePath: '/tmp/bp1.jpg',
      direction: BodyDirection.front,
      createdAt: DateTime(2026, 1, 1),
    );
    photos.photos['bp2'] = BodyPhoto(
      id: 'bp2',
      recordId: 'r1',
      filePath: '/tmp/bp2.jpg',
      direction: BodyDirection.back,
      createdAt: DateTime(2026, 1, 1),
    );
    photos.photos['ap1'] = BodyPhoto(
      id: 'ap1',
      recordId: 'r2',
      filePath: '/tmp/ap1.jpg',
      direction: BodyDirection.front,
      createdAt: DateTime(2026, 3, 1),
    );

    await tester.pumpWidget(buildApp(location));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey(CompareDirectionScreen.screenId)),
      findsOneWidget,
    );
    // front만 양쪽에 있으므로 선택 가능, back은 이후 쪽에 없어 비활성.
    final frontChip = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('compare.direction.selector.front')),
    );
    expect(frontChip.selected, isTrue);
    final backChip = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('compare.direction.selector.back')),
    );
    expect(backChip.onSelected, isNull);

    await tester.tap(
      find.byKey(const ValueKey('compare.direction.next.button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey(CompareViewScreen.screenId)),
      findsOneWidget,
    );
  });

  testWidgets('공통 방향이 없으면 안내 문구를 보여준다', (tester) async {
    photos.photos['bp1'] = BodyPhoto(
      id: 'bp1',
      recordId: 'r1',
      filePath: '/tmp/bp1.jpg',
      direction: BodyDirection.front,
      createdAt: DateTime(2026, 1, 1),
    );
    photos.photos['ap1'] = BodyPhoto(
      id: 'ap1',
      recordId: 'r2',
      filePath: '/tmp/ap1.jpg',
      direction: BodyDirection.back,
      createdAt: DateTime(2026, 3, 1),
    );

    await tester.pumpWidget(buildApp(location));
    await tester.pumpAndSettle();

    expect(find.textContaining('공통으로 존재하는 촬영 방향이 없습니다'), findsOneWidget);
  });

  testWidgets('필요한 쿼리 파라미터 없이 진입하면 안내와 복귀 버튼을 보여준다', (tester) async {
    await tester.pumpWidget(buildApp('/members/m1/compare/direction'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('compare.direction.backToDates.button')),
      findsOneWidget,
    );
  });

  testWidgets('같은 촬영 기록이 이전과 이후에 전달되면 진행을 차단한다', (tester) async {
    await tester.pumpWidget(
      buildApp(
        '/members/m1/compare/direction'
        '?beforeRecordId=r1&afterRecordId=r1',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('이전과 이후에는 서로 다른 촬영 기록을 선택해 주세요.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('compare.direction.backToDates.button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('compare.direction.next.button')),
      findsNothing,
    );
  });
}
