import 'package:bodymark/core/widgets/media_orientation_lock.dart';
import 'package:bodymark/features/capture/providers/capture_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/videos/video_fakes.dart';

void main() {
  late FakeOrientationLock lock;
  late StateController<double?> aspect;
  final aspectState = StateProvider<double?>((ref) => null);

  setUp(() => lock = FakeOrientationLock());

  Future<void> pump(WidgetTester tester, {bool show = true}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [screenOrientationLockProvider.overrideWithValue(lock)],
        child: Consumer(
          builder: (context, ref, _) {
            aspect = ref.read(aspectState.notifier);
            return show
                ? MediaOrientationLock(
                    aspectRatio: ref.watch(aspectState),
                    child: const SizedBox(),
                  )
                : const SizedBox();
          },
        ),
      ),
    );
  }

  testWidgets('비율을 모르면 화면 방향을 건드리지 않는다', (tester) async {
    await pump(tester);
    expect(lock.locks, 0);
    expect(lock.restores, 0);
  });

  testWidgets('세로 미디어는 세로로 고정하고 떠나면 되돌린다', (tester) async {
    await pump(tester);
    aspect.state = 3 / 4;
    await tester.pump();
    expect(lock.locks, 1);
    // 같은 방향이면 다시 부르지 않는다.
    aspect.state = 9 / 16;
    await tester.pump();
    expect(lock.locks, 1);
    await pump(tester, show: false);
    expect(lock.restores, 1);
  });

  testWidgets('가로 미디어는 회전을 허용하고 세로로 바뀌면 고정한다', (tester) async {
    await pump(tester);
    aspect.state = 16 / 9;
    await tester.pump();
    expect(lock.restores, 1);
    expect(lock.locks, 0);
    aspect.state = 3 / 4;
    await tester.pump();
    expect(lock.locks, 1);
  });

  test('크기를 모르면 비율도 모른다', () {
    expect(MediaOrientationLock.aspectFromSize(0, 100), isNull);
    expect(MediaOrientationLock.aspectFromSize(300, 400), 0.75);
  });
}
