import 'package:flutter/material.dart';

import 'package:bodymark/core/widgets/direction_stepper.dart';
import '../providers/capture_session_provider.dart';

/// 연속 촬영 세션의 단계 진행 표시(카메라 HUD용 [DirectionStepper]).
///
/// 현재 단계는 측정 시안으로 채우고 "정면 1/4"처럼 순번을 붙인다. 이미 찍은
/// 방향에는 체크 표시가 붙는다. 탭하면 그 단계로 이동해 재촬영할 수 있다.
/// 세그먼트 키·식별자는 `capture.progress.step.<direction.key>`다.
class CaptureProgressBar extends StatelessWidget {
  final List<CaptureShot> shots;
  final int currentIndex;
  final ValueChanged<int> onStepSelected;

  const CaptureProgressBar({
    super.key,
    required this.shots,
    required this.currentIndex,
    required this.onStepSelected,
  });

  @override
  Widget build(BuildContext context) {
    final captured = shots.where((shot) => shot.isCaptured).length;
    final directions = [for (final s in shots) s.direction];
    final current = shots[currentIndex].direction;

    return Semantics(
      identifier: 'capture.progress',
      label: '촬영 진행 ${currentIndex + 1} / ${shots.length}, $captured장 촬영됨',
      container: true,
      child: KeyedSubtree(
        key: const ValueKey('capture.progress'),
        child: DirectionStepper(
          identifier: 'capture.progress.step',
          onDark: true,
          directions: directions,
          selected: current,
          recorded: {
            for (final s in shots)
              if (s.isCaptured) s.direction,
          },
          labelBuilder: (d) => d == current
              ? '${d.label} ${currentIndex + 1}/${shots.length}'
              : d.label,
          onSelected: (d) => onStepSelected(directions.indexOf(d)),
        ),
      ),
    );
  }
}
