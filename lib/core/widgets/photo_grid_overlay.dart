import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/models.dart';
import 'grid_painter.dart';

/// 저장된 사진 위에 겹쳐 그리는 정렬 격자.
///
/// 앱 안의 모든 사진 보기(타임라인 스트립, 방향 모아보기, 기록 상세, 원본 보기,
/// 촬영 결과 확인, 갤러리 등록 미리보기)가 같은 규칙으로 격자를 얹도록 이
/// 위젯을 공유한다. 격자는 언제나 오버레이일 뿐이므로 원본 픽셀에는 남지 않는다.
///
/// [GridSettings.spacing]과 [GridSettings.lineWidth]는 촬영 화면(거의 화면 폭)
/// 기준의 논리 픽셀 값이다. 그대로 쓰면 썸네일에서는 선 몇 개만 지나가는 모양이
/// 되므로, 상자 폭을 [referenceWidth]와 비교해 격자 밀도를 비례 축소한다.
class PhotoGridOverlay extends StatelessWidget {
  /// 이 사진에 적용된 격자 설정. [GridSettings.visible]이 false면 아무것도
  /// 그리지 않는다.
  final GridSettings settings;

  /// 예: 'records.viewer.grid.overlay'. 화면마다 격자 상태를 검사·테스트할 수
  /// 있도록 별도 식별자를 부여한다.
  final String semanticsIdentifier;

  /// 격자 밀도의 기준 폭. 비워두면 화면 폭(촬영 화면 기준)을 쓴다.
  final double? referenceWidth;

  const PhotoGridOverlay({
    super.key,
    required this.settings,
    required this.semanticsIdentifier,
    this.referenceWidth,
  });

  @override
  Widget build(BuildContext context) {
    if (!settings.visible) return const SizedBox.shrink();

    final reference = referenceWidth ?? MediaQuery.sizeOf(context).width;
    final opacityPercent = (settings.opacity.clamp(0.0, 1.0) * 100).round();

    return Semantics(
      identifier: semanticsIdentifier,
      label: '체형 정렬 격자',
      value: '표시됨, 투명도 $opacityPercent%',
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) => CustomPaint(
            key: ValueKey(semanticsIdentifier),
            size: Size.infinite,
            painter: GridPainter(
              scaleGridToBox(
                settings,
                boxWidth: constraints.maxWidth,
                referenceWidth: reference,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 격자 밀도를 [boxWidth]에 맞춰 비례 축소한다.
///
/// 상자가 기준 폭보다 넓으면(확대 보기 등) 설정값을 그대로 쓴다. 축소할 때도
/// 선이 뭉개지거나 사라지지 않도록 간격과 굵기에 하한을 둔다.
GridSettings scaleGridToBox(
  GridSettings settings, {
  required double boxWidth,
  required double referenceWidth,
}) {
  const minSpacing = 12.0;
  const minLineWidth = 0.5;

  if (!boxWidth.isFinite ||
      boxWidth <= 0 ||
      !referenceWidth.isFinite ||
      referenceWidth <= 0) {
    return settings;
  }
  final scale = boxWidth / referenceWidth;
  if (scale >= 1) return settings;

  // 하한이 설정값을 거꾸로 키우지 않게 원래 값과 하한 중 작은 쪽을 바닥으로 쓴다.
  final spacingFloor = math.min(settings.spacing, minSpacing);
  final lineWidthFloor = math.min(settings.lineWidth, minLineWidth);
  return settings.copyWith(
    spacing: math.max(spacingFloor, settings.spacing * scale),
    lineWidth: math.max(lineWidthFloor, settings.lineWidth * scale),
  );
}
