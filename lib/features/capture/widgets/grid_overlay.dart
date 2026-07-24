import 'package:flutter/material.dart';

import 'package:body_frame/core/models/models.dart';
import 'grid_painter.dart';

/// 카메라 미리보기 위에 겹치는 격자 오버레이.
///
/// CustomPaint의 상태를 알 수 있도록 격자 표시 여부를 Semantics label로
/// 노출한다. 사용자 입력을 받지 않으므로
/// [IgnorePointer]로 하위 제스처(셔터 등)를 가로채지 않게 한다.
class GridOverlay extends StatelessWidget {
  final GridSettings settings;

  const GridOverlay({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'capture.grid.overlay',
      label: settings.visible ? '정렬 격자 표시됨' : '정렬 격자 숨김',
      child: IgnorePointer(
        child: CustomPaint(
          key: const ValueKey('capture.grid.overlay'),
          size: Size.infinite,
          painter: GridPainter(settings),
        ),
      ),
    );
  }
}
