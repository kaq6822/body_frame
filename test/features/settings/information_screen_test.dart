import 'package:bodymark/features/settings/information_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

GoRouter _router(String initial) => GoRouter(
  initialLocation: initial,
  routes: [
    GoRoute(
      path: '/settings/data',
      builder: (_, _) => const InformationScreen(),
    ),
    GoRoute(
      path: '/settings/privacy',
      builder: (_, _) => const InformationScreen(privacy: true),
    ),
  ],
);

Future<void> _pump(WidgetTester tester, String initial, double scale) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = _router(initial);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('데이터 보관 안내: 백업과 다름 안내와 개인정보 안내 링크', (tester) async {
    await _pump(tester, '/settings/data', 2);
    expect(find.byKey(const ValueKey('settings.data.intro')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings.data.backupNote')),
      200,
    );
    expect(
      find.byKey(const ValueKey('settings.data.backupNote')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings.data.link')),
      200,
    );
    await tester.tap(find.byKey(const ValueKey('settings.data.link')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('screen.settings.privacy')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('개인정보 안내: 데이터 보관 안내로 이동', (tester) async {
    await _pump(tester, '/settings/privacy', 1);
    expect(
      find.byKey(const ValueKey('settings.privacy.intro')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings.privacy.link')),
      200,
    );
    await tester.tap(find.byKey(const ValueKey('settings.privacy.link')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('screen.settings.data')), findsOneWidget);
  });
}
