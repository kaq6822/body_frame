import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/features/settings/services/app_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('AppSettingsService', () {
    test('저장된 값이 없으면 기본값을 반환한다', () async {
      final settings = await AppSettingsServiceImpl().load();

      expect(settings.defaultGrid, GridSettings.defaults);
      expect(settings.defaultExportOptions.includeShotDate, isTrue);
      expect(settings.defaultExportOptions.includeLabel, isTrue);
      expect(settings.defaultExportOptions.includeMemo, isFalse);
      expect(settings.defaultExportOptions.includeGrid, isFalse);
    });

    test('저장한 설정을 그대로 다시 읽는다', () async {
      final service = AppSettingsServiceImpl();
      const saved = AppSettings(
        defaultGrid: GridSettings(opacity: 0.8, spacing: 60),
        defaultExportOptions: ExportImageOptions(
          includeShotDate: false,
          includeLabel: false,
          includeMemo: true,
          includeGrid: true,
        ),
      );

      await service.save(saved);
      final loaded = await service.load();

      expect(loaded.defaultGrid.opacity, 0.8);
      expect(loaded.defaultGrid.spacing, 60);
      expect(loaded.defaultExportOptions.includeShotDate, isFalse);
      expect(loaded.defaultExportOptions.includeLabel, isFalse);
      expect(loaded.defaultExportOptions.includeMemo, isTrue);
      expect(loaded.defaultExportOptions.includeGrid, isTrue);
    });

    test('손상된 JSON은 기본값으로 대체한다', () async {
      SharedPreferences.setMockInitialValues({'app_settings': '{not json'});

      final settings = await AppSettingsServiceImpl().load();

      expect(settings.defaultGrid, GridSettings.defaults);
    });

    test('범위를 벗어난 격자 값이 저장돼 있으면 기본값으로 대체한다', () async {
      SharedPreferences.setMockInitialValues({
        'app_settings': const AppSettings(
          defaultGrid: GridSettings(opacity: 5),
        ).toJson(),
      });

      final settings = await AppSettingsServiceImpl().load();

      expect(settings.defaultGrid, GridSettings.defaults);
    });

    test('범위를 벗어난 격자 값은 저장을 거부한다', () async {
      final service = AppSettingsServiceImpl();

      await expectLater(
        service.save(const AppSettings(defaultGrid: GridSettings(spacing: 0))),
        throwsArgumentError,
      );
    });
  });

  group('CaptureOptions', () {
    test('기본값은 타이머 끔 + 카운트다운 피드백 켬이다', () async {
      final settings = await AppSettingsServiceImpl().load();

      expect(settings.capture.timerSeconds, 0);
      expect(settings.capture.countdownFeedback, isTrue);
    });

    test('저장한 촬영 편의 설정을 그대로 다시 읽는다', () async {
      final service = AppSettingsServiceImpl();

      await service.save(
        const AppSettings(
          capture: CaptureOptions(timerSeconds: 5, countdownFeedback: false),
        ),
      );
      final loaded = await service.load();

      expect(loaded.capture.timerSeconds, 5);
      expect(loaded.capture.countdownFeedback, isFalse);
    });

    test('촬영 편의 설정이 없던 버전의 저장값도 기본값으로 열린다', () async {
      // capture 키가 없는 구버전 JSON.
      SharedPreferences.setMockInitialValues({
        'app_settings':
            '{"defaultGrid":{"visible":true,"opacity":0.5,"lineWidth":1.0,'
            '"spacing":40.0,"colorValue":4294967295}}',
      });

      final settings = await AppSettingsServiceImpl().load();

      expect(settings.capture, CaptureOptions.defaults);
    });

    test('순환 목록에 없는 타이머 값은 끔으로 정규화한다', () {
      // 다른 버전에서 저장된 값이 들어와도 타이머 버튼 순환이 깨지지 않아야 한다.
      final restored = CaptureOptions.fromMap(const {'timerSeconds': 7});

      expect(restored.timerSeconds, 0);
      expect(CaptureOptions.normalizeTimer(3), 3);
      expect(CaptureOptions.normalizeTimer(99), 0);
    });
  });
}
