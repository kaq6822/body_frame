import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';

/// 1. 앱 시작 화면. MVP.md 12장.
///
/// 로그인/회원가입 없이(MVP.md 2장) 곧바로 회원 목록으로 진입한다.
/// 설정 워커가 앱 잠금 게이트를 여기에 추가할 수 있다.
class AppStartScreen extends StatelessWidget {
  static const screenId = 'screen.app.start';

  const AppStartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: screenId,
      container: true,
      label: '앱 시작',
      child: Scaffold(
        key: const ValueKey(screenId),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '체형 변화 기록',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 24),
              Semantics(
                identifier: 'app.start.enter.button',
                button: true,
                label: '시작하기',
                child: FilledButton(
                  key: const ValueKey('app.start.enter.button'),
                  onPressed: () => context.goNamed(AppRoutes.membersList),
                  child: const Text('시작하기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
