import 'package:flutter/material.dart';

/// 워커가 아직 구현하지 않은 화면을 위한 공통 placeholder.
///
/// RULE.md 1~4: 각 화면 루트에 안정적인 Semantics.identifier와 ValueKey를
/// 부여한다. 식별자는 문구/색상/위치에 의존하지 않는 `screen.area.name`
/// 형식을 따른다. 워커는 이 화면을 실제 구현으로 교체하되 동일한
/// screenId/ValueKey 규칙을 유지한다.
class PlaceholderScaffold extends StatelessWidget {
  /// 예: 'screen.members.list'. Semantics.identifier이자 ValueKey에 사용한다.
  final String screenId;

  /// AppBar 표시 제목(한국어).
  final String title;

  /// 화면 설명(선택). 아직 미구현임을 안내한다.
  final String? description;

  const PlaceholderScaffold({
    super.key,
    required this.screenId,
    required this.title,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: screenId,
      container: true,
      label: title,
      child: Scaffold(
        key: ValueKey(screenId),
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  description ?? '준비 중인 화면입니다.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  screenId,
                  style: Theme.of(context).textTheme.labelSmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
