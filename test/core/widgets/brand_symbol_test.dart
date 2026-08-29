import 'package:body_frame/core/widgets/brand_symbol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 심벌은 에셋 없이 페인터로 그리므로, 두 변형이 예외 없이 그려지는지와
/// 접근성 노출 규칙(장식이면 제외, 라벨을 주면 노출)을 확인한다.
void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('두 표현 방식 모두 예외 없이 그려진다', (tester) async {
    await tester.pumpWidget(
      host(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandSymbol(size: 40, color: Colors.black),
            BrandSymbol(
              size: 88,
              color: Colors.black,
              figureColor: Colors.blue,
              style: BrandSymbolStyle.outlined,
            ),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(BrandSymbol), findsNWidgets(2));
  });

  testWidgets('크기가 0이어도 그리기가 실패하지 않는다', (tester) async {
    await tester.pumpWidget(
      host(const SizedBox.shrink(child: BrandSymbol(color: Colors.black))),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('라벨이 없으면 스크린 리더에서 제외된다', (tester) async {
    await tester.pumpWidget(host(const BrandSymbol(color: Colors.black)));

    // MaterialApp 내부에도 ExcludeSemantics가 있으므로 심벌 하위만 본다.
    expect(
      find.descendant(
        of: find.byType(BrandSymbol),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
  });

  testWidgets('라벨을 주면 이미지로 노출된다', (tester) async {
    await tester.pumpWidget(
      host(
        const BrandSymbol(color: Colors.black, semanticLabel: 'Body Frame 심벌'),
      ),
    );

    expect(
      tester.getSemantics(find.bySemanticsLabel('Body Frame 심벌')),
      isNotNull,
    );
  });

  testWidgets('워드마크는 워드타입을 중복 낭독하지 않고 한 번만 노출한다', (tester) async {
    await tester.pumpWidget(host(const BrandWordmark(color: Colors.black)));

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Body Frame'), findsOneWidget);
  });
}
