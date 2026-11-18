import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:bodymark/core/theme/app_tokens.dart';

/// 촬영 프레임 안 머리 상단선·발끝 기준선(측정 시안 점선).
///
/// 기준 사진이 없어도 매번 같은 위치에 머리와 발을 두게 하는 촬영 전용 안내다.
/// 격자([GridPainter])와 달리 사진·내보내기에는 남지 않는다.
class FrameReferenceLines extends StatelessWidget {
  static const id = 'capture.reference.lines';

  /// 프레임 높이 대비 위치.
  static const headFraction = 0.08;
  static const feetFraction = 0.94;

  const FrameReferenceLines({super.key});

  @override
  Widget build(BuildContext context) {
    final color = context.photoColors.measure;
    final labelStyle = context.texts.labelSmall?.copyWith(
      color: color,
      shadows: const [Shadow(blurRadius: 3, color: Color(0xCC000000))],
    );
    return Semantics(
      identifier: id,
      label: '머리 상단선과 발끝 기준선',
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final h = constraints.maxHeight;
            return Stack(
              key: const ValueKey(id),
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ReferenceLinePainter(
                      color: color.withValues(alpha: 0.85),
                      fractions: const [headFraction, feetFraction],
                    ),
                  ),
                ),
                Positioned(
                  left: AppSpacing.sp2,
                  top: h * headFraction + 2,
                  child: ExcludeSemantics(
                    child: Text('머리 상단선', style: labelStyle),
                  ),
                ),
                Positioned(
                  left: AppSpacing.sp2,
                  bottom: h * (1 - feetFraction) + 2,
                  child: ExcludeSemantics(
                    child: Text('발끝 기준선', style: labelStyle),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ReferenceLinePainter extends CustomPainter {
  final Color color;
  final List<double> fractions;

  const _ReferenceLinePainter({required this.color, required this.fractions});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    const dash = 6.0;
    const space = 5.0;
    for (final f in fractions) {
      final y = size.height * f;
      var x = 0.0;
      while (x < size.width) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + dash, size.width), y),
          paint,
        );
        x += dash + space;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ReferenceLinePainter old) =>
      old.color != color || old.fractions != fractions;
}
