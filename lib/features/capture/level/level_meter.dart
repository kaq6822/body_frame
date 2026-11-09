import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// 가속도계 한 샘플(m/s², 중력 포함). 좌표는 sensors_plus 규약을 따른다.
///
/// 세로로 세워 사용자를 마주 볼 때 x는 화면 오른쪽, y는 화면 위, z는 화면에서
/// 사용자 쪽이다. 정지 상태에서 위쪽(중력 반대) 성분이 양수로 나온다.
class AccelerationSample {
  final double x;
  final double y;
  final double z;

  const AccelerationSample(this.x, this.y, this.z);
}

/// 기기 기울기 센서 경계. 테스트에서는 가짜 스트림으로 교체한다.
abstract class LevelSensor {
  /// 샘플 스트림. 센서가 없거나 막히면 에러로 끝난다.
  Stream<AccelerationSample> samples();
}

/// sensors_plus 가속도계 구현.
class SensorsPlusLevelSensor implements LevelSensor {
  /// 약 20Hz. 수평계 표시는 이보다 빠를 필요가 없고 배터리만 쓴다.
  static const samplingPeriod = Duration(milliseconds: 50);

  const SensorsPlusLevelSensor();

  @override
  Stream<AccelerationSample> samples() => accelerometerEventStream(
    samplingPeriod: samplingPeriod,
  ).map((e) => AccelerationSample(e.x, e.y, e.z));
}

/// 기울기(도). 세로(portrait) 촬영 기준.
class Tilt {
  /// 화면 평면 회전. 양수 = 기기 윗부분이 오른쪽으로 기움(시계 방향).
  final double roll;

  /// 앞뒤 기울기. 양수 = 화면이 위를 향하도록 뒤로 젖힘.
  final double pitch;

  const Tilt(this.roll, this.pitch);
}

/// 가속도 성분으로 세로 촬영 기준 기울기를 구한다. 순수 함수.
///
/// 중력 성분이 거의 0이면(자유 낙하·센서 이상) 0으로 본다.
Tilt tiltFromAcceleration(double x, double y, double z) {
  const toDegrees = 180 / math.pi;
  final planar = math.sqrt(x * x + y * y);
  if (planar < 1e-6 && z.abs() < 1e-6) return const Tilt(0, 0);
  final roll = math.atan2(-x, y) * toDegrees;
  final pitch = math.atan2(z, planar) * toDegrees;
  return Tilt(roll, pitch);
}

/// 지금 화면이 놓인 방향. 위젯의 [MediaQuery] 방향에서 정한다.
enum ScreenFrame { portrait, landscape }

/// 가속도를 **화면 기준** 기울기로 바꾼다. 순수 함수.
///
/// 센서 축은 기기에 고정돼 있어 [tiltFromAcceleration]의 roll은 세로 기준이다.
/// 가로 화면에서는 화면 위쪽이 기기의 ±x 방향이므로 기준을 ±90° 옮긴다. 어느
/// 쪽으로 눕혔는지는 x 부호로 구분한다(x < 0이면 기기 위쪽이 왼쪽 = +90°).
/// 세로 화면인데 거꾸로 든 경우(|roll| > 135°)는 화면이 뒤집히지 않아 지표가
/// 의미 없으므로 null을 돌려 숨기게 한다. pitch는 화면 회전과 무관하다.
Tilt? tiltForScreen(double x, double y, double z, ScreenFrame frame) {
  final raw = tiltFromAcceleration(x, y, z);
  switch (frame) {
    case ScreenFrame.portrait:
      if (raw.roll.abs() > 135) return null;
      return raw;
    case ScreenFrame.landscape:
      final reference = x < 0 ? 90.0 : -90.0;
      var roll = raw.roll - reference;
      if (roll > 180) roll -= 360;
      if (roll <= -180) roll += 360;
      return Tilt(roll, raw.pitch);
  }
}

/// 수평 상태.
enum LevelStatus {
  /// ±3° 밖.
  tilted,

  /// ±3° 이내(거의 수평).
  near,

  /// 수평 잠금. ±1° 이내로 들어오면 잠기고 ±1.5°를 넘어야 풀린다.
  locked,

  /// 세워 든 자세가 아니다(책상에 눕힘 등, |pitch| > 45°). 이때 roll은 의미가
  /// 없으므로 수평선·잠금을 보이지 않고 세워 달라는 안내만 한다.
  notUpright,
}

/// 수평 판정 임계값(도). 계획 #5.
class LevelThresholds {
  static const lock = 1.0;
  static const unlock = 1.5;
  static const near = 3.0;

  /// 이보다 앞뒤로 더 기울면 세워 든 자세로 보지 않는다.
  static const upright = 45.0;
}

/// 세로로 세워 든 자세인지. 순수 함수.
bool isUpright(Tilt tilt) => tilt.pitch.abs() <= LevelThresholds.upright;

/// 기울기 전체로 다음 상태를 정한다. 순수 함수.
///
/// 눕힌 자세면 [LevelStatus.notUpright]이고 잠금 이력도 끊긴다. 다시 세워 수평에
/// 들어오면 새 잠금으로 본다.
///
/// [tilt]가 null(거꾸로 든 세로 등 판정 불가)이어도 [LevelStatus.notUpright]다.
LevelStatus levelStatusFor(LevelStatus previous, Tilt? tilt) {
  if (tilt == null || !isUpright(tilt)) return LevelStatus.notUpright;
  return nextLevelStatus(previous, math.max(tilt.roll.abs(), tilt.pitch.abs()));
}

/// 이전 상태와 현재 편차로 다음 상태를 정한다. 순수 함수.
///
/// 잠금 해제에 더 넓은 임계값을 써서(히스테리시스) 경계에서 깜빡이지 않게 한다.
LevelStatus nextLevelStatus(LevelStatus previous, double deviation) {
  final d = deviation.abs();
  if (previous == LevelStatus.locked && d <= LevelThresholds.unlock) {
    return LevelStatus.locked;
  }
  if (d <= LevelThresholds.lock) return LevelStatus.locked;
  if (d <= LevelThresholds.near) return LevelStatus.near;
  return LevelStatus.tilted;
}

/// 화면에 넘기는 수평계 판독값.
class LevelReading {
  final double roll;
  final double pitch;
  final LevelStatus status;

  const LevelReading({
    required this.roll,
    required this.pitch,
    required this.status,
  });

  bool get isLocked => status == LevelStatus.locked;

  bool get isUpright => status != LevelStatus.notUpright;

  /// 스크린리더용 값. 예: "기울기 좌 2도, 앞뒤 1도".
  String get semanticsValue {
    if (status == LevelStatus.notUpright) return '휴대폰을 세워 주세요';
    final r = roll.round();
    final side = r == 0 ? '' : (r > 0 ? '우 ' : '좌 ');
    final suffix = switch (status) {
      LevelStatus.locked => ', 수평',
      LevelStatus.near => ', 거의 수평',
      LevelStatus.tilted || LevelStatus.notUpright => '',
    };
    return '기울기 $side${r.abs()}도, 앞뒤 ${pitch.round().abs()}도$suffix';
  }
}

/// 샘플 스트림을 저역 통과 필터와 상태 기계를 거친 판독값 스트림으로 바꾼다.
///
/// [smoothing]은 지수 이동 평균 계수(0~1, 작을수록 부드럽다). 잠금에 처음 들어갈
/// 때만 [onLock]을 한 번 부른다. 판독값을 바꾸지 않는 미세한 흔들림은 내보내지
/// 않아 화면 재빌드를 줄인다.
Stream<LevelReading> levelReadings(
  Stream<AccelerationSample> samples, {
  double smoothing = 0.2,
  ScreenFrame frame = ScreenFrame.portrait,
  void Function()? onLock,
}) {
  double? fx, fy, fz;
  var status = LevelStatus.tilted;
  LevelReading? last;
  return samples
      .map((s) {
        fx = fx == null ? s.x : fx! + smoothing * (s.x - fx!);
        fy = fy == null ? s.y : fy! + smoothing * (s.y - fy!);
        fz = fz == null ? s.z : fz! + smoothing * (s.z - fz!);
        final tilt = tiltForScreen(fx!, fy!, fz!, frame);
        final next = levelStatusFor(status, tilt);
        if (next == LevelStatus.locked && status != LevelStatus.locked) {
          onLock?.call();
        }
        status = next;
        return LevelReading(
          roll: tilt?.roll ?? 0,
          pitch: tilt?.pitch ?? 0,
          status: next,
        );
      })
      .where((reading) {
        final prev = last;
        final changed =
            prev == null ||
            prev.status != reading.status ||
            (prev.roll - reading.roll).abs() >= 0.1 ||
            (prev.pitch - reading.pitch).abs() >= 0.1;
        if (changed) last = reading;
        return changed;
      });
}

/// 기울기 센서. 테스트에서 가짜 구현으로 교체한다.
final levelSensorProvider = Provider<LevelSensor>(
  (ref) => const SensorsPlusLevelSensor(),
);

/// 잠금 진입 피드백. 테스트에서 호출 횟수를 센다.
final levelLockFeedbackProvider = Provider<void Function()>(
  (ref) =>
      () => unawaited(HapticFeedback.selectionClick()),
);
