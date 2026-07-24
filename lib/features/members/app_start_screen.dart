import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';

/// 앱 시작 화면.
///
/// 로그인이나 회원가입 없이 곧바로 회원 목록으로 진입한다.
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
