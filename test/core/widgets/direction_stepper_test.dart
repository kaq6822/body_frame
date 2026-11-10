import 'package:bodymark/core/models/body_direction.dart';
import 'package:bodymark/core/theme/app_theme.dart';
import 'package:bodymark/core/widgets/direction_stepper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {double width = 360, double scale = 1}) =>
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 640),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: Center(
            child: SizedBox(width: width - 32, child: child),
          ),
        ),
      ),
    );

void main() {
  testWidgets('방향을 누르면 onSelected로 전달하고 상태를 Semantics로 읽힌다', (tester) async {
    final handle = tester.ensureSemantics();
    BodyDirection? tapped;
    await tester.pumpWidget(
      _host(
        DirectionStepper(
          selected: BodyDirection.front,
          recorded: const {BodyDirection.front, BodyDirection.leftSide},
          onSelected: (d) => tapped = d,
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('common.direction.stepper.rightSide')),
    );
    expect(tapped, BodyDirection.rightSide);

    final front = tester.getSemantics(
      find.byKey(const ValueKey('common.direction.stepper.front')),
    );
    expect(front.label, '정면, 1/4단계, 기록됨, 현재 단계');
    expect(front, isSemantics(isSelected: true, isButton: true));
    final back = tester.getSemantics(
      find.byKey(const ValueKey('common.direction.stepper.back')),
    );
    expect(back.label, '후면, 4/4단계');
    expect(find.byIcon(Icons.check), findsNWidgets(2));
    handle.dispose();
  });

  testWidgets('각 세그먼트는 48dp 이상 터치 영역을 가진다', (tester) async {
    await tester.pumpWidget(
      _host(DirectionStepper(selected: null, onSelected: (_) {})),
    );
    for (final d in DirectionStepper.standardDirections) {
      final size = tester.getSize(
        find.byKey(ValueKey('common.direction.stepper.${d.key}')),
      );
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
    }
  });

  for (final onDark in [false, true]) {
    testWidgets('320dp·2배 글꼴에서 줄바꿈하고 넘치지 않는다 (onDark: $onDark)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          DirectionStepper(
            selected: BodyDirection.leftSide,
            recorded: const {BodyDirection.front},
            onDark: onDark,
            onSelected: (_) {},
          ),
          width: 320,
          scale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
      final front = tester.getTopLeft(
        find.byKey(const ValueKey('common.direction.stepper.front')),
      );
      final right = tester.getTopLeft(
        find.byKey(const ValueKey('common.direction.stepper.rightSide')),
      );
      // 2×2 배치: 우측면은 둘째 줄로 내려간다.
      expect(right.dy, greaterThan(front.dy));
    });
  }

  testWidgets('넓은 화면 보통 글꼴에서는 한 줄로 놓인다', (tester) async {
    await tester.pumpWidget(
      _host(
        DirectionStepper(selected: BodyDirection.front, onSelected: (_) {}),
      ),
    );
    final front = tester.getTopLeft(
      find.byKey(const ValueKey('common.direction.stepper.front')),
    );
    final back = tester.getTopLeft(
      find.byKey(const ValueKey('common.direction.stepper.back')),
    );
    expect(back.dy, front.dy);
  });

  testWidgets('onDark 활성 방향은 측정 시안으로 채운다', (tester) async {
    await tester.pumpWidget(
      _host(
        DirectionStepper(
          selected: BodyDirection.front,
          onDark: true,
          onSelected: (_) {},
        ),
      ),
    );
    final material = tester.widget<Material>(
      find.byKey(const ValueKey('common.direction.stepper.front')),
    );
    expect(material.color, const Color(0xFF06B6D4));
  });

  testWidgets('singleRow는 좁은 화면·큰 글꼴에서도 한 줄·고정 높이다', (tester) async {
    for (final scale in [1.0, 2.0]) {
      await tester.pumpWidget(
        _host(
          DirectionStepper(
            selected: BodyDirection.leftSide,
            singleRow: true,
            labelBuilder: (d) =>
                d == BodyDirection.leftSide ? '좌측 2/4' : d.label,
            onSelected: (_) {},
          ),
          width: 320,
          scale: scale,
        ),
      );
      final rects = [
        for (final d in DirectionStepper.standardDirections)
          tester.getRect(
            find.byKey(ValueKey('common.direction.stepper.${d.key}')),
          ),
      ];
      expect({for (final r in rects) r.top}, hasLength(1), reason: '$scale');
      expect(rects.first.height, 48, reason: '$scale');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('captionBuilder는 방향 아래 보조 문구를 보여주고 상태로 읽힌다', (tester) async {
    await tester.pumpWidget(
      _host(
        DirectionStepper(
          selected: BodyDirection.front,
          singleRow: true,
          captionBuilder: (d) => d == BodyDirection.back ? '건너뜀' : null,
          onSelected: (_) {},
        ),
      ),
    );
    expect(find.text('건너뜀'), findsOneWidget);
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('common.direction.stepper.back')),
          )
          .label,
      '후면, 4/4단계, 건너뜀',
    );
  });
}
