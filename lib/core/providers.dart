import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database/app_database.dart';
import 'repositories/body_photo_repository.dart';
import 'repositories/photo_ingest_repository.dart';
import 'repositories/photo_record_repository.dart';
import 'services/app_logger.dart';
import 'services/grid_settings_service.dart';
import 'services/photo_storage_service.dart';

/// core 계층 의존성 주입 지점.
///
/// 모든 provider는 테스트에서 `ProviderScope(overrides: [...])`로 교체할 수
/// 있다. 리포지토리는 추상 인터페이스 타입으로 노출하므로, 테스트에서는
/// 인메모리 DB 구현이나 Fake로 손쉽게 대체한다.
///
/// 예) 테스트 주입:
/// ```dart
/// ProviderScope(overrides: [
///   photoRecordRepositoryProvider.overrideWithValue(FakePhotoRecordRepository()),
/// ], child: ...)
/// ```

/// 구조화 로거(싱글턴).
final appLoggerProvider = Provider<AppLogger>((ref) => AppLogger.instance);

/// sqflite 데이터베이스. 앱 전체에서 단일 인스턴스를 공유한다.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(logger: ref.watch(appLoggerProvider));
  ref.onDispose(db.close);
  return db;
});

/// 사진 파일 저장 서비스.
final photoStorageServiceProvider = Provider<PhotoStorageService>((ref) {
  return PhotoStorageServiceImpl(logger: ref.watch(appLoggerProvider));
});

/// 격자 설정 영속화 서비스.
final gridSettingsServiceProvider = Provider<GridSettingsService>((ref) {
  return GridSettingsServiceImpl(logger: ref.watch(appLoggerProvider));
});

/// 체형 사진 리포지토리.
final bodyPhotoRepositoryProvider = Provider<BodyPhotoRepository>((ref) {
  return BodyPhotoRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    storage: ref.watch(photoStorageServiceProvider),
    logger: ref.watch(appLoggerProvider),
  );
});

/// 파일 준비를 마친 촬영 기록과 사진을 단일 transaction으로 등록한다.
final photoIngestRepositoryProvider = Provider<PhotoIngestRepository>((ref) {
  return PhotoIngestRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    storage: ref.watch(photoStorageServiceProvider),
    logger: ref.watch(appLoggerProvider),
  );
});

/// 촬영 기록 리포지토리.
final photoRecordRepositoryProvider = Provider<PhotoRecordRepository>((ref) {
  return PhotoRecordRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    storage: ref.watch(photoStorageServiceProvider),
    logger: ref.watch(appLoggerProvider),
  );
});
