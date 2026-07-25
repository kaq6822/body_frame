import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/services/app_image_picker.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/providers/settings_providers.dart';
import 'features/settings/widgets/app_lock_gate.dart';

void main() {
  runApp(const ProviderScope(child: BodyFrameApp()));
}

final appBootstrapProvider = FutureProvider<void>((ref) async {
  final reconcileRestore = ref.watch(restoreStartupReconcilerProvider);
  await reconcileRestore();
});

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
    final bootstrap = ref.watch(appBootstrapProvider);
    return bootstrap.when(
      data: (_) {
        // 복원 조정이 끝난 뒤 Android image_picker의 Activity 종료 결과를
        // 앱 루트에서 한 번만 회수한다.
        ref.read(appImagePickerCoordinatorProvider);
        return MaterialApp.router(
          title: '체형 변화 기록',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          routerConfig: _router,
          // 앱 잠금과 백그라운드 화면 가리기를 전체 화면에 적용한다.
          builder: (context, child) =>
              AppLockGate(child: child ?? const SizedBox.shrink()),
        );
      },
      loading: () => MaterialApp(
        title: '체형 변화 기록',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: const _BootstrapLoadingScreen(),
      ),
      error: (_, _) => MaterialApp(
        title: '체형 변화 기록',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: _BootstrapFailureScreen(
          onRetry: () => ref.invalidate(appBootstrapProvider),
        ),
      ),
    );
  }
}

class _BootstrapLoadingScreen extends StatelessWidget {
  const _BootstrapLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Semantics(
        key: const ValueKey('screen.bootstrap.loading'),
        identifier: 'screen.bootstrap.loading',
        container: true,
        label: '앱 데이터 확인 중',
        child: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _BootstrapFailureScreen extends StatelessWidget {
  final VoidCallback onRetry;

  const _BootstrapFailureScreen({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Semantics(
        key: const ValueKey('screen.bootstrap.error'),
        identifier: 'screen.bootstrap.error',
        container: true,
        label: '앱 데이터 확인 실패',
        child: Center(
          child: FilledButton(
            key: const ValueKey('bootstrap.retry.button'),
            onPressed: onRetry,
            child: const Text('다시 시도'),
          ),
        ),
      ),
    );
  }
}
