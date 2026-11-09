import 'dart:io';

import 'package:bodymark/core/models/models.dart';
import 'package:bodymark/core/providers.dart';
import 'package:bodymark/features/compare/compare_export_screen.dart';
import 'package:bodymark/features/compare/services/compare_export_sink.dart';
import 'package:bodymark/features/compare/services/compare_photo_loader.dart';
import 'package:bodymark/features/compare/widgets/compare_photo_pane.dart';
import 'package:bodymark/features/settings/providers/settings_providers.dart';
import 'package:bodymark/features/settings/services/app_settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';
import 'test_router.dart';

void main() {
  late FakePhotoRecordRepository records;
  late FakeBodyPhotoRepository photos;
  late FakeGridSettingsService grid;
  late FakeCompareExportSink sink;
  // 실제 파일 디코딩 없이 사진 준비를 통과시킨다. 실패 경로 테스트에서만 바꾼다.
  late ComparePhotoLoader photoLoader;
  AppSettingsService? settingsServiceOverride;

  setUp(() {
    SharedPreferences.setMockInitialValues({});

    records = FakePhotoRecordRepository();
    records.records['r1'] = PhotoRecord(
      id: 'r1',
      label: '동생',
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
    photoLoader = (_, _) async {};
    settingsServiceOverride = null;
  });

  Widget buildApp() {
    final router = createCompareTestRouter(
      initialLocation:
          '/compare/view'
          '?direction=front&beforePhotoId=bp1&afterPhotoId=ap1',
    );
    return ProviderScope(
      overrides: [
        photoRecordRepositoryProvider.overrideWithValue(records),
        bodyPhotoRepositoryProvider.overrideWithValue(photos),
        gridSettingsServiceProvider.overrideWithValue(grid),
        compareExportSinkProvider.overrideWithValue(sink),
        comparePhotoLoaderProvider.overrideWithValue(photoLoader),
        if (settingsServiceOverride != null)
          appSettingsServiceProvider.overrideWithValue(
            settingsServiceOverride!,
          ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> openExport(WidgetTester tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    // 컨트롤 영역은 스크롤된다. 생성 버튼을 화면 안으로 가져온 뒤 누른다.
    await tester.ensureVisible(
      find.byKey(const ValueKey('compare.export.button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('compare.export.button')));
    await tester.pumpAndSettle();
  }

  Future<void> generateImage(WidgetTester tester) async {
    final generateButton = find.byKey(
      const ValueKey('compare.export.generate.button'),
    );
    await tester.ensureVisible(generateButton);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(generateButton);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('비교 화면에서 이미지 생성으로 진입해 옵션을 조정하고 생성·저장·공유까지 진행한다', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    // 전후 비교 화면 -> 이미지 생성 화면.
    // 컨트롤 영역은 스크롤된다. 생성 버튼을 화면 안으로 가져온 뒤 누른다.
    await tester.ensureVisible(
      find.byKey(const ValueKey('compare.export.button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('compare.export.button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey(CompareExportScreen.screenId)),
      findsOneWidget,
    );
    // 회원 이름은 기본 비포함이다.
    expect(find.text('동생'), findsNothing);

    // 라벨 포함 토글을 끄면 미리보기에서 사라진다.
    // SingleChildScrollView 콘텐츠가 테스트 뷰포트보다 길므로 탭 전에
    // 스크롤해 화면 안으로 가져온다.
    final labelToggle = find.byKey(
      const ValueKey('compare.export.label.toggle'),
    );
    await tester.ensureVisible(labelToggle);
    await tester.pumpAndSettle();
    await tester.tap(labelToggle);
    await tester.pumpAndSettle();
    expect(find.text('동생'), findsOneWidget);

    // 생성 전에는 진행·실패 배너가 없고 1단계(구성) CTA만 있다.
    expect(
      find.byKey(const ValueKey('screen.compare.export.status')),
      findsNothing,
    );
    expect(find.text('미리보기 만들기'), findsOneWidget);

    final generateButton = find.byKey(
      const ValueKey('compare.export.generate.button'),
    );
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

    // 2단계(미리보기)는 실제로 만든 이미지 바이트를 보여준다.
    expect(find.text('공유 미리보기'), findsOneWidget);
    final preview = tester.widget<Image>(
      find.byKey(const ValueKey('compare.export.result.thumbnail')),
    );
    expect(preview.image, isA<MemoryImage>());
    expect(preview.fit, BoxFit.contain);
    expect(
      find.byKey(const ValueKey('compare.export.generate.button')),
      findsNothing,
    );

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

    final shareButton = find.byKey(
      const ValueKey('compare.export.share.button'),
    );
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

    // 컨트롤 영역은 스크롤된다. 생성 버튼을 화면 안으로 가져온 뒤 누른다.
    await tester.ensureVisible(
      find.byKey(const ValueKey('compare.export.button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('compare.export.button')));
    await tester.pumpAndSettle();

    final generateButton = find.byKey(
      const ValueKey('compare.export.generate.button'),
    );
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

    expect(find.text('저장에 실패했어요. 다시 시도해주세요.'), findsOneWidget);
    expect(sink.savedNames, isEmpty);
  });

  testWidgets('사진 메모도 촬영 기록 메모와 함께 생성 이미지에 표시한다', (tester) async {
    records.records['r1'] = records.records['r1']!.copyWith(memo: '이전 기록 메모');
    records.records['r2'] = records.records['r2']!.copyWith(memo: '이후 기록 메모');
    photos.photos['bp1'] = photos.photos['bp1']!.copyWith(memo: '이전 사진 메모');
    photos.photos['ap1'] = photos.photos['ap1']!.copyWith(memo: '이후 사진 메모');

    await openExport(tester);

    final memoToggle = find.byKey(const ValueKey('compare.export.memo.toggle'));
    await tester.ensureVisible(memoToggle);
    await tester.tap(memoToggle);
    await tester.pumpAndSettle();

    expect(find.textContaining('이전 기록: 이전 기록 메모'), findsOneWidget);
    expect(find.textContaining('이전 사진: 이전 사진 메모'), findsOneWidget);
    expect(find.textContaining('이후 기록: 이후 기록 메모'), findsOneWidget);
    expect(find.textContaining('이후 사진: 이후 사진 메모'), findsOneWidget);
  });

  testWidgets('저장된 기본 내보내기 옵션을 최초값으로 사용한다', (tester) async {
    const settings = AppSettings(
      defaultExportOptions: ExportImageOptions(
        includeShotDate: false,
        includeLabel: true,
        includeMemo: false,
        includeGrid: true,
      ),
    );
    SharedPreferences.setMockInitialValues({'app_settings': settings.toJson()});

    await openExport(tester);

    expect(find.text('동생'), findsWidgets);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('compare.export.date.toggle')),
          )
          .value,
      isFalse,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('compare.export.grid.toggle')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('compare.export.label.toggle')),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('이후 기록에만 라벨이 있어도 생성 이미지에 표시한다', (tester) async {
    // 본인 기록은 라벨이 없다. 이전 기록만 보면 라벨 포함을 켜도 아무것도 안 나온다.
    records.records['r1'] = records.records['r1']!.copyWith(clearLabel: true);
    records.records['r2'] = records.records['r2']!.copyWith(label: '동생');

    await openExport(tester);
    final toggle = find.byKey(const ValueKey('compare.export.label.toggle'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(find.text('동생'), findsWidgets);
  });

  testWidgets('두 기록의 라벨이 다르면 양쪽을 함께 표시한다', (tester) async {
    records.records['r2'] = records.records['r2']!.copyWith(label: '누나');

    await openExport(tester);
    final toggle = find.byKey(const ValueKey('compare.export.label.toggle'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(find.text('이전: 동생 · 이후: 누나'), findsOneWidget);
  });

  testWidgets('비교 화면 격자를 건드리지 않으면 저장된 기본 옵션을 그대로 쓴다', (tester) async {
    // 비교 화면은 격자를 켠 상태로 시작하지만, 그 기본값만으로 사용자가 저장해 둔
    // 격자 없이 내보내기 설정을 덮어쓰면 안 된다.
    const settings = AppSettings(
      defaultExportOptions: ExportImageOptions(includeGrid: false),
    );
    SharedPreferences.setMockInitialValues({'app_settings': settings.toJson()});

    await openExport(tester);

    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('compare.export.grid.toggle')),
          )
          .value,
      isFalse,
    );
  });

  testWidgets('비교 화면에서 격자를 직접 끄면 생성 화면도 끈 상태로 시작한다', (tester) async {
    const settings = AppSettings(
      defaultExportOptions: ExportImageOptions(includeGrid: true),
    );
    SharedPreferences.setMockInitialValues({'app_settings': settings.toJson()});

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    // 비교 화면의 격자 표시 토글을 직접 끈다.
    final viewGridToggle = find.byKey(const ValueKey('compare.grid.toggle'));
    await tester.ensureVisible(viewGridToggle);
    await tester.tap(viewGridToggle);
    await tester.pumpAndSettle();

    // 컨트롤 영역은 스크롤된다. 생성 버튼을 화면 안으로 가져온 뒤 누른다.
    await tester.ensureVisible(
      find.byKey(const ValueKey('compare.export.button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('compare.export.button')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('compare.export.grid.toggle')),
          )
          .value,
      isFalse,
    );
  });

  testWidgets('미리보기에서 돌아가면 옵션은 유지하고 만든 결과는 버린다', (tester) async {
    await openExport(tester);

    final labelToggle = find.byKey(
      const ValueKey('compare.export.label.toggle'),
    );
    await tester.ensureVisible(labelToggle);
    await tester.tap(labelToggle);
    await tester.pumpAndSettle();
    await generateImage(tester);
    expect(
      find.byKey(const ValueKey('compare.export.result.thumbnail')),
      findsOneWidget,
    );

    // 앱 바 "구성 수정" → 1단계.
    await tester.tap(find.byKey(const ValueKey('compare.export.edit.button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey(CompareExportScreen.screenId)),
      findsOneWidget,
    );
    expect(
      tester.widget<SwitchListTile>(labelToggle).value,
      isTrue,
      reason: '돌아와도 고른 옵션은 그대로다',
    );
    expect(
      find.byKey(const ValueKey('compare.export.result.thumbnail')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('compare.export.save.button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('compare.export.share.button')),
      findsNothing,
    );

    // 시스템 뒤로 가기도 화면을 닫지 않고 1단계로 돌아간다.
    await generateImage(tester);
    expect(
      find.byKey(const ValueKey('compare.export.result.thumbnail')),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey(CompareExportScreen.screenId)),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('compare.export.generate.button')),
      findsOneWidget,
    );
    expect(tester.widget<SwitchListTile>(labelToggle).value, isTrue);
    expect(sink.savedNames, isEmpty);
    expect(sink.sharedNames, isEmpty);
  });

  testWidgets('사진을 읽지 못하면 빈 이미지를 만들지 않고 실패와 재시도를 보여준다', (tester) async {
    // 캡처할 구성은 화면 뒤에 가려져 있어 사진이 덜 읽힌 채 찍힐 수 있었다.
    // 읽기에 실패하면 성공 대신 실패로 보내고, 다시 시도하면 만들 수 있다.
    var failLoad = true;
    photoLoader = (_, _) async {
      if (failLoad) throw const FileSystemException('decode failed');
    };
    await openExport(tester);
    await generateImage(tester);

    expect(find.text('이미지를 만들지 못했어요'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('compare.export.result.thumbnail')),
      findsNothing,
    );
    expect(find.text('다시 시도'), findsOneWidget);

    failLoad = false;
    await generateImage(tester);
    expect(
      find.byKey(const ValueKey('compare.export.result.thumbnail')),
      findsOneWidget,
    );
  });

  testWidgets('이미지를 만드는 동안 진행 배너를 보여주고 버튼을 막는다', (tester) async {
    await openExport(tester);

    // toImage는 FakeAsync에서 끝나지 않으므로 진행 상태가 유지된다.
    await tester.tap(
      find.byKey(const ValueKey('compare.export.generate.button')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('screen.compare.export.status')),
      findsOneWidget,
    );
    expect(find.text('비교 이미지를 만들고 있어요'), findsOneWidget);
    expect(find.text('이미지 만드는 중'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('compare.export.generate.button')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('구성 단계에서 방향을 바꾸면 같은 기록의 그 방향 사진으로 만든다', (tester) async {
    photos.photos['bl1'] = BodyPhoto(
      id: 'bl1',
      recordId: 'r1',
      filePath: '/nonexistent/before-left.jpg',
      direction: BodyDirection.leftSide,
      createdAt: DateTime(2026, 1, 1),
    );
    photos.photos['al1'] = BodyPhoto(
      id: 'al1',
      recordId: 'r2',
      filePath: '/nonexistent/after-left.jpg',
      direction: BodyDirection.leftSide,
      createdAt: DateTime(2026, 3, 1),
    );
    await openExport(tester);

    final left = find.byKey(
      const ValueKey('compare.export.direction.leftSide'),
    );
    await tester.ensureVisible(left);
    await tester.tap(left);
    await tester.pumpAndSettle();

    final panes = tester
        .widgetList<ComparePhotoPane>(find.byType(ComparePhotoPane))
        .map((p) => p.photo.id)
        .toList();
    expect(panes, ['bl1', 'al1']);
    // 방향이 없는 쪽(후면)은 고를 수 없다.
    expect(
      find.byKey(const ValueKey('compare.export.direction.back')),
      findsNothing,
    );
  });

  testWidgets('현재 포함 옵션을 기본 내보내기 설정으로 저장한다', (tester) async {
    final settingsService = FakeAppSettingsService(
      const AppSettings(defaultGrid: GridSettings(spacing: 55)),
    );
    settingsServiceOverride = settingsService;
    await openExport(tester);

    final labelToggle = find.byKey(
      const ValueKey('compare.export.label.toggle'),
    );
    await tester.ensureVisible(labelToggle);
    await tester.tap(labelToggle);
    final memoToggle = find.byKey(const ValueKey('compare.export.memo.toggle'));
    await tester.ensureVisible(memoToggle);
    await tester.tap(memoToggle);
    await tester.pumpAndSettle();

    final saveDefaultsButton = find.byKey(
      const ValueKey('compare.export.defaults.save.button'),
    );
    await tester.ensureVisible(saveDefaultsButton);
    await tester.tap(saveDefaultsButton);
    await tester.pumpAndSettle();

    expect(find.text('기본 내보내기 옵션으로 저장했어요.'), findsOneWidget);
    expect(settingsService.saveAttempts, 1);
    expect(settingsService.current.defaultExportOptions.includeLabel, isTrue);
    expect(settingsService.current.defaultExportOptions.includeMemo, isTrue);
    // 내보내기 옵션 외의 설정은 건드리지 않는다.
    expect(settingsService.current.defaultGrid.spacing, 55);
  });

  testWidgets('기본 옵션 저장이 실패하면 성공 상태를 표시하지 않고 재시도할 수 있다', (tester) async {
    final settingsService = FakeAppSettingsService(
      AppSettings.defaults,
      failSave: true,
    );
    settingsServiceOverride = settingsService;
    await openExport(tester);

    final memoToggle = find.byKey(const ValueKey('compare.export.memo.toggle'));
    await tester.ensureVisible(memoToggle);
    await tester.tap(memoToggle);

    final saveDefaultsButton = find.byKey(
      const ValueKey('compare.export.defaults.save.button'),
    );
    await tester.ensureVisible(saveDefaultsButton);
    await tester.tap(saveDefaultsButton);
    await tester.pumpAndSettle();

    expect(find.text('기본값 저장에 실패했어요. 다시 시도해주세요.'), findsOneWidget);
    expect(find.text('기본 내보내기 옵션으로 저장했어요.'), findsNothing);
    expect(settingsService.saveAttempts, 1);
    expect(settingsService.current.defaultExportOptions.includeMemo, isFalse);
    expect(
      tester.widget<OutlinedButton>(saveDefaultsButton).onPressed,
      isNotNull,
    );
  });

  testWidgets('필요한 컨텍스트 없이 진입하면 안내 화면을 보여준다', (tester) async {
    // 쿼리 파라미터조차 없으면 복구가 불가능하므로 안내 화면을 보여준다.
    final router = createCompareTestRouter(initialLocation: '/compare/export');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          photoRecordRepositoryProvider.overrideWithValue(records),
          bodyPhotoRepositoryProvider.overrideWithValue(photos),
          gridSettingsServiceProvider.overrideWithValue(grid),
          compareExportSinkProvider.overrideWithValue(sink),
          comparePhotoLoaderProvider.overrideWithValue(photoLoader),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('compare.export.backToDates.button')),
      findsOneWidget,
    );
  });

  testWidgets('extra가 소실되어도 쿼리 파라미터가 있으면 기본 구도로 복구된다', (tester) async {
    // 프로세스 복원/딥링크로 extra(CompareExportRequest)가 사라진 경우,
    // 쿼리의 사진 id/방향으로 기본 구도(전체 사진 표시)의 요청을 재구성해
    // 화면을 계속 사용할 수 있어야 한다(코드 리뷰 MAJOR-5 대응).
    final router = createCompareTestRouter(
      initialLocation:
          '/compare/export'
          '?direction=front&beforePhotoId=bp1&afterPhotoId=ap1',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          photoRecordRepositoryProvider.overrideWithValue(records),
          bodyPhotoRepositoryProvider.overrideWithValue(photos),
          gridSettingsServiceProvider.overrideWithValue(grid),
          compareExportSinkProvider.overrideWithValue(sink),
          comparePhotoLoaderProvider.overrideWithValue(photoLoader),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('compare.export.generate.button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('compare.export.backToDates.button')),
      findsNothing,
    );
  });
}

class FakeAppSettingsService implements AppSettingsService {
  AppSettings current;
  final bool failSave;
  int saveAttempts = 0;

  FakeAppSettingsService(this.current, {this.failSave = false});

  @override
  Future<AppSettings> load() async => current;

  @override
  Future<void> save(AppSettings settings) async {
    saveAttempts++;
    if (failSave) throw StateError('settings save failed');
    current = settings;
  }
}
