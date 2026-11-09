import 'dart:async';

import 'package:bodymark/features/capture/level/level_meter.dart';
import 'package:flutter_test/flutter_test.dart';

/// 수평계 계산(기울기·상태 기계·필터)을 가짜 샘플로 결정론적으로 검증한다.
void main() {
  const g = 9.81;

  group('tiltFromAcceleration', () {
    test('세로로 똑바로 세우면 roll·pitch가 0이다', () {
      final t = tiltFromAcceleration(0, g, 0);
      expect(t.roll, closeTo(0, 1e-9));
      expect(t.pitch, closeTo(0, 1e-9));
    });

    test('윗부분이 오른쪽(시계 방향)으로 기울면 roll이 양수다', () {
      // 시계 방향 10°: x = -g·sin, y = g·cos.
      final t = tiltFromAcceleration(-g * 0.17364817766, g * 0.98480775301, 0);
      expect(t.roll, closeTo(10, 0.01));
      expect(t.pitch, closeTo(0, 0.01));
    });

    test('화면이 위를 향하게 뒤로 젖히면 pitch가 양수다', () {
      final t = tiltFromAcceleration(0, g * 0.98480775301, g * 0.17364817766);
      expect(t.pitch, closeTo(10, 0.01));
      expect(t.roll, closeTo(0, 0.01));
    });

    test('중력 성분이 없으면 0으로 본다', () {
      final t = tiltFromAcceleration(0, 0, 0);
      expect(t.roll, 0);
      expect(t.pitch, 0);
    });
  });

  group('nextLevelStatus', () {
    test('±1° 이내면 잠기고 ±3° 이내면 거의 수평이다', () {
      expect(nextLevelStatus(LevelStatus.tilted, 0.9), LevelStatus.locked);
      expect(nextLevelStatus(LevelStatus.tilted, 1.2), LevelStatus.near);
      expect(nextLevelStatus(LevelStatus.tilted, -2.9), LevelStatus.near);
      expect(nextLevelStatus(LevelStatus.near, 3.5), LevelStatus.tilted);
    });

    test('잠긴 뒤에는 ±1.5°를 넘어야 풀린다(히스테리시스)', () {
      expect(nextLevelStatus(LevelStatus.locked, 1.4), LevelStatus.locked);
      expect(nextLevelStatus(LevelStatus.locked, -1.5), LevelStatus.locked);
      expect(nextLevelStatus(LevelStatus.locked, 1.6), LevelStatus.near);
      expect(nextLevelStatus(LevelStatus.near, 1.4), LevelStatus.near);
    });
  });

  group('tiltForScreen', () {
    const s10 = 0.17364817766, c10 = 0.98480775301;

    test('세로는 tiltFromAcceleration과 같다', () {
      final t = tiltForScreen(-g * s10, g * c10, 0, ScreenFrame.portrait)!;
      expect(t.roll, closeTo(10, 0.01));
    });

    test('가로(기기 위쪽이 왼쪽, x<0)로 수평이면 roll 0이다', () {
      final t = tiltForScreen(-g, 0, 0, ScreenFrame.landscape)!;
      expect(t.roll, closeTo(0, 1e-9));
      expect(t.pitch, closeTo(0, 1e-9));
    });

    test('가로(기기 위쪽이 오른쪽, x>0)로 수평이면 roll 0이다', () {
      final t = tiltForScreen(g, 0, 0, ScreenFrame.landscape)!;
      expect(t.roll, closeTo(0, 1e-9));
    });

    test('가로에서 화면 기준 10° 기울면 roll이 ±10°다', () {
      // 위쪽이 왼쪽인 가로에서 화면을 시계 방향으로 10° 돌림.
      final left = tiltForScreen(-g * c10, -g * s10, 0, ScreenFrame.landscape)!;
      expect(left.roll, closeTo(10, 0.01));
      final right = tiltForScreen(g * c10, g * s10, 0, ScreenFrame.landscape)!;
      expect(right.roll, closeTo(10, 0.01));
    });

    test('거꾸로 든 세로는 판정하지 않는다(null → notUpright)', () {
      final t = tiltForScreen(0, -g, 0, ScreenFrame.portrait);
      expect(t, isNull);
      expect(levelStatusFor(LevelStatus.locked, t), LevelStatus.notUpright);
    });
  });

  group('세워 든 자세 판정', () {
    test('|pitch|가 45°를 넘으면 세워 든 자세가 아니다', () {
      expect(isUpright(const Tilt(0, 10)), isTrue);
      expect(isUpright(const Tilt(0, -45)), isTrue);
      expect(isUpright(const Tilt(40, 80)), isFalse);
      expect(isUpright(const Tilt(0, -60)), isFalse);
    });

    test('눕힌 자세는 roll과 무관하게 notUpright이고 잠금을 끊는다', () {
      expect(
        levelStatusFor(LevelStatus.locked, const Tilt(0.2, 85)),
        LevelStatus.notUpright,
      );
      expect(
        levelStatusFor(LevelStatus.notUpright, const Tilt(0.5, 0.3)),
        LevelStatus.locked,
      );
      expect(
        levelStatusFor(LevelStatus.tilted, const Tilt(2, 0)),
        LevelStatus.near,
      );
    });

    test('스크린리더는 세워 달라는 안내만 읽는다', () {
      expect(
        const LevelReading(
          roll: 40,
          pitch: 85,
          status: LevelStatus.notUpright,
        ).semanticsValue,
        '휴대폰을 세워 주세요',
      );
    });
  });

  group('levelReadings', () {
    AccelerationSample rolled(double degrees) {
      final r = degrees * 3.141592653589793 / 180;
      return AccelerationSample(-g * _sin(r), g * _cos(r), 0);
    }

    test('잠금 진입 때만 한 번 피드백하고 경계 흔들림에는 반복하지 않는다', () async {
      var locks = 0;
      final readings = await levelReadings(
        Stream.fromIterable([
          rolled(5),
          rolled(0.5),
          rolled(1.3),
          rolled(0.8),
          rolled(1.4),
          rolled(4),
          rolled(0),
        ]),
        smoothing: 1, // 필터 없이 상태 기계만 확인한다.
        onLock: () => locks++,
      ).toList();

      expect(readings.map((r) => r.status), [
        LevelStatus.tilted,
        LevelStatus.locked,
        LevelStatus.locked,
        LevelStatus.locked,
        LevelStatus.locked,
        LevelStatus.tilted,
        LevelStatus.locked,
      ]);
      expect(locks, 2);
    });

    test('책상에 눕히면 잠금·피드백 없이 notUpright가 되고, 다시 세우면 새로 잠긴다', () async {
      var locks = 0;
      final readings = await levelReadings(
        Stream.fromIterable([
          rolled(0),
          // 화면이 위를 향하게 눕힘: z가 지배적.
          const AccelerationSample(0.3, 0.2, g),
          const AccelerationSample(-0.1, 0.0, g),
          rolled(0.2),
        ]),
        smoothing: 1,
        onLock: () => locks++,
      ).toList();

      expect(readings.map((r) => r.status), [
        LevelStatus.locked,
        LevelStatus.notUpright,
        LevelStatus.notUpright,
        LevelStatus.locked,
      ]);
      expect(locks, 2);
    });

    test('저역 통과 필터가 튀는 샘플을 완화한다', () async {
      final readings = await levelReadings(
        Stream.fromIterable([rolled(0), rolled(20)]),
        smoothing: 0.2,
      ).toList();
      expect(readings.last.roll, lessThan(5));
      expect(readings.last.roll, greaterThan(0));
    });

    test('판독값이 0.1° 미만으로만 바뀌면 내보내지 않는다', () async {
      final readings = await levelReadings(
        Stream.fromIterable([rolled(2), rolled(2.02), rolled(2.05)]),
        smoothing: 1,
      ).toList();
      expect(readings, hasLength(1));
    });

    test('센서 오류는 스트림 오류로 전달된다', () async {
      final controller = StreamController<AccelerationSample>();
      final expectation = expectLater(
        levelReadings(controller.stream).toList(),
        throwsStateError,
      );
      controller.addError(StateError('no sensor'));
      await controller.close();
      await expectation;
    });
  });

  test('스크린리더 값은 방향과 정수 각도를 읽는다', () {
    expect(
      const LevelReading(
        roll: -2.2,
        pitch: 1.4,
        status: LevelStatus.near,
      ).semanticsValue,
      '기울기 좌 2도, 앞뒤 1도, 거의 수평',
    );
    expect(
      const LevelReading(
        roll: 0.3,
        pitch: -0.2,
        status: LevelStatus.locked,
      ).semanticsValue,
      '기울기 0도, 앞뒤 0도, 수평',
    );
    expect(
      const LevelReading(
        roll: 5.6,
        pitch: 0,
        status: LevelStatus.tilted,
      ).semanticsValue,
      '기울기 우 6도, 앞뒤 0도',
    );
  });
}

double _sin(double r) => _taylor(r, true);
double _cos(double r) => _taylor(r, false);

double _taylor(double x, bool sine) {
  // dart:math 대신 쓰지 않아도 되지만, 기대값 계산을 구현과 독립시킨다.
  var term = sine ? x : 1.0;
  var sum = term;
  for (var n = 1; n < 12; n++) {
    final k = sine ? 2 * n : 2 * n - 1;
    term *= -x * x / (k * (k + 1));
    sum += term;
  }
  return sum;
}
