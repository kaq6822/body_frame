import 'package:flutter/material.dart';

import '../../../core/models/models.dart';

/// 촬영 화면과 동일한 규칙으로 그리는 정렬용 격자 오버레이.
///
/// 두 사진 위에 동일한 좌표/크기로 표시되어야 하므로, 컨테이너 크기를
/// 기준으로 한 상대 좌표(중앙 기준 대칭)만 사용한다. 확대/이동 값과는
/// 무관하게 항상 화면(컨테이너) 좌표에 고정된다.
class CompareGridOverlay extends StatelessWidget {
  final GridSettings settings;

  /// 예: 'compare.before.grid.overlay'. 검사와 테스트가 격자 상태를
  /// 확인할 수 있도록 별도 식별자를 부여한다.
  final String semanticsIdentifier;

  const CompareGridOverlay({
    super.key,
    required this.settings,
    required this.semanticsIdentifier,
  });

  @override
  Widget build(BuildContext context) {
    if (!settings.visible) return const SizedBox.shrink();
    final opacityPercent = (settings.opacity.clamp(0.0, 1.0) * 100).round();
    return Semantics(
      identifier: semanticsIdentifier,
      label: '체형 정렬 격자',
      value: '표시됨, 투명도 $opacityPercent%',
      child: IgnorePointer(
        child: CustomPaint(
          size: Size.infinite,
          painter: _GridPainter(settings),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final GridSettings settings;

  const _GridPainter(this.settings);

  @override
  void paint(Canvas canvas, Size size) {
    final spacing = settings.spacing <= 0 ? 40.0 : settings.spacing;
    final opacity = settings.opacity.clamp(0.0, 1.0);
    final color = Color(settings.colorValue).withValues(alpha: opacity);
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = settings.lineWidth <= 0 ? 1.0 : settings.lineWidth;

    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // 중앙 세로 기준선 + 좌우 대칭 세로선.
    for (double x = centerX; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
      final mirrored = centerX - (x - centerX);
      if (mirrored >= 0 && mirrored != x) {
        canvas.drawLine(
            Offset(mirrored, 0), Offset(mirrored, size.height), linePaint);
      }
    }

    // 일정 간격 가로선(중앙 가로 기준선 포함).
    for (double y = centerY; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
      final mirrored = centerY - (y - centerY);
      if (mirrored >= 0 && mirrored != y) {
        canvas.drawLine(
            Offset(0, mirrored), Offset(size.width, mirrored), linePaint);
      }
    }

    // 화면 중앙 기준점.
    final centerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(centerX, centerY),
      (settings.lineWidth <= 0 ? 1.0 : settings.lineWidth) * 2 + 2,
      centerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.settings != settings;
}
