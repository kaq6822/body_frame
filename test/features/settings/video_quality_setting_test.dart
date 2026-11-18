import 'package:bodymark/core/korean_text.dart';
import 'package:bodymark/core/models/models.dart';
import 'package:bodymark/core/providers.dart';
import 'package:bodymark/core/services/grid_settings_service.dart';
import 'package:bodymark/features/capture/camera/video_camera_controller.dart';
import 'package:bodymark/features/settings/providers/settings_providers.dart';
import 'package:bodymark/features/settings/services/app_settings_service.dart';
import 'package:bodymark/features/settings/settings_screen.dart';
import 'package:bodymark/features/videos/video_providers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingSettingsService implements AppSettingsService {
  @override
  Future<AppSettings> load() async => throw StateError('읽기 실패');

  @override
  Future<void> save(AppSettings settings) async {}
}

AppSettings _withQuality(VideoQuality quality) => AppSettings.defaults.copyWith(
  capture: CaptureOptions.defaults.copyWith(videoQuality: quality),
);

/// 앱 안 동영상 촬영 화질 설정: 기본 720p, 영속화, 카메라 해상도 순서, 설정 화면.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('영속화', () {
    test('저장된 값이 없으면 표준 720p다', () async {
      final loaded = await AppSettingsServiceImpl().load();
      expect(loaded.capture.videoQuality, VideoQuality.standard);
    });

    test('고른 화질을 저장하고 다시 읽는다', () async {
      final service = AppSettingsServiceImpl();
      await service.save(_withQuality(VideoQuality.high));
      final loaded = await AppSettingsServiceImpl().load();
      expect(loaded.capture.videoQuality, VideoQuality.high);
    });

    test('화질이 없던 버전이나 알 수 없는 값은 표준으로 연다', () {
      final old = AppSettings.fromJson('{"capture":{"timerSeconds":3}}');
      expect(old.capture.videoQuality, VideoQuality.standard);
      expect(old.capture.timerSeconds, 3);
      final unknown = AppSettings.fromJson(
        '{"capture":{"videoQuality":"ultra"}}',
      );
      expect(unknown.capture.videoQuality, VideoQuality.standard);
    });
  });

  group('카메라 해상도 순서', () {
    test('표준은 720p부터, 고화질은 1080p부터 아래로만 내려간다', () {
      expect(videoResolutionChainFor(VideoQuality.standard), [
        ResolutionPreset.high,
        ResolutionPreset.medium,
      ]);
      expect(videoResolutionChainFor(VideoQuality.high), [
        ResolutionPreset.veryHigh,
        ResolutionPreset.high,
        ResolutionPreset.medium,
      ]);
    });

    Future<List<ResolutionPreset>> presetsFrom(ProviderContainer c) {
      final controller =
          c.read(videoCameraControllerFactoryProvider)()
              as DeviceVideoCameraController;
      return controller.resolvePresets();
    }

    test('팩토리가 만든 컨트롤러는 저장된 화질부터 시도한다', () async {
      SharedPreferences.setMockInitialValues({
        'app_settings': _withQuality(VideoQuality.high).toJson(),
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(await presetsFrom(container), [
        ResolutionPreset.veryHigh,
        ResolutionPreset.high,
        ResolutionPreset.medium,
      ]);
    });

    test('저장값이 없으면 720p부터 시도한다', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(await presetsFrom(container), [
        ResolutionPreset.high,
        ResolutionPreset.medium,
      ]);
    });

    test('화질 provider를 바꾸면 그 화질로 연다', () async {
      final container = ProviderContainer(
        overrides: [
          videoQualityProvider.overrideWith((ref) async => VideoQuality.high),
        ],
      );
      addTearDown(container.dispose);
      expect((await presetsFrom(container)).first, ResolutionPreset.veryHigh);
    });

    test('설정을 읽지 못해도 촬영은 막지 않고 720p로 연다', () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsServiceProvider.overrideWithValue(
            _FailingSettingsService(),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(await presetsFrom(container), [
        ResolutionPreset.high,
        ResolutionPreset.medium,
      ]);
    });
  });

  group('설정 화면', () {
    Future<void> pumpSettings(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gridSettingsServiceProvider.overrideWithValue(
              GridSettingsServiceImpl(),
            ),
            unlinkedRecordCountProvider.overrideWith((ref) async => 0),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    const item = ValueKey('settings.videoQuality.item');

    // 하단 탭 막대에 가리지 않도록 목록 가운데로 끌어온다.
    Future<void> reveal(WidgetTester tester) async {
      await Scrollable.ensureVisible(
        tester.element(find.byKey(item)),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
    }

    const value = ValueKey('settings.videoQuality.value');

    testWidgets('기본은 표준 720p이고 시트에서 고화질을 고르면 저장된다', (tester) async {
      await pumpSettings(tester);
      await reveal(tester);
      expect(tester.widget<Text>(find.byKey(value)).data, '표준 720p');

      await tester.tap(find.byKey(item));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('settings.videoQuality.sheet')),
        findsOneWidget,
      );
      expect(find.text(keepPhrasesWhole('자세·동작 확인에 충분해요')), findsOneWidget);
      expect(
        find.text(keepPhrasesWhole('세부까지 선명해요 · 용량이 더 커요')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings.videoQuality.note')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('settings.videoQuality.option.high')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('settings.videoQuality.sheet')),
        findsNothing,
      );
      expect(tester.widget<Text>(find.byKey(value)).data, '고화질 1080p');
      final saved = await AppSettingsServiceImpl().load();
      expect(saved.capture.videoQuality, VideoQuality.high);
    });

    testWidgets('같은 화질을 다시 고르면 저장하지 않는다', (tester) async {
      await pumpSettings(tester);
      await reveal(tester);
      await tester.tap(find.byKey(item));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('settings.videoQuality.option.standard')),
      );
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_settings'), isNull);
      expect(tester.widget<Text>(find.byKey(value)).data, '표준 720p');
    });
  });
}
