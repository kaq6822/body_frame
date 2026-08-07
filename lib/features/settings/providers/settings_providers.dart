import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../services/app_settings_service.dart';
import '../services/storage_stats_service.dart';

/// settings 기능 전용 의존성 주입 지점.
///
/// core 리포지토리/서비스(사진·격자 등)는 `lib/core/providers.dart`의
/// provider를 그대로 재사용하고, 이 파일에서는 settings 기능이 추가한
/// 서비스(설정 영속화·저장 공간 통계)만 정의한다.

final appSettingsServiceProvider = Provider<AppSettingsService>((ref) {
  return AppSettingsServiceImpl(logger: ref.watch(appLoggerProvider));
});

final storageStatsServiceProvider = Provider<StorageStatsService>((ref) {
  return StorageStatsServiceImpl(
    database: ref.watch(appDatabaseProvider),
    storage: ref.watch(photoStorageServiceProvider),
  );
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
    await ref.read(appSettingsServiceProvider).save(next);
    state = AsyncValue.data(next);
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
