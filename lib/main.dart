import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
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
  void initState() {
    super.initState();
    // 저장 도중 앱이 죽으면 확정되지 않은 staging 파일이 남는다. 아직 아무
    // 쓰기도 시작되지 않은 이 시점이 지우기에 안전한 유일한 자리다.
    unawaited(_cleanupStagingLeftovers());
  }

  Future<void> _cleanupStagingLeftovers() async {
    try {
      await ref.read(photoStorageServiceProvider).cleanupStagingLeftovers();
    } catch (_) {
      // 정리는 부가 작업이다. 실패해도 앱 시작을 막지 않는다.
    }
  }

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
