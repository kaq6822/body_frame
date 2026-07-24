import 'package:flutter_test/flutter_test.dart';

/// sqflite FFI(백그라운드 isolate)를 사용하는 Riverpod FutureProvider는
/// `pumpAndSettle()`만으로는 결과를 기다리지 못하고 무한 대기(timeout)에
/// 빠진다. isolate 간 메시지 전달에는 실제 시간 경과가 필요하므로, 이
/// 헬퍼는 실제 `Future.delayed`와 `tester.pump`를 번갈아 호출하며
/// [predicate]가 참이 될 때까지 기다린다. 반드시 `tester.runAsync(...)`
/// 내부에서 호출한다.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  int maxTries = 60,
  Duration step = const Duration(milliseconds: 50),
}) async {
  for (var i = 0; i < maxTries; i++) {
    if (predicate()) return;
    await Future.delayed(step);
    await tester.pump(step);
  }
}
