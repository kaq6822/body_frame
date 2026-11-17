import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/members/ui.dart' show mark;

/// 하단 탭 틀. 탭 바는 이 틀에 한 번만 있고, 탭을 바꾸면 안쪽 내용만 바뀐다.
///
/// 탭마다 내비게이터(가지)를 따로 두어 다녀와도 스크롤·필터가 그대로 남는다.
/// 상세·편집처럼 위로 여는 화면은 루트 내비게이터에 올라가 탭 바를 덮는다.
class MainShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const MainShell({super.key, required this.shell});

  static const tabs = ['/', '/members', '/records', '/settings'];

  void _select(int index) {
    // 지금 탭을 다시 누르면 그 탭의 처음 화면으로 돌아간다.
    shell.goBranch(index, initialLocation: index == shell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 홈이 아닌 탭에서 시스템 뒤로가기는 앱을 닫지 않고 홈으로 간다.
      // 홈에서는 평소처럼 앱이 닫힌다.
      canPop: shell.currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(0);
      },
      child: Scaffold(
        body: shell,
        bottomNavigationBar: mark(
          'main.navigation',
          NavigationBar(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: _select,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: '홈',
              ),
              NavigationDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: '회원',
              ),
              NavigationDestination(
                icon: Icon(Icons.article_outlined),
                selectedIcon: Icon(Icons.article),
                label: '기록',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: '설정',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 탭 내용을 겹쳐 두고 고른 탭만 짧게 페이드로 보인다.
///
/// 화면 전체가 미끄러지는 전환 대신 내용만 바뀌어 탭 바가 움직이지 않는다.
/// 보이지 않는 탭은 입력·접근성·애니메이션에서 빠진다.
class FadingBranchContainer extends StatelessWidget {
  final int currentIndex;
  final List<Widget> children;
  const FadingBranchContainer({
    super.key,
    required this.currentIndex,
    required this.children,
  });

  static const duration = Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < children.length; i++)
          _Branch(active: i == currentIndex, child: children[i]),
      ],
    );
  }
}

class _Branch extends StatelessWidget {
  final bool active;
  final Widget child;
  const _Branch({required this.active, required this.child});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !active,
      child: ExcludeSemantics(
        excluding: !active,
        child: TickerMode(
          enabled: active,
          child: AnimatedOpacity(
            opacity: active ? 1 : 0,
            duration: FadingBranchContainer.duration,
            curve: Curves.easeOut,
            child: child,
          ),
        ),
      ),
    );
  }
}
