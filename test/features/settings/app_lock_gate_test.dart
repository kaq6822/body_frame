import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/features/settings/providers/settings_providers.dart';
import 'package:body_frame/features/settings/services/app_settings_service.dart';
import 'package:body_frame/features/settings/services/lock_service.dart';
import 'package:body_frame/features/settings/widgets/app_lock_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('잠금 설정이 있으면 콜드 스타트에서 인증 화면을 먼저 표시한다', (tester) async {
    final lock = _FakeLockService(validSecret: '1234');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsServiceProvider.overrideWithValue(
            _FakeSettingsService(const AppSettings(lockMode: LockMode.pin)),
          ),
          lockServiceProvider.overrideWithValue(lock),
        ],
        child: const MaterialApp(
          home: AppLockGate(child: Scaffold(body: Text('민감한 본문'))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('lock.gate.secret.field')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('lock.gate.secret.field')),
      '1234',
    );
    await tester.tap(find.byKey(const ValueKey('lock.gate.submit.button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('lock.gate.secret.field')), findsNothing);
    expect(find.text('민감한 본문'), findsOneWidget);
  });

  testWidgets('백그라운드에서는 잠금 사용 여부와 관계없이 화면을 가린다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsServiceProvider.overrideWithValue(
            _FakeSettingsService(AppSettings.defaults),
          ),
          lockServiceProvider.overrideWithValue(_FakeLockService()),
        ],
        child: const MaterialApp(
          home: AppLockGate(child: Scaffold(body: Text('민감한 본문'))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('screen.lock.backgroundCover')),
      findsOneWidget,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('screen.lock.backgroundCover')),
      findsNothing,
    );
  });

  testWidgets('잠금 설정을 읽지 못하면 본문 대신 재시도 화면을 표시한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsServiceProvider.overrideWithValue(
            _FailingSettingsService(),
          ),
          lockServiceProvider.overrideWithValue(_FakeLockService()),
        ],
        child: const MaterialApp(
          home: AppLockGate(child: Scaffold(body: Text('민감한 본문'))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('lock.settings.retry.button')),
      findsOneWidget,
    );
    expect(find.text('잠금 설정을 불러오지 못했습니다'), findsOneWidget);
  });
}

class _FakeSettingsService implements AppSettingsService {
  AppSettings settings;

  _FakeSettingsService(this.settings);

  @override
  Future<AppSettings> load() async => settings;

  @override
  Future<void> save(AppSettings settings) async {
    this.settings = settings;
  }
}

class _FailingSettingsService implements AppSettingsService {
  @override
  Future<AppSettings> load() => Future.error(StateError('unavailable'));

  @override
  Future<void> save(AppSettings settings) async {}
}

class _FakeLockService implements LockService {
  final String? validSecret;

  _FakeLockService({this.validSecret});

  @override
  Future<bool> authenticateWithBiometrics({String? reason}) async => false;

  @override
  Future<void> clearSecret() async {}

  @override
  Future<bool> hasSecret() async => validSecret != null;

  @override
  Future<bool> isBiometricAvailable() async => false;

  @override
  Future<LockThrottleState> loadThrottleState() async =>
      const LockThrottleState();

  @override
  Future<void> setSecret(String secret) async {}

  @override
  Future<bool> verifySecret(String secret) async => secret == validSecret;
}
