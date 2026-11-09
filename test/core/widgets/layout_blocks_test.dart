import 'package:bodymark/core/theme/app_theme.dart';
import 'package:bodymark/core/widgets/bottom_action_bar.dart';
import 'package:bodymark/core/widgets/info_row.dart';
import 'package:bodymark/core/widgets/section_header.dart';
import 'package:bodymark/core/widgets/status_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(
  Widget body, {
  Widget? bottom,
  double scale = 1,
  bool dark = false,
}) => MaterialApp(
  theme: dark ? AppTheme.dark : AppTheme.light,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(body: body, bottomNavigationBar: bottom),
);

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('BottomActionBar: 320dp, 글꼴 $scale에서 버튼이 넘치지 않는다', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          const SizedBox.shrink(),
          scale: scale,
          bottom: BottomActionBar(
            identifier: 'test.actions',
            secondary: OutlinedButton(
              key: const ValueKey('test.save'),
              onPressed: () {},
              child: const Text('기기에 저장'),
            ),
            primary: FilledButton(
              key: const ValueKey('test.share'),
              onPressed: () {},
              child: const Text('공유'),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('test.actions')), findsOneWidget);
      final share = tester.getRect(find.byKey(const ValueKey('test.share')));
      final save = tester.getRect(find.byKey(const ValueKey('test.save')));
      expect(share.height, greaterThanOrEqualTo(48));
      if (scale > 1.3) {
        expect(share.width, 320 - 32);
        expect(share.top, lessThan(save.top));
      } else {
        // 1:1. 1:2면 보조 버튼 문구가 두 줄로 꺾였다(실기기 360dp).
        expect(share.width, closeTo(save.width, 0.5));
        expect(share.top, save.top);
      }
    });
  }

  testWidgets('BottomActionBar: 360dp에서 아이콘이 붙은 보조 버튼 문구가 한 줄이다', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        const SizedBox.shrink(),
        bottom: BottomActionBar(
          secondary: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.download_outlined),
            label: const Text('기기에 저장'),
          ),
          primary: FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.share_outlined),
            label: const Text('공유'),
          ),
        ),
      ),
    );
    final line = tester.getSize(find.text('공유')).height;
    expect(tester.getSize(find.text('기기에 저장')).height, line);
  });

  testWidgets('BottomActionBar: 버튼 하나면 가로를 가득 채운다', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        const SizedBox.shrink(),
        bottom: BottomActionBar(
          primary: FilledButton(
            key: const ValueKey('test.next'),
            onPressed: () {},
            child: const Text('미리보기 만들기'),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(const ValueKey('test.next'))).width, 328);
  });

  testWidgets('SectionHeader는 제목·개수·동작을 보여주고 heading이다', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        SectionHeader(
          title: '레슨 기록',
          count: 2,
          identifier: 'test.section',
          trailing: TextButton(onPressed: () {}, child: const Text('최신순')),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('test.section')), findsOneWidget);
    expect(find.text('레슨 기록 2'), findsOneWidget);
    expect(find.text('최신순'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('레슨 기록 2')),
      isSemantics(isHeader: true),
    );
    handle.dispose();
  });

  testWidgets('InfoRow는 라벨과 값을 한 덩어리로 읽는다', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        const InfoRow(
          label: '실제 레슨 일시',
          value: '2026.11.04 (수) 오후 3:00',
          numeric: true,
          identifier: 'test.info',
        ),
      ),
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('test.info'))).label,
      '실제 레슨 일시, 2026.11.04 (수) 오후 3:00',
    );
    handle.dispose();
  });

  for (final dark in [false, true]) {
    testWidgets('StatusPill 톤별 색 (다크 $dark)', (tester) async {
      await tester.pumpWidget(
        _host(
          dark: dark,
          const Wrap(
            children: [
              StatusPill(label: '회원', identifier: 'p.neutral'),
              StatusPill(
                label: '진행',
                tone: StatusPillTone.primary,
                identifier: 'p.primary',
              ),
              StatusPill(
                label: '손목 주의',
                tone: StatusPillTone.warning,
                icon: Icons.info_outline,
                identifier: 'p.warning',
              ),
              StatusPill(
                label: '수평',
                tone: StatusPillTone.measure,
                identifier: 'p.measure',
              ),
            ],
          ),
        ),
      );
      final theme = dark ? AppTheme.dark : AppTheme.light;
      Color bg(String id) =>
          ((tester.widget<Container>(find.byKey(ValueKey(id)))).decoration!
                  as BoxDecoration)
              .color!;
      expect(bg('p.neutral'), theme.colorScheme.secondaryContainer);
      expect(bg('p.primary'), theme.colorScheme.primaryContainer);
      expect(bg('p.measure'), const Color(0xFF06B6D4));
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });
  }
}
