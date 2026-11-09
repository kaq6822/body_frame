import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// [StatusPill]의 의미 톤.
enum StatusPillTone {
  /// 회색 배경. 분류·보조 정보.
  neutral,

  /// 주요 색 옅은 배경. 선택·진행 중.
  primary,

  /// 앰버 옅은 배경. 주의 사항·누락된 방향.
  warning,

  /// 측정 시안. 수평 잠금·기준 일치. 어두운 HUD 위에서도 쓴다.
  measure,
}

/// 완전 둥근 작은 상태 칩. 누를 수 없는 표시 전용이다.
///
/// 앱에서 완전 둥근 모양은 이 칩에만 쓴다. 높이는 글꼴 크기에 따라 늘어난다.
class StatusPill extends StatelessWidget {
  final String label;
  final StatusPillTone tone;
  final IconData? icon;

  /// 지정하면 Semantics identifier와 ValueKey로 같은 값을 붙인다.
  final String? identifier;

  const StatusPill({
    super.key,
    required this.label,
    this.tone = StatusPillTone.neutral,
    this.icon,
    this.identifier,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final semantic = context.semanticColors;
    final (Color background, Color foreground) = switch (tone) {
      StatusPillTone.neutral => (
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
      StatusPillTone.primary => (
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
      StatusPillTone.warning => (
        semantic.warningContainer,
        semantic.onWarningContainer,
      ),
      StatusPillTone.measure => (semantic.measure, semantic.onMeasure),
    };
    return Semantics(
      identifier: identifier,
      container: identifier != null,
      child: Container(
        key: identifier == null ? null : ValueKey<String>(identifier!),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sp2,
          vertical: AppSpacing.sp1 / 2,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadius.fullAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              ExcludeSemantics(child: Icon(icon, size: 14, color: foreground)),
              const SizedBox(width: AppSpacing.sp1),
            ],
            Flexible(
              child: Text(
                label,
                style: context.texts.labelMedium?.copyWith(
                  color: foreground,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
