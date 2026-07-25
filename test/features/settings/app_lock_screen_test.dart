import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/features/settings/app_lock_screen.dart';
import 'package:body_frame/features/settings/providers/settings_providers.dart';
import 'package:body_frame/features/settings/services/app_settings_service.dart';
import 'package:body_frame/features/settings/services/lock_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('첫 PIN 선택은 비밀값 저장이 끝날 때까지 잠금 모드를 적용하지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = _MemorySettingsService(AppSettings.defaults);
    final lock = _MemoryLockService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsServiceProvider.overrideWithValue(settings),
          lockServiceProvider.overrideWithValue(lock),
        ],
        child: const MaterialApp(home: AppLockScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('lock.mode.pin.radio')));
    await tester.pump();

    expect(find.byKey(const ValueKey('lock.pin.field')), findsOneWidget);
    expect(settings.settings.lockMode, LockMode.none);

    await tester.enterText(
      find.byKey(const ValueKey('lock.pin.field')),
      '12a4',
    );
    await tester.enterText(
      find.byKey(const ValueKey('lock.pin.confirm.field')),
      '12a4',
    );
    await tester.tap(find.byKey(const ValueKey('lock.pin.save.button')));
    await tester.pump();

    expect(find.text('PIN은 숫자 4~12자리로 입력해 주세요'), findsOneWidget);
    expect(lock.savedSecret, isNull);
    expect(settings.settings.lockMode, LockMode.none);

    await tester.enterText(
      find.byKey(const ValueKey('lock.pin.field')),
      '1234',
    );
    await tester.enterText(
      find.byKey(const ValueKey('lock.pin.confirm.field')),
      '1234',
    );
    await tester.tap(find.byKey(const ValueKey('lock.pin.save.button')));
    await tester.pumpAndSettle();

    expect(lock.savedSecret, '1234');
    expect(settings.settings.lockMode, LockMode.pin);
  });

  testWidgets('비밀번호 방식은 일반 문자 입력과 8자 최소 길이를 사용한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = _MemorySettingsService(AppSettings.defaults);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsServiceProvider.overrideWithValue(settings),
          lockServiceProvider.overrideWithValue(_MemoryLockService()),
        ],
        child: const MaterialApp(home: AppLockScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('lock.mode.password.radio')));
    await tester.pump();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('lock.pin.field')),
    );
    expect(field.keyboardType, TextInputType.visiblePassword);
    expect(field.maxLength, 128);

    await tester.enterText(
      find.byKey(const ValueKey('lock.pin.field')),
      'short',
    );
    await tester.enterText(
      find.byKey(const ValueKey('lock.pin.confirm.field')),
      'short',
    );
    await tester.tap(find.byKey(const ValueKey('lock.pin.save.button')));
    await tester.pump();

    expect(find.text('비밀번호는 8~128자로 입력해 주세요'), findsOneWidget);
  });
}

class _MemorySettingsService implements AppSettingsService {
  AppSettings settings;

  _MemorySettingsService(this.settings);

  @override
  Future<AppSettings> load() async => settings;

  @override
  Future<void> save(AppSettings settings) async {
    this.settings = settings;
  }
}

class _MemoryLockService implements LockService {
  String? savedSecret;

  @override
  Future<bool> authenticateWithBiometrics({String? reason}) async => false;

  @override
  Future<void> clearSecret() async {
    savedSecret = null;
  }

  @override
  Future<bool> hasSecret() async => savedSecret != null;

  @override
  Future<bool> isBiometricAvailable() async => false;

  @override
  Future<LockThrottleState> loadThrottleState() async =>
      const LockThrottleState();

  @override
  Future<void> setSecret(String secret) async {
    savedSecret = secret;
  }

  @override
  Future<bool> verifySecret(String secret) async => secret == savedSecret;
}
