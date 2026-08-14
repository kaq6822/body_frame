import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/widgets/photo_grid_overlay.dart';
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
}
