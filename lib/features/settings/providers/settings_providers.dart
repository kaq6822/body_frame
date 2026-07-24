import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/repositories/member_repository.dart';
import '../services/app_settings_service.dart';
import '../services/backup_service.dart';
import '../services/lock_service.dart';
import '../services/storage_stats_service.dart';

/// settings 기능 전용 의존성 주입 지점.
///
/// core 리포지토리/서비스(멤버·사진·격자 등)는 `lib/core/providers.dart`의
/// provider를 그대로 재사용하고, 이 파일에서는 settings 기능이 추가한
/// 서비스(설정 영속화·잠금·백업·저장 공간 통계)만 정의한다.

final appSettingsServiceProvider = Provider<AppSettingsService>((ref) {
  return AppSettingsServiceImpl(logger: ref.watch(appLoggerProvider));
});

final lockServiceProvider = Provider<LockService>((ref) {
  return LockServiceImpl(logger: ref.watch(appLoggerProvider));
});

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupServiceImpl(
    database: ref.watch(appDatabaseProvider),
    storage: ref.watch(photoStorageServiceProvider),
    settingsService: ref.watch(appSettingsServiceProvider),
    logger: ref.watch(appLoggerProvider),
  );
});

final storageStatsServiceProvider = Provider<StorageStatsService>((ref) {
  return StorageStatsServiceImpl(database: ref.watch(appDatabaseProvider));
});

/// 앱 설정(AppSettings) 상태. 화면들이 공유하는 단일 소스.
class AppSettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() {
    return ref.watch(appSettingsServiceProvider).load();
  }

  Future<void> updateSettings(
    AppSettings Function(AppSettings current) updater,
  ) async {
    final current = state.valueOrNull ?? AppSettings.defaults;
    final next = updater(current);
    state = AsyncValue.data(next);
    await ref.read(appSettingsServiceProvider).save(next);
  }
}

final appSettingsControllerProvider =
    AsyncNotifierProvider<AppSettingsController, AppSettings>(
  AppSettingsController.new,
);

/// 저장 공간 사용량(screen.settings.storage).
final storageUsageProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(storageStatsServiceProvider).collect();
});

/// 회원별 백업 대상 선택용 회원 목록(screen.settings.backup).
final backupMemberListProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(memberRepositoryProvider).list(sort: MemberSort.name);
});
