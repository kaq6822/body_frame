import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/router/app_router.dart';
import 'core/services/app_image_picker.dart';
import 'core/theme/app_theme.dart';

void main() {
  LicenseRegistry.addLicense(_pretendardLicense);
  runApp(const ProviderScope(child: BodyMarkApp()));
}

/// 번들한 Pretendard 글꼴의 OFL 원문을 오픈소스 라이선스 화면에 노출한다.
/// OFL은 글꼴과 함께 라이선스 원문을 배포하도록 요구한다.
Stream<LicenseEntry> _pretendardLicense() async* {
  final text = await rootBundle.loadString('assets/fonts/Pretendard-OFL.txt');
  yield LicenseEntryWithLineBreaks(const ['Pretendard'], text);
}

/// 체형 변화 기록 앱.
///
/// 로그인/서버 없는 스탠드얼론 앱. ProviderScope + MaterialApp.router로
/// Riverpod과 go_router를 연결한다.
class BodyMarkApp extends ConsumerStatefulWidget {
  const BodyMarkApp({super.key});

  @override
  ConsumerState<BodyMarkApp> createState() => _BodyMarkAppState();
}

class _BodyMarkAppState extends ConsumerState<BodyMarkApp> {
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
      title: 'BodyMark',
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: _router,
    );
  }
}
