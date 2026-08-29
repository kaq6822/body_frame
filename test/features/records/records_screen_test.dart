import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/core/repositories/body_photo_repository.dart';
import 'package:body_frame/core/repositories/photo_record_repository.dart';
import 'package:body_frame/core/router/app_routes.dart';
import 'package:body_frame/features/records/providers/records_providers.dart';
import 'package:body_frame/features/records/records_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// 기록 화면 위젯 테스트.
///
/// 사진 파일은 실제로 만들지 않는다. `Image.file`은 errorBuilder로 떨어지지만
/// 이 테스트가 보는 것은 날짜·경과일·장수·필터·비교 진입점의 구조이므로 영향이 없다.
void main() {
  final base = DateTime(2026, 8, 8);

  BodyPhoto photo(String recordId, BodyDirection direction) => BodyPhoto(
    id: '$recordId-${direction.key}',
    recordId: recordId,
    filePath: '/nonexistent/$recordId-${direction.key}.jpg',
    direction: direction,
    createdAt: base,
  );

  PhotoRecord record(String id, DateTime shotAt, {String? label}) =>
      PhotoRecord(
        id: id,
        shotAt: shotAt,
        label: label,
        createdAt: shotAt,
        updatedAt: shotAt,
      );

  Widget buildApp({
    required List<PhotoRecord> records,
    required List<BodyPhoto> photos,
  }) {
    final router = GoRouter(
      initialLocation: '/records',
      routes: [
        GoRoute(
          path: '/',
          name: AppRoutes.home,
          builder: (context, state) => const Scaffold(
            key: ValueKey('screen.capture.camera.stub'),
            body: Text('camera stub'),
          ),
          routes: [
            GoRoute(
              path: 'records',
              name: AppRoutes.records,
              builder: (context, state) => const RecordsScreen(),
              routes: [
                GoRoute(
                  path: ':${AppParams.recordId}',
                  name: AppRoutes.recordDetail,
                  builder: (context, state) => const Scaffold(
                    key: ValueKey('screen.records.detail.stub'),
                    body: Text('detail stub'),
                  ),
                  routes: [
                    GoRoute(
                      path: 'photos/:${AppParams.photoId}',
                      name: AppRoutes.photoView,
                      builder: (context, state) => const Scaffold(
                        key: ValueKey('screen.records.photo.stub'),
                        body: Text('photo stub'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            GoRoute(
              path: 'import',
              name: AppRoutes.galleryImport,
              builder: (context, state) => const Scaffold(
                key: ValueKey('screen.capture.import.stub'),
                body: Text('import stub'),
              ),
            ),
            GoRoute(
              path: 'compare',
              name: AppRoutes.compareDates,
              builder: (context, state) => const Scaffold(
                key: ValueKey('screen.compare.dates.stub'),
                body: Text('compare dates stub'),
              ),
              routes: [
                GoRoute(
                  path: 'direction',
                  name: AppRoutes.compareDirection,
                  builder: (context, state) => Scaffold(
                    key: const ValueKey('screen.compare.direction.stub'),
                    body: Text(
                      'direction ${state.uri.queryParameters['beforeRecordId']}'
                      ' -> ${state.uri.queryParameters['afterRecordId']}',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        photoRecordRepositoryProvider.overrideWithValue(
          _FakeRecordRepository(records),
        ),
        bodyPhotoRepositoryProvider.overrideWithValue(
          _FakePhotoRepository(photos),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('기록이 없으면 빈 상태와 촬영 화면으로 가는 버튼을 보여준다', (tester) async {
    await tester.pumpWidget(buildApp(records: const [], photos: const []));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('screen.records')), findsOneWidget);
    expect(find.text('아직 기록이 없습니다'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('records.empty.capture.button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('screen.capture.camera.stub')),
      findsOneWidget,
    );
  });

  testWidgets('월 헤더와 경과일 배지, 누락 방향 자리를 함께 보여준다', (tester) async {
    // 기본 테스트 뷰포트(800x600)는 폭이 넓어 카드가 세로로 커지고 세 번째 기록이
    // 화면 밖으로 밀려 빌드되지 않는다. 실기기 비율(1080x2400 @2.75)을 재현한다.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      buildApp(
        records: [
          record('r1', DateTime(2026, 8, 8)),
          record('r2', DateTime(2026, 8, 1)),
          record('r3', DateTime(2026, 7, 20)),
        ],
        photos: [
          photo('r1', BodyDirection.front),
          photo('r1', BodyDirection.leftSide),
          photo('r1', BodyDirection.rightSide),
          photo('r1', BodyDirection.back),
          // r2는 정면만 있어 좌·우·후면 자리가 비어야 한다.
          photo('r2', BodyDirection.front),
          photo('r3', BodyDirection.front),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2026년 8월'), findsOneWidget);
    expect(find.text('2026년 7월'), findsOneWidget);
    expect(find.text('8월 8일 (토)'), findsOneWidget);
    // 8/8과 8/1은 7일, 8/1과 7/20은 12일 간격.
    expect(find.text('+7일'), findsOneWidget);
    expect(find.text('+12일'), findsOneWidget);
    // r2·r3의 빈 방향 자리(각 3칸)가 그려진다.
    expect(
      find.bySemanticsIdentifier('records.strip.leftSide.empty'),
      findsNWidgets(2),
    );
    // 스트립 썸네일도 기본적으로 정렬 격자를 함께 보여준다.
    expect(
      find.byKey(const ValueKey('records.strip.front.grid.overlay')),
      findsWidgets,
    );
  });

  testWidgets('같은 날 촬영이 여러 건이면 회차로 구분하고 0일 배지는 붙이지 않는다', (tester) async {
    await tester.pumpWidget(
      buildApp(
        records: [
          record('r2', DateTime(2026, 8, 8)),
          record('r1', DateTime(2026, 8, 8)),
          record('r0', DateTime(2026, 8, 1)),
        ],
        photos: [
          photo('r2', BodyDirection.front),
          photo('r1', BodyDirection.front),
          photo('r0', BodyDirection.front),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // 같은 날 두 건이므로 회차가 붙고, 8/1 기록은 단독이라 붙지 않는다.
    expect(find.text('2/2번째'), findsOneWidget);
    expect(find.text('1/2번째'), findsOneWidget);
    expect(find.text('8월 8일 (토)'), findsNWidgets(2));
    // 같은 날 기록끼리는 간격이 0이라 알릴 것이 없다.
    expect(find.text('+0일'), findsNothing);
    expect(find.text('+7일'), findsOneWidget);
  });

  testWidgets('대상 라벨이 다른 기록은 경과일 계산에 끼어들지 않는다', (tester) async {
    await tester.pumpWidget(
      buildApp(
        records: [
          record('r1', DateTime(2026, 8, 8)),
          record('r2', DateTime(2026, 8, 4), label: '어머니'),
          record('r3', DateTime(2026, 8, 1)),
        ],
        photos: [
          photo('r1', BodyDirection.front),
          photo('r2', BodyDirection.front),
          photo('r3', BodyDirection.front),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // 본인 기록끼리는 7일. 4일이 나오면 다른 대상이 끼어든 것이다.
    expect(find.text('+7일'), findsOneWidget);
    expect(find.text('+4일'), findsNothing);
    expect(find.text('어머니'), findsOneWidget);
  });

  testWidgets('방향 필터를 고르면 그 방향만 큰 타일로 나열한다', (tester) async {
    await tester.pumpWidget(
      buildApp(
        records: [
          record('r1', DateTime(2026, 8, 8)),
          record('r2', DateTime(2026, 8, 1)),
        ],
        photos: [
          photo('r1', BodyDirection.front),
          photo('r1', BodyDirection.back),
          photo('r2', BodyDirection.front),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // 후면은 r1에만 있으므로 타일이 1개여야 한다.
    await tester.tap(find.byKey(const ValueKey('records.filter.${'back'}')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('records.direction.item.0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('records.direction.item.1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('records.direction.item.0.grid.overlay')),
      findsOneWidget,
    );

    // 전체로 돌아오면 카드 목록이 다시 보인다.
    await tester.tap(find.byKey(const ValueKey('records.filter.all')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('records.item.0')), findsOneWidget);
  });

  testWidgets('고른 방향의 사진이 모두 사라지면 전체 보기로 되돌아온다', (tester) async {
    // 필터 바는 방향이 2종류 이상일 때만 나온다. 후면을 고른 채 마지막 후면
    // 사진을 지우면 바가 사라져 전체로 돌아갈 칩도 함께 없어지므로, 필터를
    // 되돌리지 않으면 "후면 사진이 없습니다"에 갇힌다.
    final photos = [
      photo('r1', BodyDirection.front),
      photo('r1', BodyDirection.back),
      photo('r2', BodyDirection.front),
    ];

    await tester.pumpWidget(
      buildApp(
        records: [
          record('r1', DateTime(2026, 8, 8)),
          record('r2', DateTime(2026, 8, 1)),
        ],
        photos: photos,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('records.filter.${'back'}')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('records.direction.item.0')),
      findsOneWidget,
    );

    // 기록 상세에서 마지막 후면 사진을 지우고 돌아온 상황.
    photos.removeWhere((p) => p.direction == BodyDirection.back);
    ProviderScope.containerOf(
      tester.element(find.byType(RecordsScreen)),
    ).invalidate(timelineProvider);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('records.filter')), findsNothing);
    expect(find.text('후면 사진이 없습니다'), findsNothing);
    expect(find.byKey(const ValueKey('records.item.0')), findsOneWidget);
  });

  testWidgets('사진이 없는 방향은 필터 후보로 나오지 않는다', (tester) async {
    await tester.pumpWidget(
      buildApp(
        records: [record('r1', DateTime(2026, 8, 8))],
        photos: [photo('r1', BodyDirection.front)],
      ),
    );
    await tester.pumpAndSettle();

    // 방향이 한 종류뿐이면 필터 바 자체를 내보이지 않는다.
    expect(find.byKey(const ValueKey('records.filter')), findsNothing);
  });

  testWidgets('카드의 비교 버튼은 직전 기록을 이전으로 지정해 방향 선택으로 보낸다', (tester) async {
    await tester.pumpWidget(
      buildApp(
        records: [
          record('r1', DateTime(2026, 8, 8)),
          record('r2', DateTime(2026, 8, 1)),
        ],
        photos: [
          photo('r1', BodyDirection.front),
          photo('r2', BodyDirection.front),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final compareButton = find.byKey(
      const ValueKey('records.item.0.compare.button'),
    );
    expect(compareButton, findsOneWidget);
    // 가장 오래된 기록에는 비교할 직전 기록이 없다.
    expect(
      find.byKey(const ValueKey('records.item.1.compare.button')),
      findsNothing,
    );

    await tester.tap(compareButton);
    await tester.pumpAndSettle();

    expect(find.text('direction r2 -> r1'), findsOneWidget);
  });

  testWidgets('닫기 버튼은 촬영 화면으로 돌아간다', (tester) async {
    await tester.pumpWidget(
      buildApp(
        records: [record('r1', DateTime(2026, 8, 8))],
        photos: [photo('r1', BodyDirection.front)],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('records.close.button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('screen.capture.camera.stub')),
      findsOneWidget,
    );
  });
}

class _FakeRecordRepository implements PhotoRecordRepository {
  final List<PhotoRecord> _records;

  _FakeRecordRepository(this._records);

  @override
  Future<void> delete(String id) async {}

  @override
  Future<PhotoRecord?> getById(String id) async =>
      _records.where((r) => r.id == id).firstOrNull;

  @override
  Future<void> insert(PhotoRecord record) async {}

  /// 실제 리포지토리와 같이 촬영일 최신순으로 준다.
  @override
  Future<List<PhotoRecord>> listAll() async {
    final sorted = [..._records]..sort((a, b) => b.shotAt.compareTo(a.shotAt));
    return sorted;
  }

  @override
  Future<void> update(PhotoRecord record) async {}
}

class _FakePhotoRepository implements BodyPhotoRepository {
  final List<BodyPhoto> _photos;

  _FakePhotoRepository(this._photos);

  @override
  Future<void> delete(String id) async {}

  @override
  Future<BodyPhoto?> getById(String id) async =>
      _photos.where((p) => p.id == id).firstOrNull;

  @override
  Future<void> insert(BodyPhoto photo) async {}

  @override
  Future<List<BodyPhoto>> listAll() async => _photos;

  @override
  Future<List<BodyPhoto>> listByDirection(BodyDirection direction) async =>
      _photos.where((p) => p.direction == direction).toList();

  @override
  Future<List<BodyPhoto>> listByRecord(String recordId) async =>
      _photos.where((p) => p.recordId == recordId).toList();

  @override
  Future<void> update(BodyPhoto photo) async {}
}
