import 'dart:async';

import 'package:body_frame/core/services/settings_save_queue.dart';
import 'package:flutter_test/flutter_test.dart';

/// 설정 저장 큐 테스트.
///
/// 저장 순서가 뒤집히면 마지막 선택이 유실되고, 실패하면 사용자가 모르는 채
/// 이전 값이 남는다. 실제 시간에 의존하지 않고 Completer로 완료를 직접 제어해
/// 결정론적으로 검증한다.
void main() {
  test('저장 요청은 호출 순서대로 반영된다', () async {
    final written = <int>[];
    final queue = SettingsSaveQueue<int>((value) async => written.add(value));
    addTearDown(queue.dispose);

    await queue.save(1);
    await queue.save(2);
    await queue.save(3);

    expect(written, [1, 2, 3]);
    expect(queue.state.status, SettingsSaveStatus.success);
  });

  test('진행 중인 저장이 있으면 도착한 요청은 최신 값으로 합쳐진다', () async {
    final written = <int>[];
    final firstStarted = Completer<void>();
    final gate = Completer<void>();
    var callCount = 0;

    final queue = SettingsSaveQueue<int>((value) async {
      callCount += 1;
      if (callCount == 1) {
        firstStarted.complete();
        await gate.future;
      }
      written.add(value);
    });
    addTearDown(queue.dispose);

    final first = queue.save(1);
    await firstStarted.future;
    // 첫 저장이 진행 중일 때 세 값을 더 보낸다. 드래그 중 중간값이 모두
    // 저장되면 불필요한 쓰기가 쌓이고 순서도 어긋난다.
    final merged = <Future<SettingsSaveState>>[
      queue.save(2),
      queue.save(3),
      queue.save(4),
    ];
    gate.complete();
    await Future.wait<void>([first, ...merged]);

    // 첫 저장은 그대로 끝나고, 나머지는 최신 값 하나로 합쳐진다.
    expect(written, [1, 4]);
  });

  test('느린 저장이 끝나도 뒤 요청이 먼저 기록되지 않는다', () async {
    // 첫 저장을 오래 붙들어 둔 뒤 두 번째·세 번째를 보낸다. 직렬화되지 않으면
    // 뒤 요청이 먼저 끝나 최종 영속 값이 오래된 값으로 남는다.
    final written = <int>[];
    final slowGate = Completer<void>();
    var callCount = 0;
    final queue = SettingsSaveQueue<int>((value) async {
      callCount += 1;
      if (callCount == 1) await slowGate.future;
      written.add(value);
    });
    addTearDown(queue.dispose);

    final first = queue.save(1);
    await Future<void>.delayed(Duration.zero);
    final rest = <Future<SettingsSaveState>>[queue.save(2), queue.save(3)];
    slowGate.complete();
    await Future.wait<void>([first, ...rest]);

    expect(written, [1, 3]);
    expect(queue.state.status, SettingsSaveStatus.success);
    expect(queue.state.lastAttempted, 3);
  });

  test('저장 실패는 예외 대신 상태로 알리고 마지막 값을 남긴다', () async {
    final queue = SettingsSaveQueue<int>((value) async {
      throw StateError('저장 실패(테스트)');
    });
    addTearDown(queue.dispose);

    final result = await queue.save(7);

    expect(result.isFailure, isTrue);
    expect(queue.state.isFailure, isTrue);
    // 실패해도 마지막 선택 의도를 재시도에 쓸 수 있게 남는다.
    expect(queue.state.lastAttempted, 7);
    expect(queue.state.canRetry, isTrue);
    expect(queue.state.error, isStateError);
  });

  test('재시도는 마지막으로 요청한 값을 다시 저장한다', () async {
    final written = <int>[];
    var shouldFail = true;
    final queue = SettingsSaveQueue<int>((value) async {
      if (shouldFail) throw StateError('저장 실패(테스트)');
      written.add(value);
    });
    addTearDown(queue.dispose);

    await queue.save(3);
    expect(written, isEmpty);

    shouldFail = false;
    final result = await queue.retry();

    expect(result.isFailure, isFalse);
    expect(written, [3]);
  });

  test('초기화는 대기 중인 저장 뒤에 순서대로 수행된다', () async {
    final order = <String>[];
    final queue = SettingsSaveQueue<int>(
      (value) async => order.add('save$value'),
      reset: () async => order.add('reset'),
    );
    addTearDown(queue.dispose);

    await queue.save(1);
    await queue.resetToDefault();

    expect(order, ['save1', 'reset']);
    expect(queue.state.status, SettingsSaveStatus.success);
  });

  test('초기화 동작이 없으면 resetToDefault은 아무것도 하지 않는다', () async {
    final queue = SettingsSaveQueue<int>((value) async {});
    addTearDown(queue.dispose);

    final result = await queue.resetToDefault();

    expect(result.status, SettingsSaveStatus.idle);
  });

  test('실패한 저장이 걸린 뒤에도 다음 요청은 정상 처리된다', () async {
    final written = <int>[];
    var callCount = 0;
    final queue = SettingsSaveQueue<int>((value) async {
      callCount += 1;
      if (callCount == 1) throw StateError('저장 실패(테스트)');
      written.add(value);
    });
    addTearDown(queue.dispose);

    await queue.save(1);
    await queue.save(2);

    expect(written, [2]);
    expect(queue.state.status, SettingsSaveStatus.success);
  });
  for (final firstFails in [false, true]) {
    for (final lastFails in [false, true]) {
      test('후속 저장 중 진행 상태 유지: 이전 실패 $firstFails, 마지막 실패 $lastFails', () async {
        final firstGate = Completer<void>();
        final lastGate = Completer<void>();
        final lastStarted = Completer<void>();
        final statuses = <SettingsSaveStatus>[];
        final queue = SettingsSaveQueue<int>((value) async {
          if (value == 1) {
            await firstGate.future;
            if (firstFails) throw StateError('이전 요청 실패');
          } else {
            lastStarted.complete();
            await lastGate.future;
            if (lastFails) throw StateError('마지막 요청 실패');
          }
        });
        addTearDown(queue.dispose);
        queue.addListener(
          (state) => statuses.add(state.status),
          fireImmediately: false,
        );
        final first = queue.save(1);
        final merged = queue.save(2);
        final last = queue.save(3);
        firstGate.complete();
        final firstResult = await first;
        await lastStarted.future;
        final statusWhileSaving = queue.state;
        final intermediateStatuses = List.of(statuses);
        lastGate.complete();
        await Future.wait([merged, last]);
        expect(firstResult.isFailure, firstFails);
        expect(statusWhileSaving.isSaving, isTrue);
        expect(statusWhileSaving.lastAttempted, 3);
        expect(statusWhileSaving.canRetry, isFalse);
        expect(intermediateStatuses, everyElement(SettingsSaveStatus.saving));
        expect(
          queue.state.status,
          lastFails ? SettingsSaveStatus.failure : SettingsSaveStatus.success,
        );
        expect(queue.state.lastAttempted, 3);
        expect(queue.state.canRetry, lastFails);
      });
    }
  }
}
