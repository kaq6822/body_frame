import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/services/app_image_picker.dart';
import 'core/theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: BodyFrameApp()));
}

/// 체형 변화 기록 앱.
///
/// 로그인/서버 없는 스탠드얼론 앱. ProviderScope + MaterialApp.router로
/// Riverpod과 go_router를 연결한다.
class BodyFrameApp extends ConsumerStatefulWidget {
  const BodyFrameApp({super.key});

  @override
  ConsumerState<BodyFrameApp> createState() => _BodyFrameAppState();
}

class _BodyFrameAppState extends ConsumerState<BodyFrameApp> {
  late final _router = createAppRouter();

  @override
  Widget build(BuildContext context) {
    // Android image_picker의 Activity 종료 결과를 앱 루트에서 한 번만 회수한다.
    ref.read(appImagePickerCoordinatorProvider);
    return MaterialApp.router(
      title: '체형 변화 기록',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: _router,
    );
  }
}
