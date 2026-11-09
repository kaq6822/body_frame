import 'package:bodymark/core/models/models.dart';
import 'package:bodymark/core/providers.dart';
import 'package:bodymark/features/compare/compare_export_models.dart';
import 'package:bodymark/features/compare/compare_export_screen.dart';
import 'package:bodymark/features/compare/services/compare_export_sink.dart';
import 'package:bodymark/features/compare/services/compare_photo_loader.dart';
import 'package:bodymark/features/compare/widgets/compare_layered_pane.dart';
import 'package:bodymark/features/compare/widgets/compare_photo_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    records = FakePhotoRecordRepository()
      ..records['r1'] = PhotoRecord(
        id: 'r1',
        shotAt: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      )
      ..records['r2'] = PhotoRecord(
        id: 'r2',
        shotAt: DateTime(2026, 3, 1),
        createdAt: DateTime(2026, 3, 1),
        updatedAt: DateTime(2026, 3, 1),
      );
    photos = FakeBodyPhotoRepository()
      ..photos['before'] = BodyPhoto(
        id: 'before',
        recordId: 'r1',
        filePath: '/nonexistent/wide.jpg',
        direction: BodyDirection.front,
        width: 1600,
        height: 900,
        createdAt: DateTime(2026, 1, 1),
      )
      ..photos['after'] = BodyPhoto(
        id: 'after',
        recordId: 'r2',
        filePath: '/nonexistent/tall.jpg',
        direction: BodyDirection.front,
        width: 900,
        height: 1600,
        createdAt: DateTime(2026, 3, 1),
      );
    grid = FakeGridSettingsService();
    sink = FakeCompareExportSink();
    photoLoader = (_, _) async {};
  });

  // 컨트롤 영역이 길어서 기본 800x600에서는 사진 영역이 36dp까지 줄어든다.
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Widget buildApp() {
    final router = createCompareTestRouter(
      initialLocation:
          '/compare/view'
          '?direction=front&beforePhotoId=before&afterPhotoId=after',
    );
    return ProviderScope(
      overrides: [
        photoRecordRepositoryProvider.overrideWithValue(records),
        bodyPhotoRepositoryProvider.overrideWithValue(photos),
        gridSettingsServiceProvider.overrideWithValue(grid),
        compareExportSinkProvider.overrideWithValue(sink),
        comparePhotoLoaderProvider.overrideWithValue(photoLoader),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> selectMode(WidgetTester tester, String buttonId) async {
    await tester.tap(find.byKey(ValueKey(buttonId)));
    await tester.pumpAndSettle();
  }

  Future<void> openExport(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('compare.export.button'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey(CompareExportScreen.screenId)),
      findsOneWidget,
    );
  }

  for (final size in const [Size(360, 640), Size(640, 360)]) {
    testWidgets(
      '${size.width.toInt()}x${size.height.toInt()} 화면에서도 넘치지 않고 이미지 생성으로 갈 수 있다',
      (tester) async {
        // 작은 세로 화면·가로 화면에서 컨트롤이 넘쳐 생성 버튼이 잘리던 문제.
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(buildApp());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        for (final mode in const [
          'compare.mode.overlay.button',
          'compare.mode.slider.button',
          'compare.mode.sideBySide.button',
        ]) {
          await selectMode(tester, mode);
          expect(tester.takeException(), isNull, reason: mode);
        }

        final pane = tester.getSize(
          find.byKey(const ValueKey('compare.before.viewer')),
        );
        // 사진 프레임(3:4)이 손톱만 해지지 않아야 한다.
        expect(pane.height, greaterThan(110));
        await openExport(tester);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('겹쳐 보기 투명도와 슬라이더 경계를 조절할 수 있고 접근성 값을 제공한다', (tester) async {
    final semantics = tester.ensureSemantics();

    useTallViewport(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await selectMode(tester, 'compare.mode.overlay.button');
    expect(
      find.byKey(const ValueKey('compare.overlay.canvas')),
      findsOneWidget,
    );
    expect(find.textContaining('준비 중'), findsNothing);

    final opacitySlider = tester.widget<Slider>(
      find.byKey(const ValueKey('compare.overlay.opacity.slider')),
    );
    opacitySlider.onChanged!(0.3);
    await tester.pump();
    expect(
      tester
          .widget<CompareLayeredPane>(find.byType(CompareLayeredPane))
          .overlayOpacity,
      closeTo(0.3, 0.001),
    );
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('compare.overlay.canvas')))
          .value,
      contains('30%'),
    );

    await selectMode(tester, 'compare.mode.slider.button');
    final handle = find.byKey(const ValueKey('compare.slider.handle'));
    expect(handle, findsOneWidget);
    expect(find.bySemanticsIdentifier('compare.slider.handle'), findsOneWidget);
    expect(tester.getSemantics(handle).label, contains('비교 경계'));
    expect(tester.getSemantics(handle).flagsCollection.isSlider, isTrue);

    await tester.drag(handle, const Offset(50, 0));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CompareLayeredPane>(find.byType(CompareLayeredPane))
          .sliderPosition,
      greaterThan(0.5),
    );
    semantics.dispose();
  });

  testWidgets('컨트롤 슬라이더는 화면에 보이는 값과 같은 퍼센트 하나만 읽힌다', (tester) async {
    final semantics = tester.ensureSemantics();
    useTallViewport(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await selectMode(tester, 'compare.mode.overlay.button');

    tester
        .widget<Slider>(
          find.byKey(const ValueKey('compare.overlay.opacity.slider')),
        )
        .onChanged!(0.44);
    await tester.pump();

    expect(find.text('44%'), findsOneWidget);
    final values = <String>[];
    void collect(SemanticsNode node) {
      if (node.value.isNotEmpty) values.add(node.value);
      node.visitChildren((child) {
        collect(child);
        return true;
      });
    }

    collect(
      tester.getSemantics(
        find.byKey(const ValueKey('compare.overlay.opacity.slider')),
      ),
    );
    expect(values, ['44%']);
    semantics.dispose();
  });

  testWidgets('겹쳐 보기 모드와 투명도가 생성 화면에 그대로 전달된다', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await selectMode(tester, 'compare.mode.overlay.button');

    tester
        .widget<Slider>(
          find.byKey(const ValueKey('compare.overlay.opacity.slider')),
        )
        .onChanged!(0.24);
    await tester.pumpAndSettle();
    await openExport(tester);

    final exported = tester.widget<CompareLayeredPane>(
      find.byType(CompareLayeredPane),
    );
    expect(exported.mode, CompareMode.overlay);
    expect(exported.overlayOpacity, closeTo(0.24, 0.001));
    expect(
      find.byKey(const ValueKey('compare.export.overlay.canvas')),
      findsOneWidget,
    );
  });

  testWidgets('슬라이더 모드와 경계 위치가 생성 화면에 그대로 전달된다', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await selectMode(tester, 'compare.mode.slider.button');

    tester
        .widget<Slider>(
          find.byKey(const ValueKey('compare.slider.position.slider')),
        )
        .onChanged!(0.72);
    await tester.pumpAndSettle();
    await openExport(tester);

    final exported = tester.widget<CompareLayeredPane>(
      find.byType(CompareLayeredPane),
    );
    expect(exported.mode, CompareMode.slider);
    expect(exported.sliderPosition, closeTo(0.72, 0.001));
    expect(
      find.byKey(const ValueKey('compare.export.slider.canvas')),
      findsOneWidget,
    );
  });

  testWidgets('비교 화면에서 방향을 바꾸면 같은 두 기록의 그 방향 사진을 보여준다', (tester) async {
    photos.photos['beforeLeft'] = BodyPhoto(
      id: 'beforeLeft',
      recordId: 'r1',
      filePath: '/nonexistent/before-left.jpg',
      direction: BodyDirection.leftSide,
      createdAt: DateTime(2026, 1, 1),
    );
    photos.photos['afterLeft'] = BodyPhoto(
      id: 'afterLeft',
      recordId: 'r2',
      filePath: '/nonexistent/after-left.jpg',
      direction: BodyDirection.leftSide,
      createdAt: DateTime(2026, 3, 1),
    );
    // 한쪽에만 있는 방향은 단계에 나오지 않는다.
    photos.photos['onlyBack'] = BodyPhoto(
      id: 'onlyBack',
      recordId: 'r1',
      filePath: '/nonexistent/back.jpg',
      direction: BodyDirection.back,
      createdAt: DateTime(2026, 1, 1),
    );
    useTallViewport(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('compare.view.direction.back')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('compare.view.direction.leftSide')),
    );
    await tester.pumpAndSettle();

    final shown = tester
        .widgetList<ComparePhotoPane>(find.byType(ComparePhotoPane))
        .map((p) => p.photo.id)
        .toList();
    expect(shown, ['beforeLeft', 'afterLeft']);

    await openExport(tester);
    final exported = tester
        .widgetList<ComparePhotoPane>(find.byType(ComparePhotoPane))
        .map((p) => p.photo.id)
        .toList();
    expect(exported, ['beforeLeft', 'afterLeft']);
  });

  for (final size in const [Size(320, 640), Size(640, 360)]) {
    testWidgets(
      '큰 글꼴(2배) ${size.width.toInt()}x${size.height.toInt()}에서도 비교·구성·미리보기가 넘치지 않는다',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(buildApp());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await selectMode(tester, 'compare.mode.overlay.button');
        expect(tester.takeException(), isNull);
        await openExport(tester);
        expect(tester.takeException(), isNull);

        await tester.runAsync(() async {
          await tester.tap(
            find.byKey(const ValueKey('compare.export.generate.button')),
          );
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('compare.export.result.thumbnail')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        // 미리보기의 두 버튼은 화면 안에 있어야 한다.
        for (final id in const [
          'compare.export.share.button',
          'compare.export.save.button',
        ]) {
          final rect = tester.getRect(find.byKey(ValueKey(id)));
          expect(rect.bottom, lessThanOrEqualTo(size.height), reason: id);
        }
      },
    );
  }
}
