import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../compare_export_models.dart';

/// 비교 방식(나란히·겹쳐·슬라이더)을 고르는 3등분 세그먼트.
///
/// 한 줄에 세 칸을 같은 폭으로 둔다. 칩을 가로 스크롤하면 마지막 칩이 화면
/// 끝에서 잘려 보이고 더 있다는 표시도 없었다. 칸이 좁으면 아이콘을 빼고,
/// 큰 글꼴에서 라벨이 칸보다 길면 잘라내지 않고 칸 안에 맞게 줄여 그린다.
/// 읽기는 전체 라벨로 한다.
///
/// 식별자는 `<idPrefix>.selector`, 칸마다 `<idPrefix>.<mode.key>.button`이다.
class CompareModeSelector extends StatelessWidget {
  final String idPrefix;
  final String semanticsLabel;
  final CompareMode mode;
  final ValueChanged<CompareMode> onChanged;

  const CompareModeSelector({
    super.key,
    required this.idPrefix,
    required this.mode,
    required this.onChanged,
    this.semanticsLabel = '비교 방식 선택',
  });

  /// 아이콘과 라벨을 함께 그릴 수 있는 칸 폭(논리 px).
  static const _iconMinSegmentWidth = 120.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      identifier: '$idPrefix.selector',
      label: semanticsLabel,
      container: true,
      child: DecoratedBox(
        key: ValueKey('$idPrefix.selector'),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: AppRadius.mdAll,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sp1),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final segmentWidth =
                  (constraints.maxWidth - AppSpacing.sp1 * 2) / 3;
              final showIcon = segmentWidth >= _iconMinSegmentWidth;
              return Row(
                spacing: AppSpacing.sp1,
                children: [
                  for (final value in CompareMode.values)
                    Expanded(child: _segment(context, value, showIcon)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _segment(BuildContext context, CompareMode value, bool showIcon) {
    final colors = context.colors;
    final selected = value == mode;
    final id = '$idPrefix.${value.key}.button';
    final foreground = selected ? colors.primary : colors.onSurfaceVariant;
    final icon = switch (value) {
      CompareMode.sideBySide => Icons.view_column_outlined,
      CompareMode.overlay => Icons.layers_outlined,
      CompareMode.slider => Icons.compare_outlined,
    };
    return Semantics(
      identifier: id,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: value.label,
      excludeSemantics: true,
      onTap: () => onChanged(value),
      child: Material(
        key: ValueKey(id),
        color: selected ? colors.surface : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.smAll,
          side: selected
              ? BorderSide(color: colors.outlineVariant)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onChanged(value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTouchTarget - AppSpacing.sp1 * 2,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp1),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: AppSpacing.sp1,
                    children: [
                      if (showIcon) Icon(icon, size: 18, color: foreground),
                      Text(
                        value.label,
                        maxLines: 1,
                        style: context.texts.labelLarge?.copyWith(
                          color: foreground,
                          fontWeight: selected ? FontWeight.w600 : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
