import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 화면 하단에 고정되는 주요 동작 영역. `Scaffold.bottomNavigationBar`에 넣는다.
///
/// 위쪽 1px 구분선, 16dp 여백, 하단 SafeArea를 포함한다. [primary]는 가로를
/// 가득 채운다. [secondary]가 있으면 보통 글꼴에서는 [secondary]·[primary]를
/// 1:1로 나란히, 큰 글꼴에서는 [primary]를 위에 두고 세로로 쌓는다.
class BottomActionBar extends StatelessWidget {
  static const defaultIdentifier = 'common.bottom.actions';

  /// 주요 동작 버튼. 보통 [FilledButton].
  final Widget primary;

  /// 보조 동작 버튼. 보통 [OutlinedButton].
  final Widget? secondary;

  /// 진행 상태·오류처럼 버튼 위에 붙는 한 줄.
  final Widget? leading;

  final String identifier;

  const BottomActionBar({
    super.key,
    required this.primary,
    this.secondary,
    this.leading,
    this.identifier = defaultIdentifier,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final Widget buttons;
    if (secondary == null) {
      buttons = SizedBox(width: double.infinity, child: primary);
    } else if (stacked) {
      buttons = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          primary,
          const SizedBox(height: AppSpacing.sp2),
          secondary!,
        ],
      );
    } else {
      buttons = Row(
        children: [
          // 1:1로 나눈다. 1:2면 360dp에서 보조 버튼 폭이 105dp 남짓이라
          // "기기에 저장"처럼 아이콘이 붙은 다섯 글자도 두 줄로 꺾였다(실기기 확인).
          Expanded(child: secondary!),
          const SizedBox(width: AppSpacing.sp3),
          Expanded(child: primary),
        ],
      );
    }

    return Semantics(
      identifier: identifier,
      container: true,
      child: DecoratedBox(
        key: ValueKey(identifier),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLowest,
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: AppSpacing.content,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(height: AppSpacing.sp2),
                ],
                buttons,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
