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

  void addRecord(String id, DateTime shotAt, {String? label}) {
    records.records[id] = PhotoRecord(
      id: id,
      shotAt: shotAt,
      label: label,
      createdAt: shotAt,
      updatedAt: shotAt,
    );
  }

  void addPhoto(String id, String recordId, {BodyDirection? direction}) {
    photos.photos[id] = BodyPhoto(
      id: id,
      recordId: recordId,
      filePath: '/tmp/$id.jpg',
      direction: direction ?? BodyDirection.front,
      createdAt: DateTime(2026, 1, 1),
    );
  }

  setUp(() {
    records = FakePhotoRecordRepository();
    photos = FakeBodyPhotoRepository();
    addRecord('r1', DateTime(2026, 1, 1));
    addRecord('r2', DateTime(2026, 3, 1));
    // 자동 제안은 사진이 있는 본인 기록끼리만 이뤄진다.
    addPhoto('p1', 'r1');
    addPhoto('p2', 'r2');
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
    expect(find.textContaining('반대쪽에 선택된 기록'), findsOneWidget);
    final selectedTile = tester.widget<ListTile>(
      find.byKey(const ValueKey('compare.before.date.option.r1')),
    );
    expect(selectedTile.selected, isTrue);
    expect(selectedTile.trailing, isNotNull);
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

    expect(find.textContaining('18:40 등록'), findsOneWidget);
    // 촬영일이 겹치지 않는 기록에는 시각을 덧붙이지 않는다.
    final unique = tester.widget<ListTile>(
      find.byKey(const ValueKey('compare.after.date.option.r1')),
    );
    final subtitle = (unique.subtitle! as Text).data!;
    expect(subtitle, isNot(contains('등록')));
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
    photos.photos.remove('p2');
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('비교하려면 촬영 기록이 2개 이상 필요합니다.'), findsOneWidget);
  });

  testWidgets('본인 기록 쌍이 없으면 다른 사람 기록을 자동 선택하지 않고 수동을 안내한다', (tester) async {
    // 가장 최근 두 건이 다른 사람이 찍은 기록이다. 그대로 채우면 본인끼리
    // 비교하는 것이 아니라 조용히 섞인다.
    records.records.clear();
    photos.photos.clear();
    addRecord('r1', DateTime(2026, 1, 1), label: '어머니');
    addRecord('r2', DateTime(2026, 3, 1), label: '동생');
    addPhoto('p1', 'r1');
    addPhoto('p2', 'r2');

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('compare.dates.manual.hint')),
      findsOneWidget,
    );
    final next = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('compare.dates.next.button')),
    );
    expect(next.onPressed, isNull);
    // 목록에서 어느 라벨의 기록인지 알 수 있다.
    await tester.tap(find.byKey(const ValueKey('compare.after.date.button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('어머니'), findsOneWidget);
    expect(find.textContaining('동생'), findsOneWidget);
  });

  testWidgets('수동으로 다른 대상을 고르면 라벨이 다르다는 사실을 알려준다', (tester) async {
    addRecord('r3', DateTime(2026, 5, 1), label: '동생');
    addPhoto('p3', 'r3');

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    // 기본 쌍(r1/r2)은 둘 다 본인 기록이라 안내가 없다.
    expect(
      find.byKey(const ValueKey('compare.dates.label.warning')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('compare.after.date.button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('compare.after.date.option.r3')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('compare.dates.label.warning')),
      findsOneWidget,
    );
    expect(find.text('이전과 이후의 대상 라벨이 다릅니다.'), findsOneWidget);
    // 라벨이 달라도 수동 선택은 유지되고 다음으로 진행할 수 있다.
    expect(
      tester
          .widget<ElevatedButton>(
            find.byKey(const ValueKey('compare.dates.next.button')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('비교 기간은 공용 날짜 계산으로 서머타임 경계에서도 어긋나지 않는다', (tester) async {
    // 지역 자정 차이를 직접 빼면 서머타임이 낀 구간에서 하루가 깎인다.
    records.records.clear();
    photos.photos.clear();
    addRecord('r1', DateTime(2026, 3, 6));
    addRecord('r2', DateTime(2026, 3, 13));
    addPhoto('p1', 'r1');
    addPhoto('p2', 'r2');

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('7일 사이의 변화'), findsOneWidget);
  });
}
