import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/features/settings/services/app_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('저장한 적 없으면 기본값을 반환한다', () async {
    final service = AppSettingsServiceImpl();
    final loaded = await service.load();
    expect(loaded.lockMode, LockMode.none);
    expect(loaded.studioName, isNull);
  });

  test('저장 후 다시 불러오면 동일한 값이 유지된다(라운드트립)', () async {
    final service = AppSettingsServiceImpl();
    final settings = AppSettings.defaults.copyWith(
      lockMode: LockMode.pin,
      biometricEnabled: true,
      autoLockSeconds: 60,
      studioName: '테스트 스튜디오',
    );

    await service.save(settings);
    final loaded = await service.load();

    expect(loaded.lockMode, LockMode.pin);
    expect(loaded.biometricEnabled, isTrue);
    expect(loaded.autoLockSeconds, 60);
    expect(loaded.studioName, '테스트 스튜디오');
  });
}
