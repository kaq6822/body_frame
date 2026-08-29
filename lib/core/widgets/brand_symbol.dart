import 'package:flutter/material.dart';

/// 브랜드 심벌의 표현 방식.
enum BrandSymbolStyle {
  /// 인물이 채워진 기본형. 워드마크·아이콘 자리에 쓴다.
  solid,

  /// 인물이 점선 외곽선인 변형. "이 프레임을 아직 채우지 않았다"는 뜻이므로
  /// 빈 상태에서만 쓴다.
  outlined,
}

/// Body Frame 브랜드 심벌.
///
/// 카메라 뷰파인더의 코너 브래킷 안에 인물 실루엣을 둔 형태다. "같은 프레임에
/// 몸을 다시 세운다"는 핵심 경험을 그대로 형상화한 것이라, 장식이 아니라 기능적
/// 의미가 있는 자리에만 놓는다.
///
/// 에셋 파일을 추가하지 않고 [CustomPainter]로 그린다. 색은 호출부가 정하며
/// 사진 위에서는 반드시 고정 흰색([AppPhotoColors.onChrome])을 넘긴다.
class BrandSymbol extends StatelessWidget {
  /// 심벌 한 변의 크기(정사각). 최소 20을 권장한다.
  final double size;

  /// 선·면 색. 사진 위에서는 고정 흰색을 넘긴다.
  final Color color;

  /// 인물 부분 색. null이면 [color]를 따른다. 빈 상태에서 브래킷과 인물의
  /// 위계를 나눌 때 쓴다.
  final Color? figureColor;

  final BrandSymbolStyle style;

  /// 접근성 라벨. 장식용이면 null로 두어 스크린 리더에서 제외한다.
  final String? semanticLabel;

  const BrandSymbol({
    super.key,
    this.size = 24,
    required this.color,
    this.figureColor,
    this.style = BrandSymbolStyle.solid,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final painter = CustomPaint(
      size: Size.square(size),
      painter: _BrandSymbolPainter(
        color: color,
        figureColor: figureColor ?? color,
        style: style,
      ),
    );

    if (semanticLabel == null) {
      return ExcludeSemantics(child: painter);
    }
    return Semantics(image: true, label: semanticLabel, child: painter);
  }
}

class _BrandSymbolPainter extends CustomPainter {
  final Color color;
  final Color figureColor;
  final BrandSymbolStyle style;

  /// 심벌 원본 좌표계 한 변. 모든 좌표는 이 값을 기준으로 정의하고 실제 크기에
  /// 맞춰 스케일한다.
  static const double _design = 40;

  const _BrandSymbolPainter({
    required this.color,
    required this.figureColor,
    required this.style,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final scale = size.shortestSide / _design;
    canvas.save();
    canvas.scale(scale);

    _paintBrackets(canvas);
    _paintFigure(canvas);

    canvas.restore();
  }

  /// 뷰파인더 코너 브래킷 4개.
  void _paintBrackets(Canvas canvas) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round;

    const lo = 4.0; // 프레임 안쪽 여백
    const hi = _design - lo;
    const arm = 8.0; // 각 코너에서 뻗는 직선 길이
    const r = 3.0; // 코너 곡률

    // 코너를 제어점으로 둔 2차 베지어로 둥근 모서리를 만든다. 호(arc)와 달리
    // 회전 방향 해석이 끼어들지 않아 네 코너가 항상 대칭으로 그려진다.
    canvas
      ..drawPath(
        Path()
          ..moveTo(lo, lo + arm)
          ..lineTo(lo, lo + r)
          ..quadraticBezierTo(lo, lo, lo + r, lo)
          ..lineTo(lo + arm, lo),
        paint,
      )
      ..drawPath(
        Path()
          ..moveTo(hi - arm, lo)
          ..lineTo(hi - r, lo)
          ..quadraticBezierTo(hi, lo, hi, lo + r)
          ..lineTo(hi, lo + arm),
        paint,
      )
      ..drawPath(
        Path()
          ..moveTo(hi, hi - arm)
          ..lineTo(hi, hi - r)
          ..quadraticBezierTo(hi, hi, hi - r, hi)
          ..lineTo(hi - arm, hi),
        paint,
      )
      ..drawPath(
        Path()
          ..moveTo(lo + arm, hi)
          ..lineTo(lo + r, hi)
          ..quadraticBezierTo(lo, hi, lo, hi - r)
          ..lineTo(lo, hi - arm),
        paint,
      );
  }

  /// 인물 실루엣(머리 + 어깨).
  void _paintFigure(Canvas canvas) {
    const headCenter = Offset(20, 14.5);
    const headRadius = 4.4;

    final body = Path()
      ..moveTo(20, 21.5)
      ..cubicTo(15.4, 21.5, 12.6, 24.1, 12.6, 28.6)
      ..lineTo(27.4, 28.6)
      ..cubicTo(27.4, 24.1, 24.6, 21.5, 20, 21.5)
      ..close();

    switch (style) {
      case BrandSymbolStyle.solid:
        final fill = Paint()
          ..color = figureColor
          ..style = PaintingStyle.fill;
        canvas.drawCircle(headCenter, headRadius, fill);
        canvas.drawPath(body, fill);

      case BrandSymbolStyle.outlined:
        final stroke = Paint()
          ..color = figureColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        final head = Path()
          ..addOval(Rect.fromCircle(center: headCenter, radius: headRadius));
        canvas.drawPath(_dashed(head), stroke);
        canvas.drawPath(_dashed(body), stroke);
    }
  }

  /// 점선 경로. [Path]에 직접 dash를 줄 수 없어 길이를 따라 잘라 만든다.
  Path _dashed(Path source, {double dash = 3, double gap = 3}) {
    final result = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0.0, metric.length);
        result.addPath(metric.extractPath(distance, end), Offset.zero);
        distance = end + gap;
      }
    }
    return result;
  }

  @override
  bool shouldRepaint(covariant _BrandSymbolPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.figureColor != figureColor ||
      oldDelegate.style != style;
}

/// 심벌 + 워드타입.
///
/// 앱 안에서 워드마크가 등장하는 곳은 기록 화면 헤더와 내보내기 꼬리말뿐이다.
/// 그 외 화면은 뒤로가기와 화면 제목이 맥락을 대신하므로 넣지 않는다.
class BrandWordmark extends StatelessWidget {
  /// 심벌 크기. 워드타입 크기는 여기에 비례해 정한다.
  final double symbolSize;

  final Color color;

  const BrandWordmark({super.key, this.symbolSize = 20, required this.color});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Body Frame',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BrandSymbol(size: symbolSize, color: color),
          SizedBox(width: symbolSize * 0.3),
          // "Body"가 굵고 "Frame"이 가벼운 것은 의도다. 몸(피사체)이 주인공이고
          // 프레임(도구)이 받친다.
          ExcludeSemantics(
            child: Text.rich(
              TextSpan(
                children: const [
                  TextSpan(
                    text: 'Body ',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: 'Frame',
                    style: TextStyle(fontWeight: FontWeight.w400),
                  ),
                ],
                style: TextStyle(
                  color: color,
                  fontSize: symbolSize * 0.85,
                  height: 1.2,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
