import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/models.dart';

/// 촬영 화면과 비교 화면이 함께 사용하는 정렬 보조 격자 페인터.
///
/// 구성 요소: 중앙 세로 기준선(강조), 일정 간격 세로/가로선, 중앙 기준점,
/// 좌우 대칭 확인용 기준선(점선). 오버레이 전용이며 원본 이미지에는
/// 합성하지 않는다.
class GridPainter extends CustomPainter {
  final GridSettings settings;

  const GridPainter(this.settings);

  @override
  void paint(Canvas canvas, Size size) {
    if (!settings.visible || size.width <= 0 || size.height <= 0) return;

    final color = Color(
      settings.colorValue,
    ).withValues(alpha: settings.opacity.clamp(0.0, 1.0));
    final lineWidth = settings.lineWidth <= 0 ? 1.0 : settings.lineWidth;
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = lineWidth
      ..style = PaintingStyle.stroke;
    final centerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final spacing = settings.spacing <= 0 ? 40.0 : settings.spacing;

    // 일정 간격 세로선(중앙 기준 좌우 대칭 배치).
    for (
      var dx = spacing;
      centerX + dx <= size.width || centerX - dx >= 0;
      dx += spacing
    ) {
      if (centerX + dx <= size.width) {
        canvas.drawLine(
          Offset(centerX + dx, 0),
          Offset(centerX + dx, size.height),
          linePaint,
        );
      }
      if (centerX - dx >= 0) {
        canvas.drawLine(
          Offset(centerX - dx, 0),
          Offset(centerX - dx, size.height),
          linePaint,
        );
      }
    }

    // 일정 간격 가로선(중앙 기준 상하 대칭 배치).
    for (
      var dy = spacing;
      centerY + dy <= size.height || centerY - dy >= 0;
      dy += spacing
    ) {
      if (centerY + dy <= size.height) {
        canvas.drawLine(
          Offset(0, centerY + dy),
          Offset(size.width, centerY + dy),
          linePaint,
        );
      }
      if (centerY - dy >= 0) {
        canvas.drawLine(
          Offset(0, centerY - dy),
          Offset(size.width, centerY - dy),
          linePaint,
        );
      }
    }

    // 좌우 대칭 확인용 기준선(화면 1/4, 3/4 지점, 점선으로 중앙선과 구분).
    _drawDashedVerticalLine(canvas, size.width * 0.25, size.height, linePaint);
    _drawDashedVerticalLine(canvas, size.width * 0.75, size.height, linePaint);

    // 중앙 세로 기준선(강조, 다른 선 위에 그려 항상 보이게 함).
    final emphasisPaint = Paint()
      ..color = color
      ..strokeWidth = lineWidth * 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(centerX, 0),
      Offset(centerX, size.height),
      emphasisPaint,
    );

    // 중앙 기준점.
    canvas.drawCircle(
      Offset(centerX, centerY),
      math.max(lineWidth * 2, 3),
      centerPaint,
    );
  }

  void _drawDashedVerticalLine(
    Canvas canvas,
    double x,
    double height,
    Paint paint,
  ) {
    const dashLength = 8.0;
    const gapLength = 6.0;
    var y = 0.0;
    while (y < height) {
      final end = math.min(y + dashLength, height);
      canvas.drawLine(Offset(x, y), Offset(x, end), paint);
      y += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) =>
      oldDelegate.settings != settings;
}
