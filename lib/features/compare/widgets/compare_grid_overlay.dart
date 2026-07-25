import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../../core/widgets/grid_painter.dart';

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
    final opacityPercent = (settings.opacity.clamp(0.0, 1.0) * 100).round();
    return Semantics(
      identifier: semanticsIdentifier,
      label: '체형 정렬 격자',
      value: '표시됨, 투명도 $opacityPercent%',
      child: IgnorePointer(
        child: CustomPaint(
          size: Size.infinite,
          // 이 위젯의 존재 자체가 비교 화면의 명시적인 표시 선택이다.
          // 촬영 화면에서 저장한 visible 값이 이를 다시 숨기지 않게 한다.
          painter: GridPainter(settings.copyWith(visible: true)),
        ),
      ),
    );
  }
}
