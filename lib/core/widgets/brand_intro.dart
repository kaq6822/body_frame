import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'brand_symbol.dart';

/// 기록·설정에서 같은 브랜드 약속과 시각적 위계를 제공한다.
class BrandIntro extends StatelessWidget {
  const BrandIntro({
    super.key,
    required this.identifier,
    required this.title,
    required this.description,
    this.eyebrow = 'BODY FRAME',
    this.trailing,
  });

  final String identifier;
  final String eyebrow;
  final String title;
  final String description;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: identifier,
      container: true,
      child: Container(
        key: ValueKey(identifier),
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.sp6),
        decoration: BoxDecoration(
          color: context.colors.primaryContainer,
          borderRadius: AppRadius.xlAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                BrandSymbol(size: 24, color: context.colors.onPrimaryContainer),
                const SizedBox(width: AppSpacing.sp2),
                Expanded(
                  child: Text(
                    eyebrow,
                    style: context.texts.labelMedium?.copyWith(
                      color: context.colors.onPrimaryContainer,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sp4),
            Text(
              title,
              style: context.texts.headlineSmall?.copyWith(
                color: context.colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: AppSpacing.sp2),
            Text(
              description,
              style: context.texts.bodyMedium?.copyWith(
                color: context.colors.onPrimaryContainer,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(height: AppSpacing.sp4),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
