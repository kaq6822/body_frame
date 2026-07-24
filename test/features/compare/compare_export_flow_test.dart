import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/features/compare/compare_export_screen.dart';
import 'package:body_frame/features/compare/services/compare_export_sink.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'test_router.dart';

void main() {
  late FakeMemberRepository members;
  late FakePhotoRecordRepository records;
  late FakeBodyPhotoRepository photos;
  late FakeGridSettingsService grid;
  late FakeCompareExportSink sink;

  setUp(() {
    members = FakeMemberRepository();
    members.members['m1'] = Member(
      id: 'm1',
      name: '홍길동',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    records = FakePhotoRecordRepository();
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

    // ComparePhotoPane은 Image.file의 errorBuilder로 디코딩 실패를 흡수하므로
    // 존재하지 않는 경로를 써서 실제 이미지 디코딩 없이 화면 로직만 검증한다.
    photos = FakeBodyPhotoRepository();
    photos.photos['bp1'] = BodyPhoto(
      id: 'bp1',
      recordId: 'r1',
      filePath: '/nonexistent/before.jpg',
      direction: BodyDirection.front,
      createdAt: DateTime(2026, 1, 1),
    );
    photos.photos['ap1'] = BodyPhoto(
      id: 'ap1',
      recordId: 'r2',
      filePath: '/nonexistent/after.jpg',
      direction: BodyDirection.front,
      createdAt: DateTime(2026, 3, 1),
    );

    grid = FakeGridSettingsService();
    sink = FakeCompareExportSink();
  });

  Widget buildApp() {
    final router = createCompareTestRouter(
      initialLocation: '/members/m1/compare/view'
          '?direction=front&beforePhotoId=bp1&afterPhotoId=ap1',
    );
    return ProviderScope(
      overrides: [
        memberRepositoryProvider.overrideWithValue(members),
        photoRecordRepositoryProvider.overrideWithValue(records),
        bodyPhotoRepositoryProvider.overrideWithValue(photos),
        gridSettingsServiceProvider.overrideWithValue(grid),
        compareExportSinkProvider.overrideWithValue(sink),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets(
      '비교 화면에서 이미지 생성으로 진입해 옵션을 조정하고 생성·저장·공유까지 진행한다',
      (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    // 전후 비교 화면 -> 이미지 생성 화면.
    await tester.tap(find.byKey(const ValueKey('compare.export.button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey(CompareExportScreen.screenId)), findsOneWidget);
    // 개인정보 보호를 위해 회원 이름은 기본적으로 숨긴다.
    expect(find.textContaining('홍길동'), findsNothing);

    // 회원 이름 포함 토글 -> 미리보기에 반영된다.
    // SingleChildScrollView 콘텐츠가 테스트 뷰포트보다 길므로 탭 전에
    // 스크롤해 화면 안으로 가져온다.
    final nameToggle = find.byKey(const ValueKey('compare.export.name.toggle'));
    await tester.ensureVisible(nameToggle);
    await tester.pumpAndSettle();
    await tester.tap(nameToggle);
    await tester.pumpAndSettle();
    expect(find.textContaining('홍길동'), findsOneWidget);

    // 생성 전 상태 확인.
    expect(find.text('이미지를 생성해 주세요.'), findsOneWidget);

    final generateButton =
        find.byKey(const ValueKey('compare.export.generate.button'));
    await tester.ensureVisible(generateButton);
    await tester.pumpAndSettle();
    // RenderRepaintBoundary.toImage()의 Future는 flutter_test의 FakeAsync
    // 프레임 펌프 안에서는 완료 콜백을 받지 못한다. runAsync로 실제 이벤트
    // 루프에서 tap+대기를 수행한 뒤, 바깥에서 pump로 결과 setState를
    // 반영해야 성공 상태까지 진행된다.
    await tester.runAsync(() async {
      await tester.tap(generateButton);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(find.text('이미지 생성이 완료되었습니다.'), findsOneWidget);
    expect(find.byKey(const ValueKey('compare.export.result.thumbnail')), findsOneWidget);

    final saveButton = find.byKey(const ValueKey('compare.export.save.button'));
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(sink.savedNames, hasLength(1));
    expect(sink.savedNames.first, contains('front'));
    // 저장 성공 SnackBar가 화면 하단 버튼 영역을 겹쳐 히트 테스트를 가로채므로
    // 기본 표시 시간(4초)이 지나 사라질 때까지 기다린다.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    final shareButton = find.byKey(const ValueKey('compare.export.share.button'));
    await tester.ensureVisible(shareButton);
    await tester.pumpAndSettle();
    await tester.tap(shareButton);
    await tester.pumpAndSettle();
    expect(sink.sharedNames, hasLength(1));
  });

  testWidgets('저장이 실패하면 실패 안내를 보여주고 상태는 유지된다', (tester) async {
    sink.failSave = true;
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('compare.export.button')));
    await tester.pumpAndSettle();

    final generateButton =
        find.byKey(const ValueKey('compare.export.generate.button'));
    await tester.ensureVisible(generateButton);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(generateButton);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const ValueKey('compare.export.save.button'));
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('저장에 실패했습니다. 다시 시도해 주세요.'), findsOneWidget);
    expect(sink.savedNames, isEmpty);
  });

  testWidgets('필요한 컨텍스트 없이 진입하면 안내 화면을 보여준다', (tester) async {
    // 쿼리 파라미터조차 없으면 복구가 불가능하므로 안내 화면을 보여준다.
    final router = createCompareTestRouter(
      initialLocation: '/members/m1/compare/export',
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        memberRepositoryProvider.overrideWithValue(members),
        photoRecordRepositoryProvider.overrideWithValue(records),
        bodyPhotoRepositoryProvider.overrideWithValue(photos),
        gridSettingsServiceProvider.overrideWithValue(grid),
        compareExportSinkProvider.overrideWithValue(sink),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('compare.export.backToDates.button')),
        findsOneWidget);
  });

  testWidgets('extra가 소실되어도 쿼리 파라미터가 있으면 기본 구도로 복구된다', (tester) async {
    // 프로세스 복원/딥링크로 extra(CompareExportRequest)가 사라진 경우,
    // 쿼리의 사진 id/방향으로 기본 구도(전체 사진 표시)의 요청을 재구성해
    // 화면을 계속 사용할 수 있어야 한다(코드 리뷰 MAJOR-5 대응).
    final router = createCompareTestRouter(
      initialLocation: '/members/m1/compare/export'
          '?direction=front&beforePhotoId=bp1&afterPhotoId=ap1',
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        memberRepositoryProvider.overrideWithValue(members),
        photoRecordRepositoryProvider.overrideWithValue(records),
        bodyPhotoRepositoryProvider.overrideWithValue(photos),
        gridSettingsServiceProvider.overrideWithValue(grid),
        compareExportSinkProvider.overrideWithValue(sink),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('compare.export.generate.button')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('compare.export.backToDates.button')),
        findsNothing);
  });
}
