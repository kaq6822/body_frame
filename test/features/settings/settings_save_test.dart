import 'dart:async';

import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/core/services/grid_settings_service.dart';
import 'package:body_frame/features/capture/providers/capture_providers.dart';
import 'package:body_frame/features/capture/widgets/grid_settings_panel.dart';
import 'package:body_frame/features/settings/providers/settings_providers.dart';
import 'package:body_frame/features/settings/services/app_settings_service.dart';
import 'package:body_frame/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 앱 설정·격자 설정 저장의 신뢰성 테스트.
///
/// 저장이 빠르게 겹칠 때 마지막 선택이 영속 값으로 남는지, 실패가 조용히
/// 지나가지 않는지를 확인한다. 역순 완료와 예외는 Fake로 만들어 실제 시간이나
/// 플랫폼 I/O에 의존하지 않는다.
void main() {
  group('AppSettingsController', () {
    test('여러 설정을 빠르게 바꾸면 마지막 선택이 저장값으로 남는다', () async {
      final service = _FakeAppSettingsService();
      final container = ProviderContainer(
        overrides: [appSettingsServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      await container.read(appSettingsControllerProvider.future);

      final notifier = container.read(appSettingsControllerProvider.notifier);
      // 저장을 일부러 붙들어 두고 연속으로 바꾼다. 저장이 느릴 때 직전 값을
      // 다시 읽어 이전 값 위에 덮어쓰면 마지막 선택이 유실된다.
      final gate = Completer<void>();
      service.saveGate = gate;
      final first = notifier.updateSettings(
        (current) => current.copyWith(
          capture: current.capture.copyWith(timerSeconds: 5),
        ),
      );
      final second = notifier.updateSettings(
        (current) => current.copyWith(
          capture: current.capture.copyWith(countdownFeedback: false),
        ),
      );
      final third = notifier.updateSettings(
        (current) => current.copyWith(
          capture: current.capture.copyWith(timerSeconds: 10),
        ),
      );
      gate.complete();
      await Future.wait<void>([first, second, third]);

      // UI 상태는 마지막 선택을 반영한다.
      expect(
        container
            .read(appSettingsControllerProvider)
            .valueOrNull!
            .capture
            .timerSeconds,
        10,
      );
      // 영속 값도 마지막 선택과 같다. 실패 없이 저장되었다.
      final saveState = container.read(appSettingsSaveQueueProvider);
      expect(saveState.isFailure, isFalse);
      expect(service.saved.last.capture.timerSeconds, 10);
      // 세 번째 저장에 앞선 변경도 함께 남아 있다(필드 단위로 덮어쓰지 않음).
      expect(service.saved.last.capture.countdownFeedback, isFalse);
    });

    test('저장이 실패하면 실패 상태를 알리고 마지막 선택을 유지한다', () async {
      final service = _FakeAppSettingsService(failSave: true);
      final container = ProviderContainer(
        overrides: [appSettingsServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      await container.read(appSettingsControllerProvider.future);

      final notifier = container.read(appSettingsControllerProvider.notifier);
      await notifier.updateSettings(
        (current) => current.copyWith(
          capture: current.capture.copyWith(timerSeconds: 10),
        ),
      );

      final saveState = container.read(appSettingsSaveQueueProvider);
      expect(saveState.isFailure, isTrue);
      expect(saveState.canRetry, isTrue);
      // 실패해도 화면에 반영된 마지막 선택은 남는다.
      expect(
        container
            .read(appSettingsControllerProvider)
            .valueOrNull!
            .capture
            .timerSeconds,
        10,
      );

      // 재시도하면 저장이 성공하고 상태가 회복된다.
      service.failSave = false;
      await notifier.retrySave();

      expect(container.read(appSettingsSaveQueueProvider).isFailure, isFalse);
      expect(service.saved.last.capture.timerSeconds, 10);
    });

    testWidgets('설정 화면은 저장 실패를 보여주고 재시도를 제공한다', (tester) async {
      final service = _FakeAppSettingsService(failSave: true);
      _prepareWidgetTests();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appSettingsServiceProvider.overrideWithValue(service)],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('settings.capture.countdownFeedback.switch')),
      );
      await tester.pumpAndSettle();

      const statusId = 'screen.settings.save.status';
      expect(
        find.byKey(const ValueKey('$statusId.retry.button')),
        findsOneWidget,
      );
      expect(find.text('설정을 저장하지 못했습니다. 다시 시도해주세요.'), findsOneWidget);
      // 저장은 shared_preferences 대신 Fake를 쓴다. 재시도가 실제로 값을 남긴다.
      service.failSave = false;
      await tester.tap(find.byKey(const ValueKey('$statusId.retry.button')));
      await tester.pumpAndSettle();

      expect(service.saved, isNotEmpty);
    });
  });

  group('GridSettingsController', () {
    test('슬라이더 조작이 겹쳐도 마지막 값이 저장된다', () async {
      final service = _FakeGridSettingsService();
      final container = ProviderContainer(
        overrides: [gridSettingsServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = await _gridController(container);

      final gate = Completer<void>();
      service.saveGate = gate;
      final first = controller.update((s) => s.copyWith(opacity: 0.4));
      final second = controller.update((s) => s.copyWith(opacity: 0.6));
      final third = controller.update((s) => s.copyWith(opacity: 0.8));
      gate.complete();
      await Future.wait<void>([first, second, third]);

      // 미리보기는 마지막 선택을 즉시 보여준다.
      expect(
        container.read(gridSettingsControllerProvider).value!.opacity,
        0.8,
      );
      expect(container.read(gridSettingsSaveQueueProvider).isFailure, isFalse);
      expect(service.saved.last.opacity, 0.8);
    });

    test('저장 실패는 오류 상태가 아니라 저장 상태로만 드러난다', () async {
      final service = _FakeGridSettingsService(failSave: true);
      final container = ProviderContainer(
        overrides: [gridSettingsServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = await _gridController(container);

      await controller.update((s) => s.copyWith(opacity: 0.7));

      // 값 상태는 데이터로 유지된다. 저장 실패로 카메라가 꺼지지 않는다.
      final value = container.read(gridSettingsControllerProvider);
      expect(value.hasError, isFalse);
      expect(value.value!.opacity, 0.7);
      expect(container.read(gridSettingsSaveQueueProvider).canRetry, isTrue);

      service.failSave = false;
      await controller.retrySave();

      expect(container.read(gridSettingsSaveQueueProvider).isFailure, isFalse);
      expect(service.saved.last.opacity, 0.7);
    });

    testWidgets('격자 설정 패널은 저장 실패와 재시도를 보여준다', (tester) async {
      final service = _FakeGridSettingsService(failSave: true);
      _prepareWidgetTests();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [gridSettingsServiceProvider.overrideWithValue(service)],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: GridSettingsPanel()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('capture.grid.toggle')));
      await tester.pumpAndSettle();

      const statusId = 'capture.grid.save.status';
      expect(
        find.byKey(const ValueKey('$statusId.retry.button')),
        findsOneWidget,
      );
      // 값은 그대로 반영돼 미리보기가 유지된다.
      final toggle = tester.widget<Switch>(
        find.byKey(const ValueKey('capture.grid.toggle')),
      );
      expect(toggle.value, isFalse);

      service.failSave = false;
      await tester.tap(find.byKey(const ValueKey('$statusId.retry.button')));
      await tester.pumpAndSettle();

      expect(service.saved, isNotEmpty);
    });
  });
}

/// 격자 설정 컨트롤러를 구독을 유지한 채 만든다.
///
/// 컨트롤러는 autoDispose라 값만 읽으면 다음 마이크로태스크에 폐기된다.
/// 구독을 붙들어 카메라 화면처럼 계속 살아 있는 상태를 만든다. 로드는 생성자에서
/// 시작되므로 값이 채워질 때까지 마이크로태스크를 양보한다(실제 시간 미사용).
Future<GridSettingsController> _gridController(
  ProviderContainer container,
) async {
  final subscription = container.listen(
    gridSettingsControllerProvider,
    (_, _) {},
  );
  addTearDown(subscription.close);
  final controller = container.read(gridSettingsControllerProvider.notifier);
  for (var i = 0; i < 100; i++) {
    if (container.read(gridSettingsControllerProvider).value != null) {
      return controller;
    }
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('격자 설정 로드가 끝나지 않았습니다.');
}

/// 설정 화면/패널이 함께 쓰는 shared_preferences 목을 비운 상태로 준비한다.
void _prepareWidgetTests() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
}

class _FakeAppSettingsService implements AppSettingsService {
  AppSettings? persisted;
  final List<AppSettings> saved = [];
  bool failSave;

  /// 저장을 이 지연까지 붙들어 둔다.
  Completer<void>? saveGate;

  _FakeAppSettingsService({this.failSave = false});

  @override
  Future<AppSettings> load() async => persisted ?? AppSettings.defaults;

  @override
  Future<void> save(AppSettings settings) async {
    final gate = saveGate;
    if (gate != null) await gate.future;
    if (failSave) throw StateError('설정 저장 실패(테스트)');
    persisted = settings;
    saved.add(settings);
  }
}

class _FakeGridSettingsService implements GridSettingsService {
  GridSettings persisted = GridSettings.defaults;
  final List<GridSettings> saved = [];
  bool failSave;

  /// 저장을 이 지연까지 붙들어 둔다.
  Completer<void>? saveGate;

  _FakeGridSettingsService({this.failSave = false});

  @override
  Future<GridSettings> load() async => persisted;

  @override
  Future<void> save(GridSettings settings) async {
    final gate = saveGate;
    if (gate != null) await gate.future;
    if (failSave) throw StateError('격자 저장 실패(테스트)');
    persisted = settings;
    saved.add(settings);
  }

  @override
  Future<void> reset() async {
    persisted = GridSettings.defaults;
  }
}
