import 'package:bodymark/core/theme/app_theme.dart';
import 'package:bodymark/core/widgets/app_confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Future<bool>> _open(
  WidgetTester tester,
  Future<bool> Function(BuildContext) show, {
  double scale = 1,
}) async {
  late Future<bool> result;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => result = show(context),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('확인은 true, 취소는 false를 돌려준다', (tester) async {
    var result = await _open(
      tester,
      (c) => showAppConfirm(c, title: '레슨을 삭제할까요?', confirmLabel: '삭제'),
    );
    expect(find.byKey(const ValueKey('common.confirm.dialog')), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('common.confirm.accept.button')),
    );
    await tester.pumpAndSettle();
    expect(await result, isTrue);

    result = await _open(tester, (c) => showAppConfirm(c, title: '나갈까요?'));
    await tester.tap(
      find.byKey(const ValueKey('common.confirm.cancel.button')),
    );
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  testWidgets('바깥을 눌러 닫으면 false다', (tester) async {
    final result = await _open(tester, (c) => showAppConfirm(c, title: '?'));
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  testWidgets('destructive는 오류 색 확인 버튼과 범위 요약·경고를 보여준다', (tester) async {
    await _open(
      tester,
      (c) => showAppConfirm(
        c,
        title: '이 레슨 기록을 삭제할까요?',
        body: '11.04 오후 3:00 레슨',
        summary: const ['사진 4장, 메모 1개가 함께 삭제돼요'],
        warning: '삭제 후 되돌릴 수 없어요.',
        confirmLabel: '삭제',
        destructive: true,
        dialogKey: 'x.dialog',
        cancelKey: 'x.cancel',
        confirmKey: 'x.confirm',
      ),
    );
    expect(find.byKey(const ValueKey('x.dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('x.dialog.summary')), findsOneWidget);
    expect(find.text('사진 4장, 메모 1개가 함께 삭제돼요'), findsOneWidget);
    expect(find.text('삭제 후 되돌릴 수 없어요.'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('x.confirm')),
    );
    final bg = button.style!.backgroundColor!.resolve({});
    expect(bg, AppTheme.light.colorScheme.error);
  });

  testWidgets('preferCancel은 취소를 주요 버튼으로 위에 쌓는다', (tester) async {
    await _open(
      tester,
      (c) => showAppConfirm(
        c,
        title: '작성한 내용을 버릴까요?',
        confirmLabel: '변경 내용 버리기',
        cancelLabel: '계속 작성',
        destructive: true,
        preferCancel: true,
      ),
    );
    final cancel = find.byKey(const ValueKey('common.confirm.cancel.button'));
    final accept = find.byKey(const ValueKey('common.confirm.accept.button'));
    expect(tester.widget(cancel), isA<FilledButton>());
    expect(tester.widget(accept), isA<OutlinedButton>());
    expect(
      tester.getTopLeft(cancel).dy,
      lessThan(tester.getTopLeft(accept).dy),
    );
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('320dp·2배 글꼴에서도 넘치지 않고 버튼을 세로로 쌓는다', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _open(
      tester,
      (c) => showAppConfirm(
        c,
        title: '김서연 회원을 삭제할까요?',
        body: '이 회원의 모든 레슨 일지와 사진도 함께 삭제돼요.',
        summary: const ['레슨 12개', '사진 48장'],
        warning: '삭제 후 되돌릴 수 없어요.',
        confirmLabel: '삭제',
        destructive: true,
      ),
      scale: 2,
    );
    expect(tester.takeException(), isNull);
    final cancel = find.byKey(const ValueKey('common.confirm.cancel.button'));
    final accept = find.byKey(const ValueKey('common.confirm.accept.button'));
    await tester.ensureVisible(cancel);
    expect(tester.getTopLeft(accept).dx, tester.getTopLeft(cancel).dx);
  });
}
