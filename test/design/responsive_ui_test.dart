import 'dart:io';
import 'dart:ui' as ui;

import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/core/theme/app_theme.dart';
import 'package:body_frame/features/capture/providers/capture_session_provider.dart';
import 'package:body_frame/features/capture/widgets/capture_progress_bar.dart';
import 'package:body_frame/features/records/records_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/compare/fakes.dart';
import '../features/compare/test_router.dart';

void main() {
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('비교 날짜와 방향: 320px, 글꼴 $scale, 다크 $dark에서도 다음 단계 접근 가능', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final records = FakePhotoRecordRepository();
        final photos = FakeBodyPhotoRepository();
        for (var i = 0; i < 2; i++) {
          final date = DateTime(2026, 1, 1 + i * 7);
          records.records['r$i'] = PhotoRecord(
            id: 'r$i',
            shotAt: date,
            createdAt: date,
            updatedAt: date,
          );
          for (final direction in BodyDirection.values) {
            final id = 'r$i-${direction.key}';
            photos.photos[id] = BodyPhoto(
              id: id,
              recordId: 'r$i',
              filePath: '/unused/$id.png',
              direction: direction,
              createdAt: date,
            );
          }
        }
        final router = createCompareTestRouter(initialLocation: '/compare');
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              photoRecordRepositoryProvider.overrideWithValue(records),
              bodyPhotoRepositoryProvider.overrideWithValue(photos),
            ],
            child: MaterialApp.router(
              theme: dark ? AppTheme.dark : AppTheme.light,
              routerConfig: router,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('7일 사이의 변화'), findsOneWidget);
        final next = find.byKey(const ValueKey('compare.dates.next.button'));
        await tester.ensureVisible(next);
        await tester.pumpAndSettle();
        expect(tester.widget<ElevatedButton>(next).onPressed, isNotNull);
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('compare.direction.intro')),
          findsOneWidget,
        );
        final directionNext = find.byKey(
          const ValueKey('compare.direction.next.button'),
        );
        await tester.ensureVisible(directionNext);
        await tester.pumpAndSettle();
        expect(
          tester.widget<ElevatedButton>(directionNext).onPressed,
          isNotNull,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('빈 기록: 큰 글꼴에서 촬영과 갤러리 진입점에 접근 가능', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          photoRecordRepositoryProvider.overrideWithValue(
            FakePhotoRecordRepository(),
          ),
          bodyPhotoRepositoryProvider.overrideWithValue(
            FakeBodyPhotoRepository(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const RecordsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final id in [
      'records.empty.capture.button',
      'records.empty.import.button',
    ]) {
      await tester.ensureVisible(find.byKey(ValueKey(id)));
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier(id), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(60, 120),
    const Size(120, 60),
    const Size(80, 80),
  ]) {
    testWidgets('기록 사진 $size: 원본 비율 보존, 큰 글꼴에서 카드와 필터 조작 가능', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final directory = Directory.systemTemp.createTempSync(
        'body-frame-layout-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/photo.png');
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
        canvas.drawRect(
          Rect.fromLTWH(0, 0, size.width, 8),
          Paint()..color = Colors.red,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(
          size.width.toInt(),
          size.height.toInt(),
        );
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        file.writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
      });
      final bytes = file.readAsBytesSync();
      final date = DateTime(2026, 1, 1);
      final records = FakePhotoRecordRepository();
      records.records['r1'] = PhotoRecord(
        id: 'r1',
        shotAt: date,
        createdAt: date,
        updatedAt: date,
        label: '긴 촬영 대상 라벨도 화면 안에서 확인',
      );
      final photos = FakeBodyPhotoRepository();
      for (final direction in [BodyDirection.front, BodyDirection.back]) {
        photos.photos[direction.key] = BodyPhoto(
          id: direction.key,
          recordId: 'r1',
          filePath: file.path,
          direction: direction,
          width: size.width.toInt(),
          height: size.height.toInt(),
          createdAt: date,
        );
      }
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            photoRecordRepositoryProvider.overrideWithValue(records),
            bodyPhotoRepositoryProvider.overrideWithValue(photos),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const RecordsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final strip = find.descendant(
        of: find.byKey(const ValueKey('records.item.0')),
        matching: find.byType(Image),
      );
      expect(strip, findsNWidgets(2));
      for (final image in tester.widgetList<Image>(strip)) {
        expect(image.fit, BoxFit.contain);
      }
      await tester.tap(find.byKey(const ValueKey('records.filter.back')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('records.direction.item.0')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(file.readAsBytesSync(), bytes);
      await tester.pumpWidget(const SizedBox());
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });
  }

  testWidgets('촬영 방향: 큰 글꼴에서도 터치 영역 48px 및 단계 선택 유지', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Center(
              child: CaptureProgressBar(
                shots: [
                  for (final direction in kSessionDirections)
                    CaptureShot(direction: direction),
                ],
                currentIndex: 0,
                foreground: Colors.white,
                onStepSelected: (index) => selected = index,
              ),
            ),
          ),
        ),
      ),
    );
    for (final direction in kSessionDirections) {
      final step = find.byKey(
        ValueKey('capture.progress.step.${direction.key}'),
      );
      expect(tester.getSize(step).height, greaterThanOrEqualTo(48));
      await tester.tap(step);
      expect(selected, kSessionDirections.indexOf(direction));
    }
    expect(tester.takeException(), isNull);
  });
}
