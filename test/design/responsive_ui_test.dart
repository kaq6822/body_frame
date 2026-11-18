import 'package:bodymark/core/theme/app_theme.dart';
import 'package:bodymark/features/capture/providers/capture_session_provider.dart';
import 'package:bodymark/features/capture/widgets/capture_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
