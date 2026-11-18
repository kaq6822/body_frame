import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 섹션 제목 + (선택) 개수 + (선택) 오른쪽 동작.
///
/// 예: "레슨 기록 2" + "최신순". 제목은 스크린 리더에서 heading으로 읽힌다.
class SectionHeader extends StatelessWidget {
  final String title;

  /// 제목 옆에 붙는 개수. tabular figures로 표시한다.
  final int? count;

  /// 오른쪽 정렬 위젯. 보통 [TextButton] 또는 [StatusPill].
  final Widget? trailing;

  /// 지정하면 Semantics identifier와 ValueKey로 같은 값을 붙인다.
  final String? identifier;

  final EdgeInsetsGeometry padding;

  const SectionHeader({
    super.key,
    required this.title,
    this.count,
    this.trailing,
    this.identifier,
    this.padding = const EdgeInsets.only(
      top: AppSpacing.sp6,
      bottom: AppSpacing.sp2,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final style = context.texts.titleMedium?.copyWith(
      color: context.colors.onSurface,
    );
    final row = Padding(
      key: identifier == null ? null : ValueKey<String>(identifier!),
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: title),
                    if (count != null)
                      TextSpan(
                        text: ' $count',
                        style: context.numericTexts.titleMedium.copyWith(
                          color: context.colors.primary,
                        ),
                      ),
                  ],
                ),
                style: style,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.sp2),
            trailing!,
          ],
        ],
      ),
    );
    if (identifier == null) return row;
    return Semantics(identifier: identifier, container: true, child: row);
  }
}
