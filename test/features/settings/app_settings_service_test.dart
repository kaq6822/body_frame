import 'dart:io';

import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/services/photo_storage_service.dart';
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

  test('손상된 설정은 예외 대신 잠금 없는 안전 기본값으로 복구한다', () async {
    SharedPreferences.setMockInitialValues({'app_settings': '{invalid-json'});
    final service = AppSettingsServiceImpl();

    final loaded = await service.load();

    expect(loaded.lockMode, LockMode.none);
    expect(loaded.biometricEnabled, isFalse);
  });

  test('UI에서 처리할 수 없는 설정 범위도 기본값으로 복구한다', () async {
    SharedPreferences.setMockInitialValues({
      'app_settings': const AppSettings(autoLockSeconds: 999).toJson(),
    });

    final loaded = await AppSettingsServiceImpl().load();

    expect(loaded.autoLockSeconds, AppSettings.defaults.autoLockSeconds);
  });

  test('스튜디오 로고는 앱 저장소 상대경로로 저장하고 명시적으로 지울 수 있다', () async {
    final service = AppSettingsServiceImpl();
    final withLogo = AppSettings.defaults.copyWith(
      studioLogoPath: 'photos/studio-assets/logo.png',
    );
    await service.save(withLogo);

    expect(
      (await service.load()).studioLogoPath,
      'photos/studio-assets/logo.png',
    );
    expect(withLogo.copyWith(clearStudioLogoPath: true).studioLogoPath, isNull);
  });

  test('기존 스튜디오 로고 절대경로를 로드할 때 상대경로로 마이그레이션한다', () async {
    final root = await Directory.systemTemp.createTemp(
      'body_frame_settings_logo_',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final storage = PhotoStorageServiceImpl(rootPath: root.path);
    final absolute = await storage.saveBytes(
      memberId: 'studio-assets',
      bytes: const [1, 2, 3],
      fileName: 'logo.png',
    );
    SharedPreferences.setMockInitialValues({
      'app_settings': AppSettings(studioLogoPath: absolute).toJson(),
    });

    final loaded = await AppSettingsServiceImpl(storage: storage).load();

    expect(loaded.studioLogoPath, 'photos/studio-assets/logo.png');
  });
}
