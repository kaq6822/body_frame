import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/features/compare/compare_export_models.dart';
import 'package:body_frame/features/compare/compare_export_screen.dart';
import 'package:body_frame/features/compare/services/compare_export_sink.dart';
import 'package:body_frame/features/compare/widgets/compare_layered_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';
import 'test_router.dart';

void main() {
  late FakeMemberRepository members;
  late FakePhotoRecordRepository records;
  late FakeBodyPhotoRepository photos;
  late FakeGridSettingsService grid;
  late FakeCompareExportSink sink;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    members = FakeMemberRepository()
      ..members['m1'] = Member(
        id: 'm1',
        name: '테스트 회원',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
    records = FakePhotoRecordRepository()
      ..records['r1'] = PhotoRecord(
        id: 'r1',
        memberId: 'm1',
        shotAt: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      )
      ..records['r2'] = PhotoRecord(
        id: 'r2',
        memberId: 'm1',
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
  });

  Widget buildApp() {
    final router = createCompareTestRouter(
      initialLocation:
          '/members/m1/compare/view'
          '?direction=front&beforePhotoId=before&afterPhotoId=after',
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

  testWidgets('겹쳐 보기 투명도와 슬라이더 경계를 조절할 수 있고 접근성 값을 제공한다', (tester) async {
    final semantics = tester.ensureSemantics();

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

  testWidgets('겹쳐 보기 모드와 투명도가 생성 화면에 그대로 전달된다', (tester) async {
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
}
