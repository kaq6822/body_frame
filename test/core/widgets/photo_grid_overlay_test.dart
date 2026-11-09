import 'dart:async';
import 'dart:ui' as ui;

import 'package:bodymark/core/models/models.dart';
import 'package:bodymark/core/theme/app_tokens.dart';
import 'package:bodymark/core/widgets/photo_grid_overlay.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('scaleGridToBox', () {
    const settings = GridSettings(spacing: 40, lineWidth: 2);

    test('기준 폭과 같거나 넓으면 설정을 그대로 쓴다', () {
      expect(
        scaleGridToBox(settings, boxWidth: 400, referenceWidth: 400),
        settings,
      );
      expect(
        scaleGridToBox(settings, boxWidth: 800, referenceWidth: 400),
        settings,
      );
    });

    test('상자가 좁으면 간격과 선 굵기를 비례 축소한다', () {
      final scaled = scaleGridToBox(
        settings,
        boxWidth: 200,
        referenceWidth: 400,
      );
      expect(scaled.spacing, 20);
      expect(scaled.lineWidth, 1);
      // 나머지 설정은 손대지 않는다.
      expect(scaled.opacity, settings.opacity);
      expect(scaled.colorValue, settings.colorValue);
    });

    test('아주 작은 썸네일에서도 격자가 뭉개지지 않게 하한을 둔다', () {
      final scaled = scaleGridToBox(
        settings,
        boxWidth: 40,
        referenceWidth: 400,
      );
      expect(scaled.spacing, 12);
      expect(scaled.lineWidth, 0.5);
    });

    test('하한이 원래 설정값을 거꾸로 키우지 않는다', () {
      const dense = GridSettings(spacing: 10, lineWidth: 0.5);
      final scaled = scaleGridToBox(dense, boxWidth: 40, referenceWidth: 400);
      expect(scaled.spacing, 10);
      expect(scaled.lineWidth, 0.5);
    });

    test('폭을 알 수 없으면 설정을 그대로 쓴다', () {
      expect(
        scaleGridToBox(
          settings,
          boxWidth: double.infinity,
          referenceWidth: 400,
        ),
        settings,
      );
      expect(
        scaleGridToBox(settings, boxWidth: 0, referenceWidth: 400),
        settings,
      );
      expect(
        scaleGridToBox(settings, boxWidth: 200, referenceWidth: 0),
        settings,
      );
    });
  });

  group('PhotoGridOverlay', () {
    Widget host(GridSettings settings) => MaterialApp(
      home: Center(
        child: SizedBox(
          width: 100,
          height: 100,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              PhotoGridOverlay(
                settings: settings,
                semanticsIdentifier: 'test.grid.overlay',
              ),
            ],
          ),
        ),
      ),
    );

    testWidgets('표시 설정이 켜져 있으면 격자를 그린다', (tester) async {
      await tester.pumpWidget(host(GridSettings.defaults));
      expect(find.byKey(const ValueKey('test.grid.overlay')), findsOneWidget);
    });

    testWidgets('표시 설정이 꺼져 있으면 아무것도 그리지 않는다', (tester) async {
      await tester.pumpWidget(
        host(GridSettings.defaults.copyWith(visible: false)),
      );
      expect(find.byKey(const ValueKey('test.grid.overlay')), findsNothing);
    });

    testWidgets('격자는 아래 위젯의 제스처를 가로채지 않는다', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 100,
              height: 100,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    key: const ValueKey('test.photo'),
                    onTap: () => tapped = true,
                    child: const ColoredBox(color: Colors.black),
                  ),
                  const PhotoGridOverlay(
                    settings: GridSettings.defaults,
                    semanticsIdentifier: 'test.grid.overlay',
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('test.photo')));
      expect(tapped, isTrue);
    });
  });

  group('PhotoWithGrid', () {
    const boxSize = 200.0;
    const gridKey = ValueKey('test.grid.overlay');

    Widget host(ImageProvider image, {double? aspectRatio}) => MaterialApp(
      home: Center(
        child: SizedBox(
          key: const ValueKey('test.box'),
          width: boxSize,
          height: boxSize,
          child: PhotoWithGrid(
            image: image,
            aspectRatio: aspectRatio,
            settings: GridSettings.defaults,
            gridSemanticsIdentifier: 'test.grid.overlay',
            errorIdPrefix: 'test.photo',
          ),
        ),
      ),
    );

    Rect photoRect(WidgetTester tester) {
      final box = tester.getRect(find.byKey(const ValueKey('test.box')));
      return tester.getRect(find.byKey(gridKey)).shift(-box.topLeft);
    }

    testWidgets('세로 사진은 정사각 상자 가운데 사진 폭에만 격자를 그린다', (tester) async {
      await tester.pumpWidget(host(_PendingImage(), aspectRatio: 3 / 4));
      expect(photoRect(tester), const Rect.fromLTWH(25, 0, 150, 200));
    });

    testWidgets('가로 사진은 정사각 상자 가운데 사진 높이에만 격자를 그린다', (tester) async {
      await tester.pumpWidget(host(_PendingImage(), aspectRatio: 4 / 3));
      expect(photoRect(tester), const Rect.fromLTWH(0, 25, 200, 150));
    });

    testWidgets('사진 비율을 모르면 letterbox까지 번지게 그리지 않는다', (tester) async {
      await tester.pumpWidget(host(_PendingImage()));
      expect(find.byKey(gridKey), findsNothing);
    });

    testWidgets('메타데이터가 없으면 디코딩한 사진 크기로 격자 영역을 정한다', (tester) async {
      final bytes = (await tester.runAsync(() => _pngBytes(2, 4)))!;
      final image = MemoryImage(bytes);
      await tester.pumpWidget(host(image));
      for (var i = 0; i < 40 && find.byKey(gridKey).evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(photoRect(tester), const Rect.fromLTWH(50, 0, 100, 200));
    });

    testWidgets('사진을 불러오지 못하면 문구와 재시도를 보여 주고 다시 불러온다', (tester) async {
      final image = _FailingImage();
      await tester.pumpWidget(host(image, aspectRatio: 3 / 4));
      await tester.pump();

      expect(find.byKey(const ValueKey('test.photo.error')), findsOneWidget);
      expect(find.text('사진을 불러오지 못했어요'), findsOneWidget);
      expect(find.byKey(gridKey), findsNothing);
      final loadsBefore = image.loads;

      await tester.tap(find.byKey(const ValueKey('test.photo.retry.button')));
      await tester.pump();
      await tester.pump();

      expect(image.loads, greaterThan(loadsBefore));
      expect(find.byKey(const ValueKey('test.photo.error')), findsOneWidget);
    });

    testWidgets('실패 문구는 어두운 사진 배경 위에서 읽히는 고정 흰색이다', (tester) async {
      await tester.pumpWidget(host(_FailingImage(), aspectRatio: 1));
      await tester.pump();
      final text = tester.widget<Text>(find.text('사진을 불러오지 못했어요'));
      expect(text.style?.color, const AppPhotoColors().onChrome);
    });
  });
}

Future<Uint8List> _pngBytes(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF808080),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

/// 끝나지 않는 이미지. 메타데이터 비율만으로 배치를 검증할 때 쓴다.
class _PendingImage extends ImageProvider<_PendingImage> {
  @override
  Future<_PendingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _PendingImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(Completer<ImageInfo>().future);
}

/// 항상 실패하는 이미지. 불러온 횟수를 센다.
class _FailingImage extends ImageProvider<_FailingImage> {
  int loads = 0;

  @override
  Future<_FailingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _FailingImage key,
    ImageDecoderCallback decode,
  ) {
    loads++;
    return OneFrameImageStreamCompleter(
      Future<ImageInfo>.error(StateError('missing file')),
    );
  }
}
