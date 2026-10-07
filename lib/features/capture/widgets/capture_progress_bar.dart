import 'package:flutter/material.dart';

import '../providers/capture_session_provider.dart';

/// 연속 촬영 세션의 단계 진행 표시.
///
/// 각 방향이 현재 단계인지, 이미 찍었는지, 아직 안 찍었는지를 한눈에 보여주고
/// 탭하면 그 단계로 이동해 재촬영할 수 있다.
class CaptureProgressBar extends StatelessWidget {
  final List<CaptureShot> shots;
  final int currentIndex;
  final ValueChanged<int> onStepSelected;
  final Color foreground;

  const CaptureProgressBar({
    super.key,
    required this.shots,
    required this.currentIndex,
    required this.onStepSelected,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final captured = shots.where((shot) => shot.isCaptured).length;

    return Semantics(
      identifier: 'capture.progress',
      label: '촬영 진행 ${currentIndex + 1} / ${shots.length}, $captured장 촬영됨',
      child: Column(
        key: const ValueKey('capture.progress'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${currentIndex + 1} / ${shots.length} · ${shots[currentIndex].direction.label}',
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          // 글꼴을 축소하지 않고 줄바꿈해 터치 영역과 읽기 크기를 보존한다.
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < shots.length; i++)
                _StepChip(
                  shot: shots[i],
                  isCurrent: i == currentIndex,
                  foreground: foreground,
                  onTap: () => onStepSelected(i),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  final CaptureShot shot;
  final bool isCurrent;
  final Color foreground;
  final VoidCallback onTap;

  const _StepChip({
    required this.shot,
    required this.isCurrent,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final id = 'capture.progress.step.${shot.direction.key}';
    final state = shot.isCaptured ? '촬영 완료' : '미촬영';

    return Semantics(
      identifier: id,
      button: true,
      selected: isCurrent,
      value: state,
      label: '${shot.direction.label} $state, 탭하여 이 단계로 이동',
      child: InkWell(
        key: ValueKey(id),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: shot.isCaptured
                ? foreground.withValues(alpha: 0.22)
                : Colors.transparent,
            border: Border.all(
              color: isCurrent
                  ? foreground
                  : foreground.withValues(alpha: 0.35),
              width: isCurrent ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                shot.isCaptured
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 14,
                color: foreground,
              ),
              const SizedBox(width: 4),
              Text(
                shot.direction.label,
                style: TextStyle(color: foreground, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
