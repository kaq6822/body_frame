import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/widgets/grid_painter.dart';
import 'package:body_frame/features/compare/widgets/compare_grid_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('비교 화면에서 격자를 명시적으로 표시하면 저장된 visible 값보다 우선한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 200,
          height: 300,
          child: CompareGridOverlay(
            settings: GridSettings(visible: false),
            semanticsIdentifier: 'test.compare.grid',
          ),
        ),
      ),
    );

    final paintFinder = find.descendant(
      of: find.byType(CompareGridOverlay),
      matching: find.byType(CustomPaint),
    );
    expect(paintFinder, findsOneWidget);

    final customPaint = tester.widget<CustomPaint>(paintFinder);
    expect(customPaint.painter, isA<GridPainter>());
    expect((customPaint.painter! as GridPainter).settings.visible, isTrue);
  });
}
