import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:bodymark/core/theme/app_tokens.dart';
import '../level/level_meter.dart';

/// 촬영 프레임 가운데에 겹치는 수평계.
///
/// 가로선은 기기 회전(roll)만큼 반대로 기울어 실제 수평을 가리키고, 양 끝의
/// 고정 눈금과 겹치면 수평이다. 가운데 원 안의 점은 앞뒤 기울기(pitch)를 위아래로
/// 보여준다. 색: 흰 점선(기울어짐) → 앰버(거의 수평) → 측정 시안 실선(수평).
/// 미리보기 위 표시일 뿐 저장되는 원본에는 남지 않는다.
class LevelIndicator extends StatelessWidget {
  static const id = 'capture.level';

  final LevelReading reading;

  const LevelIndicator({super.key, required this.reading});

  @override
  Widget build(BuildContext context) {
    final photo = context.photoColors;
    if (!reading.isUpright) {
      // 눕힌 자세에서는 roll이 의미가 없어 선을 그리지 않고 안내만 한다.
      return Semantics(
        identifier: id,
        label: '수평계',
        value: reading.semanticsValue,
        child: IgnorePointer(
          child: Center(
            key: const ValueKey('capture.level.upright.hint'),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sp3,
                vertical: AppSpacing.sp2,
              ),
              decoration: BoxDecoration(
                color: photo.hudSurface,
                borderRadius: AppRadius.fullAll,
                border: Border.all(color: photo.hudOutline),
              ),
              child: ExcludeSemantics(
                child: Text(
                  '휴대폰을 세워 주세요',
                  style: context.texts.labelLarge?.copyWith(
                    color: photo.onChrome,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    final color = switch (reading.status) {
      LevelStatus.locked => photo.measure,
      LevelStatus.near => photo.warning,
      LevelStatus.tilted || LevelStatus.notUpright => photo.onChrome,
    };
    return Semantics(
      identifier: id,
      label: '수평계',
      value: reading.semanticsValue,
      liveRegion: false,
      child: IgnorePointer(
        child: CustomPaint(
          key: const ValueKey(id),
          size: Size.infinite,
          painter: LevelPainter(
            roll: reading.roll,
            pitch: reading.pitch,
            color: color,
            dashed: reading.status == LevelStatus.tilted,
            tickColor: photo.onChrome.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}

/// [LevelIndicator]의 페인터. 테스트에서 상태별 속성을 확인한다.
class LevelPainter extends CustomPainter {
  final double roll;
  final double pitch;
  final Color color;
  final bool dashed;
  final Color tickColor;

  const LevelPainter({
    required this.roll,
    required this.pitch,
    required this.color,
    required this.dashed,
    required this.tickColor,
  });

  /// pitch 1도당 점 이동(논리 픽셀)과 최대 이동.
  static const pitchScale = 3.0;
  static const maxPitchOffset = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = size.center(Offset.zero);
    final half = math.min(size.width * 0.22, 96.0);
    const tick = 12.0;
    const gap = 6.0;

    final tickPaint = Paint()
      ..color = tickColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    // 고정 눈금: 기기가 수평이면 회전선과 일직선이 된다.
    canvas.drawLine(
      center + Offset(-half - gap - tick, 0),
      center + Offset(-half - gap, 0),
      tickPaint,
    );
    canvas.drawLine(
      center + Offset(half + gap, 0),
      center + Offset(half + gap + tick, 0),
      tickPaint,
    );

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final angle = -roll.clamp(-45.0, 45.0) * math.pi / 180;
    final dir = Offset(math.cos(angle), math.sin(angle));
    final start = center - dir * half;
    final end = center + dir * half;
    if (dashed) {
      _dashedLine(canvas, start, end, linePaint);
    } else {
      canvas.drawLine(start, end, linePaint);
    }

    // 앞뒤 기울기: 고정 원 안에서 점이 위아래로 움직인다.
    final ringPaint = Paint()
      ..color = tickColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, 10, ringPaint);
    final dy = (pitch * pitchScale).clamp(-maxPitchOffset, maxPitchOffset);
    canvas.drawCircle(center + Offset(0, dy), 4, Paint()..color = color);
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 8.0;
    const space = 6.0;
    final total = (b - a).distance;
    final unit = (b - a) / total;
    var t = 0.0;
    while (t < total) {
      final e = math.min(t + dash, total);
      canvas.drawLine(a + unit * t, a + unit * e, paint);
      t += dash + space;
    }
  }

  @override
  bool shouldRepaint(covariant LevelPainter old) =>
      old.roll != roll ||
      old.pitch != pitch ||
      old.color != color ||
      old.dashed != dashed ||
      old.tickColor != tickColor;
}
