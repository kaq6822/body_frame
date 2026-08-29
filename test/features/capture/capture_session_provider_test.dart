import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/features/capture/providers/capture_session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer buildContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // autoDispose 세션이 구독 없이 즉시 폐기되지 않게 붙잡아 둔다.
    final subscription = container.listen(captureSessionProvider, (_, _) {});
    addTearDown(subscription.close);
    return container;
  }

  test('처음 찍는 단계는 밀려나는 임시 파일이 없다', () {
    final notifier = buildContainer().read(captureSessionProvider.notifier);

    expect(
      notifier.captureCurrent(
        '/tmp/front.jpg',
        gridSettings: GridSettings.defaults,
      ),
      isNull,
    );
  });

  test('이미 찍은 단계를 다시 찍으면 밀려난 임시 파일 경로를 돌려준다', () {
    final container = buildContainer();
    final notifier = container.read(captureSessionProvider.notifier);

    notifier.captureCurrent('/tmp/front-1.jpg');
    // 진행 칩으로 찍은 단계로 되돌아가 다시 셔터를 누르는 흐름.
    notifier.goTo(0);
    final replaced = notifier.captureCurrent('/tmp/front-2.jpg');

    // 밀려난 파일은 세션에 남지 않으므로 호출부가 지워야 한다.
    expect(replaced, '/tmp/front-1.jpg');
    expect(
      container.read(captureSessionProvider).shots[0].imagePath,
      '/tmp/front-2.jpg',
    );
    expect(
      container
          .read(captureSessionProvider)
          .capturedShots
          .map((shot) => shot.imagePath),
      ['/tmp/front-2.jpg'],
    );
  });

  test('같은 경로로 다시 기록하면 지울 것이 없다', () {
    final notifier = buildContainer().read(captureSessionProvider.notifier);

    notifier.captureCurrent('/tmp/front.jpg');
    notifier.goTo(0);

    expect(notifier.captureCurrent('/tmp/front.jpg'), isNull);
  });

  test('라벨과 메모는 빈 문자열을 넣으면 지워진다', () {
    final container = buildContainer();
    final notifier = container.read(captureSessionProvider.notifier);

    notifier.setLabel('  동생  ');
    notifier.setMemo('체중 감량 시작');
    expect(container.read(captureSessionProvider).label, '동생');
    expect(container.read(captureSessionProvider).memo, '체중 감량 시작');

    notifier.setLabel('   ');
    notifier.setMemo('');
    expect(container.read(captureSessionProvider).label, isNull);
    expect(container.read(captureSessionProvider).memo, isNull);
  });
}
