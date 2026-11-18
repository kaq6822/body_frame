import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 라벨(위) + 값(아래) + (선택) 오른쪽 위젯.
///
/// 상세 화면의 "실제 레슨 일시 / 2026.11.04 (수) 오후 3:00" 같은 한 쌍에 쓴다.
/// 값이 날짜·수치면 [numeric]을 켜 tabular figures로 표시한다. 스크린 리더는
/// "라벨, 값"을 한 덩어리로 읽는다.
class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Widget? trailing;
  final bool numeric;

  /// 지정하면 Semantics identifier와 ValueKey로 같은 값을 붙인다.
  final String? identifier;

  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.trailing,
    this.numeric = false,
    this.identifier,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final valueStyle =
        (numeric ? context.numericTexts.titleMedium : context.texts.titleMedium)
            ?.copyWith(color: colors.onSurface);
    return Semantics(
      identifier: identifier,
      container: true,
      label: '$label, $value',
      excludeSemantics: trailing == null,
      child: Padding(
        key: identifier == null ? null : ValueKey<String>(identifier!),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sp2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Text(
                      label,
                      style: context.texts.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sp1),
                  ExcludeSemantics(child: Text(value, style: valueStyle)),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.sp3),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
