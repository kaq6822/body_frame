import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/widgets/app_lock_gate.dart';

void main() {
  runApp(const ProviderScope(child: BodyFrameApp()));
}

/// 체형 변화 기록 앱. MVP.md 1장.
///
/// 로그인/서버 없는 스탠드얼론 앱. ProviderScope + MaterialApp.router로
/// Riverpod과 go_router를 연결한다.
class BodyFrameApp extends StatefulWidget {
  const BodyFrameApp({super.key});

  @override
  State<BodyFrameApp> createState() => _BodyFrameAppState();
}

class _BodyFrameAppState extends State<BodyFrameApp> {
  late final _router = createAppRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '체형 변화 기록',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: _router,
      // MVP.md 11장: 앱 잠금·백그라운드 화면 가리기를 전체 화면에 적용.
      builder: (context, child) => AppLockGate(child: child ?? const SizedBox.shrink()),
    );
  }
}
