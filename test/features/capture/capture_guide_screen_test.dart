import 'package:bodymark/features/capture/capture_guide_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 촬영 가이드(Stitch 21): 번호 단계·표준 순서·하단 복귀 버튼.
void main() {
  Future<void> pumpGuide(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const ValueKey('open'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CaptureGuideScreen(),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
  }

  testWidgets('번호 단계 3개와 표준 촬영 순서를 보여주고 촬영으로 돌아간다', (tester) async {
    await pumpGuide(tester);

    for (final i in [1, 2, 3]) {
      expect(find.byKey(ValueKey('capture.guide.step.$i')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('capture.guide.order')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('capture.guide.back.button')));
    await tester.pumpAndSettle();
    expect(find.byType(CaptureGuideScreen), findsNothing);
  });

  testWidgets('320dp·글꼴 2배에서도 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpGuide(tester);
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('capture.guide.back.button')),
      findsOneWidget,
    );
  });
}
